import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// App-wide user settings persisted to settings.json.
class AppSettings extends ChangeNotifier {
  static AppSettings? _instance;
  static AppSettings get instance {
    final i = _instance;
    if (i == null) throw StateError('call AppSettings.load() first');
    return i;
  }

  static bool get isLoaded => _instance != null;

  String? _downloadDir;
  int _maxWorkers = 8;

  String? get downloadDir => _downloadDir;
  int get maxWorkers => _maxWorkers;

  File? _file;

  AppSettings._();

  /// Loads (once) the persisted settings. Safe to call repeatedly.
  static Future<AppSettings> load() async {
    if (_instance != null) return _instance!;
    final s = AppSettings._();
    try {
      final docs = await getApplicationDocumentsDirectory();
      s._file = File('${docs.path}${Platform.pathSeparator}settings.json');
      if (s._file!.existsSync()) {
        final j = jsonDecode(await s._file!.readAsString()) as Map<String, dynamic>;
        s._downloadDir = j['downloadDir'] as String?;
        s._maxWorkers = ((j['maxWorkers'] as num?)?.toInt() ?? 8).clamp(2, 16);
      }
    } catch (_) {}
    _instance = s;
    return s;
  }

  Future<void> setDownloadDir(String? path) async {
    _downloadDir = (path == null || path.trim().isEmpty) ? null : path.trim();
    notifyListeners();
    await _save();
  }

  Future<void> setMaxWorkers(int v) async {
    _maxWorkers = v.clamp(2, 16);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      await _file?.writeAsString(jsonEncode({
        'downloadDir': _downloadDir,
        'maxWorkers': _maxWorkers,
      }));
    } catch (_) {}
  }

  /// The platform-appropriate default download folder (used until the user
  /// picks their own).
  static Future<Directory> defaultDownloadDir() async {
    if (!kIsWeb && Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? '';
      if (home.isNotEmpty) {
        return Directory('$home${Platform.pathSeparator}Downloads${Platform.pathSeparator}MDownloader');
      }
    }
    try {
      final dl = await getDownloadsDirectory();
      if (dl != null) {
        return Directory('${dl.path}${Platform.pathSeparator}MDownloader');
      }
    } catch (_) {}
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}downloads');
  }

  /// The directory downloads should be saved to right now.
  Future<Directory> resolveDownloadDir() async {
    final p = _downloadDir;
    if (p != null && p.isNotEmpty) return Directory(p);
    return defaultDownloadDir();
  }
}
