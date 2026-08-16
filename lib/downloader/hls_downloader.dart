import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'segmented_downloader.dart' show DProgress, DStatus;

/// Downloads an HLS stream (master → variant → segments) with no ffmpeg:
/// fetch every TS segment in parallel, then concatenate them in playlist order
/// into a single playable .ts file. VOD only (EXT-X-ENDLIST).
class HlsDownloader {
  final String url;
  final Directory dir;
  final String fileName;
  final Map<String, String> headers;
  final int workers;
  final void Function(DProgress)? onProgress;

  HlsDownloader({
    required this.url,
    required this.dir,
    required this.fileName,
    this.headers = const {},
    this.workers = 8,
    this.onProgress,
  });

  DStatus _status = DStatus.idle;
  String? _error;
  int _downloaded = 0;
  double _speed = 0;
  int _lastTick = 0;
  int _lastTickBytes = 0;
  bool _cancelled = false;

  Future<void> start() async {
    try {
      await dir.create(recursive: true);
      _emit(DStatus.running);
      final media = await _resolveToMedia(url);
      final segs = _parseSegments(media.text, media.base);
      if (segs.isEmpty) throw Exception('no segments found in playlist');
      final partsDir = Directory('${dir.path}${Platform.pathSeparator}$fileName.parts');
      await partsDir.create(recursive: true);
      await _fetchAll(segs, partsDir);
      if (_cancelled) { _emit(DStatus.cancelled); return; }
      _emit(DStatus.merging);
      await _concat(segs, partsDir);
      _emit(DStatus.completed);
    } catch (e) {
      _error = e.toString();
      _emit(DStatus.error);
    }
  }

  void cancel() => _cancelled = true;

  // --- playlist fetching ------------------------------------------------------
  Future<_Playlist> _resolveToMedia(String u) async {
    for (var depth = 0; depth < 3; depth++) {
      final p = await _fetchPlaylist(u);
      if (_isMaster(p.text)) {
        final variant = _bestVariant(p.text, p.base);
        if (variant == null) throw Exception('no playable variant');
        u = variant;
        continue;
      }
      return p;
    }
    throw Exception('playlist too deep');
  }

  Future<_Playlist> _fetchPlaylist(String u) async {
    final c = HttpClient();
    try {
      final req = await c.openUrl('GET', Uri.parse(u));
      headers.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return _Playlist(body, u);
    } finally {
      c.close(force: true);
    }
  }

  bool _isMaster(String text) => text.contains('#EXT-X-STREAM-INF');

  /// Picks the highest-bandwidth variant (best quality).
  String? _bestVariant(String text, String baseUrl) {
    String? best;
    var bestBw = -1;
    final lines = text.split('\n');
    var curBw = -1;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        final m = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        curBw = m != null ? int.parse(m.group(1)!) : -1;
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        if (curBw > bestBw) {
          bestBw = curBw;
          best = _resolve(baseUrl, line);
        }
        curBw = -1;
      }
    }
    return best;
  }

  List<String> _parseSegments(String text, String baseUrl) {
    final out = <String>[];
    final lines = text.split('\n');
    var inSegments = true;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('#EXT-X-MAP:')) {
        // fMP4 stream — can't concat without muxing; bail out.
        throw Exception('fMP4 (EXT-X-MAP) streams need muxing — pick a TS variant');
      }
      if (line.startsWith('#EXT-X-KEY') || line.startsWith('#EXT-X-ENDLIST')) {
        inSegments = line.startsWith('#EXT-X-KEY') ? inSegments : inSegments;
        continue;
      }
      if (line.startsWith('#')) continue;
      if (line.isEmpty) continue;
      if (inSegments) out.add(_resolve(baseUrl, line));
    }
    return out;
  }

  String _resolve(String base, String ref) {
    if (ref.startsWith('http')) return ref;
    final baseUri = Uri.parse(base);
    return baseUri.resolve(ref).toString();
  }

  // --- parallel fetch ----------------------------------------------------------
  Future<void> _fetchAll(List<String> segs, Directory partsDir) async {
    _lastTick = DateTime.now().millisecondsSinceEpoch;
    var idx = 0;
    Future<void> worker() async {
      final c = HttpClient();
      try {
        while (!_cancelled) {
          final i = idx++;
          if (i >= segs.length) return;
          await _fetchSegment(c, segs[i], i, partsDir);
        }
      } finally {
        c.close(force: true);
      }
    }

    final jobs = <Future<void>>[];
    for (var w = 0; w < workers.clamp(1, segs.length); w++) {
      jobs.add(worker());
    }
    await Future.wait(jobs);
  }

  Future<void> _fetchSegment(HttpClient c, String segUrl, int i, Directory partsDir) async {
    for (var attempt = 0; attempt < 3 && !_cancelled; attempt++) {
      try {
        final req = await c.openUrl('GET', Uri.parse(segUrl));
        headers.forEach((k, v) => req.headers.set(k, v));
        final res = await req.close();
        if (res.statusCode != 200 && res.statusCode != 206) continue;
        final out = File('${partsDir.path}${Platform.pathSeparator}seg_$i.ts');
        final sink = out.openWrite();
        await for (final data in res) {
          if (_cancelled) break;
          sink.add(data);
          _tick(data.length);
        }
        await sink.flush();
        await sink.close();
        return;
      } catch (_) {}
    }
    throw Exception('segment $i failed');
  }

  Future<void> _concat(List<String> segs, Directory partsDir) async {
    final out = File('${dir.path}${Platform.pathSeparator}$fileName').openSync(mode: FileMode.write);
    try {
      for (var i = 0; i < segs.length; i++) {
        final f = File('${partsDir.path}${Platform.pathSeparator}seg_$i.ts');
        if (!f.existsSync()) throw Exception('missing segment $i');
        await for (final data in f.openRead()) {
          out.writeFromSync(data, 0, data.length);
        }
      }
      out.flushSync();
    } finally {
      out.closeSync();
    }
    try { partsDir.deleteSync(recursive: true); } catch (_) {}
  }

  void _tick(int n) {
    _downloaded += n;
    _lastTickBytes += n;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTick >= 1000) {
      final dt = (now - _lastTick) / 1000.0;
      _speed = dt > 0 ? _lastTickBytes / dt : 0;
      _lastTick = now;
      _lastTickBytes = 0;
      _emit(_status);
    }
  }

  void _emit(DStatus s) {
    _status = s;
    onProgress?.call(DProgress(
      status: s,
      totalBytes: _downloaded,
      downloadedBytes: _downloaded,
      bytesPerSec: _speed,
      error: _error,
    ));
  }
}

class _Playlist {
  final String text;
  final String base;
  _Playlist(this.text, this.base);
}
