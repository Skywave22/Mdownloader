import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/config.dart';
import '../services/scraper/scraper.dart';
import 'hls_downloader.dart';
import 'segmented_downloader.dart';

/// A queued download task (wraps one SegmentedDownloader or HlsDownloader).
class DownloadTask extends ChangeNotifier {
  final String id;
  final String name;
  final String url;
  final DownloadKind kind;
  final Map<String, String> headers;
  DStatus status = DStatus.idle;
  int totalBytes = 0;
  int downloadedBytes = 0;
  double bytesPerSec = 0;
  String? error;
  File? file;
  Object? _engine;

  DownloadTask({
    required this.id,
    required this.name,
    required this.url,
    this.kind = DownloadKind.direct,
    this.headers = const {},
  });

  Future<void> start(Directory saveDir) async {
    if (status == DStatus.running || status == DStatus.merging) return;
    file = File('${saveDir.path}${Platform.pathSeparator}$name');
    final dir = Directory('${saveDir.path}${Platform.pathSeparator}.$id');
    void onProgress(DProgress p) {
      status = p.status;
      totalBytes = p.totalBytes;
      downloadedBytes = p.downloadedBytes;
      bytesPerSec = p.bytesPerSec;
      error = p.error;
      notifyListeners();
    }
    if (kind == DownloadKind.hls) {
      final hls = HlsDownloader(url: url, dir: dir, fileName: name, headers: headers, onProgress: onProgress);
      _engine = hls;
      await hls.start();
    } else {
      final dl = SegmentedDownloader(
        url: url,
        dir: dir,
        fileName: name,
        headers: headers,
        maxWorkers: AppConfig.maxWorkers,
        chunkSize: AppConfig.autoChunkSize,
        onProgress: onProgress,
      );
      _engine = dl;
      await dl.start();
    }
    notifyListeners();
  }

  void pause() {
    final e = _engine;
    if (e is SegmentedDownloader) e.pause();
    if (e is HlsDownloader) e.cancel();
  }

  void cancel() {
    final e = _engine;
    if (e is SegmentedDownloader) e.cancel();
    if (e is HlsDownloader) e.cancel();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'kind': kind.name,
        'headers': headers,
      };

  static DownloadTask fromJson(Map<String, dynamic> j) => DownloadTask(
        id: j['id'] as String,
        name: j['name'] as String,
        url: j['url'] as String,
        kind: DownloadKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => DownloadKind.direct),
        headers: ((j['headers'] as Map?) ?? const {}).cast<String, String>(),
      );
}

/// Owns the task list, saves/restores it, and provides the save directory.
class DownloadManager extends ChangeNotifier {
  final List<DownloadTask> tasks = [];
  Directory? _saveDir;

  Directory get saveDir {
    if (_saveDir == null) throw StateError('call init() first');
    return _saveDir!;
  }

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _saveDir = Directory('${docs.path}${Platform.pathSeparator}downloads');
    await _saveDir!.create(recursive: true);
    await _restore();
  }

  Future<void> _restore() async {
    final f = File('${_saveDir!.path}${Platform.pathSeparator}tasks.json');
    if (!f.existsSync()) return;
    try {
      final list = jsonDecode(await f.readAsString()) as List;
      for (final j in list.whereType<Map>()) {
        final t = DownloadTask.fromJson(j.cast<String, dynamic>());
        // completed tasks without a file are stale
        final file = File('${_saveDir!.path}${Platform.pathSeparator}${t.name}');
        t.status = file.existsSync() ? DStatus.completed : DStatus.paused;
        if (file.existsSync()) {
          t.file = file;
          t.totalBytes = file.lengthSync();
          t.downloadedBytes = file.lengthSync();
        }
        tasks.add(t);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<DownloadTask> enqueue({
    required String name,
    required String url,
    DownloadKind kind = DownloadKind.direct,
    Map<String, String> headers = const {},
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final task = DownloadTask(id: id, name: _safeName(name), url: url, kind: kind, headers: headers);
    tasks.insert(0, task);
    await _persist();
    notifyListeners();
    return task;
  }

  Future<void> _persist() async {
    try {
      final f = File('${_saveDir!.path}${Platform.pathSeparator}tasks.json');
      await f.writeAsString(jsonEncode(tasks.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> remove(DownloadTask task) async {
    task.cancel();
    tasks.remove(task);
    await _persist();
    notifyListeners();
  }

  String _safeName(String raw) {
    var n = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (n.isEmpty) n = 'download';
    return n;
  }
}
