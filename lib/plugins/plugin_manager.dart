import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../models/download.dart';
import '../models/media.dart';
import 'plugin_bootstrap.dart';

/// Metadata loaded from a plugin's plugin.json.
class PluginInfo {
  final String packageName;
  final String name;
  final int version;
  final String description;
  final String baseUrl;
  final String icon;
  final Directory dir;
  bool enabled;

  PluginInfo({
    required this.packageName,
    required this.name,
    required this.version,
    required this.description,
    required this.baseUrl,
    required this.icon,
    required this.dir,
    this.enabled = true,
  });

  Map<String, dynamic> get manifest => {
        'packageName': packageName,
        'name': name,
        'version': version,
        'baseUrl': baseUrl,
        'description': description,
        'icon': icon,
      };

  factory PluginInfo.fromJson(Map<String, dynamic> j, Directory dir) => PluginInfo(
        packageName: (j['packageName'] ?? '').toString(),
        name: (j['name'] ?? (j['packageName'] ?? 'Plugin')).toString(),
        version: (j['version'] is num) ? (j['version'] as num).toInt() : 1,
        description: (j['description'] ?? '').toString(),
        baseUrl: (j['baseUrl'] ?? '').toString(),
        icon: (j['icon'] ?? '').toString(),
        dir: dir,
      );
}

/// One downloadable copy resolved by a plugin.
class PluginStreamResult {
  final String pluginName;
  final String label;
  final String url;
  final DownloadKind kind;
  final Map<String, String> headers;

  const PluginStreamResult({
    required this.pluginName,
    required this.label,
    required this.url,
    this.kind = DownloadKind.direct,
    this.headers = const {},
  });
}

/// One content item returned by a plugin's `search` function.
class PluginSearchItem {
  final String pluginName;
  final String pluginPackage;
  final String title;
  final String url; // plugin-specific payload (JSON string) for loadStreams
  final String posterUrl;
  final String type; // 'movie' | 'series' | ''
  const PluginSearchItem({
    required this.pluginName,
    required this.pluginPackage,
    required this.title,
    required this.url,
    this.posterUrl = '',
    this.type = '',
  });
}

/// Scans the plugins folder, loads every plugin into the JS engine, and runs
/// them to resolve download links for a title.
class PluginManager extends ChangeNotifier {
  final MdnEngine engine;
  final Directory pluginsDir;
  final Directory storageDir;
  final List<PluginInfo> plugins = [];
  final Set<String> _enabled = {};

  bool _ready = false;
  bool get ready => _ready;

  PluginManager._(this.engine, this.pluginsDir, this.storageDir);

  static Future<PluginManager> create() async {
    final docs = await getApplicationDocumentsDirectory();
    final base = _pluginsBase(docs);
    final pluginsDir = Directory('${base.path}${Platform.pathSeparator}plugins');
    final storageDir = Directory('${base.path}${Platform.pathSeparator}plugin_data');
    await pluginsDir.create(recursive: true);
    await storageDir.create(recursive: true);
    final engine = MdnEngine(storageDir: storageDir);
    return PluginManager._(engine, pluginsDir, storageDir);
  }

  /// Windows: <exe>/plugins · Android: <appDocuments>/plugins
  static Directory _pluginsBase(Directory docs) {
    if (!kIsWeb && Platform.isWindows) {
      try {
        final exe = File(Platform.resolvedExecutable).parent;
        return exe;
      } catch (_) {}
    }
    return docs;
  }

  Future<void> init() async {
    engine.init();
    await _ensureBundled();
    await _loadState();
    await rescan();
    _ready = true;
    notifyListeners();
  }

  /// Copies the example plugins shipped with the app into the plugins folder
  /// on first run, so users can read/edit them.
  Future<void> _ensureBundled() async {
    const bundled = ['youtube', 'template', 'goldmines', 'ultra', 'pen'];
    for (final name in bundled) {
      final dir = Directory('${pluginsDir.path}${Platform.pathSeparator}$name');
      if (dir.existsSync()) continue;
      await dir.create(recursive: true);
      for (final file in ['plugin.json', 'plugin.js']) {
        final target = File('${dir.path}${Platform.pathSeparator}$file');
        if (target.existsSync()) continue;
        try {
          final data = await _readBundledAsset('assets/plugins/$name/$file');
          await target.writeAsString(data);
        } catch (_) {}
      }
    }
  }

  Future<String> _readBundledAsset(String path) async {
    return rootBundle.loadString(path);
  }

  Future<void> _loadState() async {
    final f = File('${storageDir.path}${Platform.pathSeparator}plugins_state.json');
    if (!f.existsSync()) return;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final enabled = j['enabled'];
      if (enabled is List) {
        _enabled.addAll(enabled.whereType<String>());
      }
    } catch (_) {}
  }

  Future<void> _saveState() async {
    try {
      final f = File('${storageDir.path}${Platform.pathSeparator}plugins_state.json');
      await f.writeAsString(jsonEncode({'enabled': _enabled.toList()}));
    } catch (_) {}
  }

  Future<void> rescan() async {
    final seen = <String, PluginInfo>{};
    if (pluginsDir.existsSync()) {
      for (final e in pluginsDir.listSync()) {
        if (e is! Directory) continue;
        final info = await _loadFromDir(e);
        if (info != null) seen[info.packageName] = info;
      }
    }
    plugins
      ..clear()
      ..addAll(seen.values);
    for (final p in plugins) {
      if (_enabled.isEmpty) {
        // first run: enable everything
        p.enabled = true;
        _enabled.add(p.packageName);
      } else {
        p.enabled = _enabled.contains(p.packageName);
      }
    }
    // Re-load every plugin into the engine (re-evaluate all sources).
    for (final p in plugins) {
      _loadIntoEngine(p);
    }
    await _saveState();
    notifyListeners();
  }

  Future<PluginInfo?> _loadFromDir(Directory dir) async {
    final manifestFile = File('${dir.path}${Platform.pathSeparator}plugin.json');
    if (!manifestFile.existsSync()) return null;
    try {
      final j = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      return PluginInfo.fromJson(j, dir);
    } catch (_) {
      return null;
    }
  }

  void _loadIntoEngine(PluginInfo p) {
    try {
      final src = File('${p.dir.path}${Platform.pathSeparator}plugin.js').readAsStringSync();
      engine.loadPlugin(p.packageName, p.manifest, src);
    } catch (e) {
      debugPrint('plugin ${p.packageName} failed to load: $e');
    }
  }

  Future<void> setEnabled(PluginInfo p, bool value) async {
    p.enabled = value;
    if (value) {
      _enabled.add(p.packageName);
      _loadIntoEngine(p);
    } else {
      _enabled.remove(p.packageName);
    }
    await _saveState();
    notifyListeners();
  }

  Future<void> deletePlugin(PluginInfo p) async {
    _enabled.remove(p.packageName);
    plugins.remove(p);
    try {
      if (p.dir.existsSync()) await p.dir.delete(recursive: true);
    } catch (_) {}
    await _saveState();
    notifyListeners();
  }

  /// Picks a plugin package (.zip or .sky) and installs it.
  Future<bool> installFromPicker() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'sky'],
      );
      if (files.isEmpty) return false;
      final path = files.first.path;
      if (path == null) return false;
      return await installArchive(File(path));
    } catch (_) {
      return false;
    }
  }

  Future<bool> installArchive(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      String? manifestStr;
      String? jsStr;
      for (final f in archive) {
        if (f.isFile) {
          final name = f.name.split('/').last;
          if (name == 'plugin.json') manifestStr = utf8.decode(f.content as List<int>);
          if (name == 'plugin.js') jsStr = utf8.decode(f.content as List<int>);
        }
      }
      if (manifestStr == null || jsStr == null) return false;
      final manifest = jsonDecode(manifestStr) as Map<String, dynamic>;
      final ns = (manifest['packageName'] ?? '').toString();
      if (ns.isEmpty) return false;
      final dir = Directory('${pluginsDir.path}${Platform.pathSeparator}${ns.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}');
      await dir.create(recursive: true);
      await File('${dir.path}${Platform.pathSeparator}plugin.json').writeAsString(manifestStr);
      await File('${dir.path}${Platform.pathSeparator}plugin.js').writeAsString(jsStr);
      await rescan();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Runs every enabled plugin's loadStreams() for a title, in parallel.
  Future<List<PluginStreamResult>> resolveStreams(
    MediaItem item, {
    int? season,
    int? episode,
  }) async {
    final urlJson = jsonEncode({
      'tmdbId': item.id,
      'title': item.title,
      'year': item.year,
      'mediaType': item.mediaType,
      if (season != null) 'season': season,
      if (episode != null) 'episode': episode,
    });

    final enabled = plugins.where((p) => p.enabled).toList();
    if (enabled.isEmpty) return const [];

    final futures = enabled.map((p) async {
      try {
        final res = await engine.invoke(p.packageName, 'loadStreams', [urlJson]);
        return _parseStreams(p, res);
      } catch (_) {
        return const <PluginStreamResult>[];
      }
    });

    final results = await Future.wait(futures);
    return results.expand((e) => e).toList();
  }

  List<PluginStreamResult> _parseStreams(PluginInfo p, dynamic res) {
    if (res is! Map) return const <PluginStreamResult>[];
    if (res['success'] != true) return const <PluginStreamResult>[];
    final data = res['data'];
    if (data is! List) return const <PluginStreamResult>[];
    final out = <PluginStreamResult>[];
    for (final s in data) {
      if (s is! Map) continue;
      final url = s['url'];
      if (url is! String || url.isEmpty) continue;
      final kindStr = (s['kind'] ?? 'direct').toString();
      final kind = kindStr == 'hls' ? DownloadKind.hls : DownloadKind.direct;
      final headers = <String, String>{};
      if (s['headers'] is Map) {
        (s['headers'] as Map).forEach((k, v) => headers[k.toString()] = v?.toString() ?? '');
      }
      final label = (s['label'] ?? url.split('.').last).toString();
      out.add(PluginStreamResult(
        pluginName: p.name,
        label: label,
        url: url,
        kind: kind,
        headers: headers,
      ));
    }
    return out;
  }

  /// Runs `search` on every enabled plugin and merges the results.
  Future<List<PluginSearchItem>> searchAll(String query, {Set<String>? onlyPackages}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final enabled = plugins.where((p) => p.enabled && (onlyPackages == null || onlyPackages.contains(p.packageName))).toList();
    if (enabled.isEmpty) return const [];

    final futures = enabled.map((p) async {
      try {
        final res = await engine.invoke(p.packageName, 'search', [q]);
        if (res is! Map || res['success'] != true) return const <PluginSearchItem>[];
        final data = res['data'];
        if (data is! List) return const <PluginSearchItem>[];
        final out = <PluginSearchItem>[];
        for (final it in data) {
          if (it is! Map) continue;
          final url = it['url'];
          if (url is! String || url.isEmpty) continue;
          out.add(PluginSearchItem(
            pluginName: p.name,
            pluginPackage: p.packageName,
            title: (it['title'] ?? 'Untitled').toString(),
            url: url,
            posterUrl: (it['posterUrl'] ?? '').toString(),
            type: (it['type'] ?? '').toString(),
          ));
        }
        return out;
      } catch (_) {
        return const <PluginSearchItem>[];
      }
    });

    final results = await Future.wait(futures);
    return results.expand((e) => e).toList();
  }

  /// Resolves download streams for a plugin search item's payload URL.
  Future<List<PluginStreamResult>> resolveUrl(String packageName, String urlJson) async {
    PluginInfo? p;
    for (final x in plugins) {
      if (x.packageName == packageName) {
        p = x;
        break;
      }
    }
    if (p == null) return const [];
    try {
      final res = await engine.invoke(packageName, 'loadStreams', [urlJson]);
      return _parseStreams(p, res);
    } catch (_) {
      return const [];
    }
  }
}
