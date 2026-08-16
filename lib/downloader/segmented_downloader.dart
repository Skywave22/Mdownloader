// =============================================================================
//  segmented_downloader.dart — REAL parallel segmented download engine
//
//  - Splits a file into fixed-size chunks (a queue) and downloads them with N
//    concurrent HTTP range requests (works against any server that honors
//    Range: bytes=... / Accept-Ranges). This is the same technique IDM/aria2
//    use: when a server throttles each connection, N connections multiply
//    throughput up to your actual line speed. It can never exceed your ISP
//    bandwidth — that is a physical limit, not a software one.
//  - Each chunk is written to its own .part file, so pausing, resuming and
//    retrying are per-chunk and corruption-proof.
//  - On completion the parts are merged into the final file in order.
//  - Pure dart:io, no Flutter dependency -> unit-testable in plain Dart.
// =============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

enum DStatus { idle, running, paused, merging, completed, error, cancelled }

class DProgress {
  final DStatus status;
  final int totalBytes;
  final int downloadedBytes;
  final double bytesPerSec;
  final String? error;
  const DProgress({
    required this.status,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.bytesPerSec,
    this.error,
  });
}

class _Chunk {
  final int index;
  final int start; // inclusive
  final int end; // inclusive
  bool done = false;
  _Chunk(this.index, this.start, this.end);
  int get length => end - start + 1;
}

class SegmentedDownloader {
  final String url;
  final Directory dir; // work dir (parts + state live here)
  final String fileName; // final output name inside dir
  final Map<String, String> headers;
  final int maxWorkers;
  final int chunkSize; // 0 = auto
  final void Function(DProgress)? onProgress;

  SegmentedDownloader({
    required this.url,
    required this.dir,
    required this.fileName,
    this.headers = const {},
    this.maxWorkers = 8,
    this.chunkSize = 0,
    this.onProgress,
  });

  late final File _finalFile;
  late final File _stateFile;
  late final Directory _partsDir;

  int _total = -1;
  bool _supportsRanges = false;
  List<_Chunk> _chunks = [];
  bool _paused = false;
  bool _cancelled = false;
  String? _error;
  int _downloaded = 0;
  double _speed = 0;
  int _lastTick = 0;
  int _lastTickBytes = 0;
  DStatus _status = DStatus.idle;

  File partFile(int i) => File('${_partsDir.path}${Platform.pathSeparator}part_$i.bin');

  String get statePath => '${dir.path}${Platform.pathSeparator}$fileName.mdn';

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------
  Future<void> start() async {
    if (_status == DStatus.running) return;
    _paused = false;
    _cancelled = false;
    _error = null;
    _finalFile = File('${dir.path}${Platform.pathSeparator}$fileName');
    _stateFile = File(statePath);
    _partsDir = Directory('${dir.path}${Platform.pathSeparator}$fileName.parts');
    try {
      await dir.create(recursive: true);
      await _partsDir.create(recursive: true);

      final restored = _loadState();
      if (!restored) {
        await _probe();
        if (_total <= 0) {
          // Unknown length -> fall back to plain single-connection download.
          _supportsRanges = false;
          _total = 0;
          _chunks = [_Chunk(0, 0, -1)]; // "unknown" chunk
        } else {
          _supportsRanges = _supportsRanges && _total > 0;
          _buildChunks();
        }
        _downloaded = 0;
        _saveState();
      }

      if (_total > 0 && _downloaded >= _total) {
        _emit(DStatus.merging);
        await _merge();
        _emit(DStatus.completed);
        return;
      }

      _emit(DStatus.running);
      _lastTick = DateTime.now().millisecondsSinceEpoch;
      _lastTickBytes = 0;

      if (!_supportsRanges || _total <= 0) {
        await _downloadSequential();
      } else {
        await _runWorkers();
      }

      if (_cancelled) { _emit(DStatus.cancelled); return; }
      if (_error != null) { _emit(DStatus.error); return; }
      if (_paused) { _emit(DStatus.paused); return; }

      _emit(DStatus.merging);
      await _merge();
      _emit(DStatus.completed);
    } catch (e) {
      _error = e.toString();
      _emit(DStatus.error);
    }
  }

  void pause() => _paused = true;
  void cancel() { _cancelled = true; _paused = true; }

  bool get isDone => _status == DStatus.completed;

  // ---------------------------------------------------------------------------
  // Probing
  // ---------------------------------------------------------------------------
  Future<void> _probe() async {
    final c = HttpClient();
    try {
      // HEAD first.
      var req = await c.openUrl('HEAD', Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.set('User-Agent', 'Mozilla/5.0');
      var res = await req.close();
      final cl = int.tryParse(res.headers.value('content-length') ?? '') ?? -1;
      final ar = (res.headers.value('accept-ranges') ?? '').toLowerCase().contains('bytes');
      if (cl > 0) { _total = cl; _supportsRanges = ar; return; }
    } catch (_) {}
    // GET bytes=0-0 fallback.
    final c2 = HttpClient();
    try {
      final req = await c2.openUrl('GET', Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.set('Range', 'bytes=0-0');
      final res = await req.close();
      if (res.statusCode == 206) {
        final cr = res.headers.value('content-range') ?? ''; // "bytes 0-0/12345"
        final slash = cr.lastIndexOf('/');
        if (slash > 0) _total = int.tryParse(cr.substring(slash + 1)) ?? -1;
        _supportsRanges = true;
      } else if (res.statusCode == 200) {
        _total = int.tryParse(res.headers.value('content-length') ?? '') ?? -1;
        _supportsRanges = false;
      }
    } finally {
      c2.close(force: true);
    }
  }

  void _buildChunks() {
    final cs = chunkSize > 0
        ? chunkSize
        : math.max(1 << 20, (_total / (maxWorkers * 4)).ceil()).clamp(1 << 20, 16 << 20);
    _chunks = [];
    var i = 0;
    var s = 0;
    while (s < _total) {
      final e = math.min(s + cs - 1, _total - 1);
      _chunks.add(_Chunk(i++, s, e));
      s = e + 1;
    }
  }

  // ---------------------------------------------------------------------------
  // State (resume)
  // ---------------------------------------------------------------------------
  bool _loadState() {
    if (!_stateFile.existsSync()) return false;
    try {
      final j = jsonDecode(_stateFile.readAsStringSync()) as Map<String, dynamic>;
      if (j['url'] != url) return false;
      _total = (j['total'] as num).toInt();
      _supportsRanges = (j['ranges'] as bool?) ?? false;
      _chunks = [];
      _downloaded = 0;
      for (final c in (j['chunks'] as List)) {
        final ch = _Chunk(c['i'] as int, c['s'] as int, c['e'] as int);
        final part = partFile(ch.index);
        if (c['done'] == true && part.existsSync() && part.lengthSync() == ch.length) {
          ch.done = true;
          _downloaded += ch.length;
        }
        _chunks.add(ch);
      }
      return _chunks.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _saveState() {
    try {
      _stateFile.writeAsStringSync(jsonEncode({
        'url': url,
        'total': _total,
        'ranges': _supportsRanges,
        'chunks': _chunks.map((c) => {'i': c.index, 's': c.start, 'e': c.end, 'done': c.done}).toList(),
      }));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Workers (parallel segmented)
  // ---------------------------------------------------------------------------
  int _nextIndex = 0;

  _Chunk? _nextChunk() {
    while (_nextIndex < _chunks.length) {
      final c = _chunks[_nextIndex++];
      if (!c.done) return c;
    }
    return null;
  }

  Future<void> _runWorkers() async {
    final workers = <Future<void>>[];
    for (var i = 0; i < math.min(maxWorkers, _chunks.length); i++) {
      workers.add(_worker());
    }
    await Future.wait(workers);
  }

  Future<void> _worker() async {
    while (!_paused && !_cancelled && _error == null) {
      final chunk = _nextChunk();
      if (chunk == null) return;
      final ok = await _downloadChunkWithRetry(chunk);
      if (!ok) {
        if (_paused || _cancelled) return;
        _error = 'chunk ${chunk.index} failed';
        return;
      }
    }
  }

  Future<bool> _downloadChunkWithRetry(_Chunk chunk) async {
    for (var attempt = 0; attempt < 3 && !_paused && !_cancelled; attempt++) {
      if (await _downloadChunk(chunk)) return true;
    }
    return false;
  }

  Future<bool> _downloadChunk(_Chunk chunk) async {
    final part = partFile(chunk.index);
    final raf = part.openSync(mode: FileMode.write);
    final client = HttpClient();
    try {
      final req = await client.openUrl('GET', Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.set('Range', 'bytes=${chunk.start}-${chunk.end}');
      final res = await req.close();
      if (res.statusCode != 206 && res.statusCode != 200) {
        return false;
      }
      var written = 0;
      await for (final data in res) {
        if (_paused || _cancelled) { raf.closeSync(); return false; }
        raf.writeFromSync(data, 0, data.length);
        written += data.length;
        _tick(data.length);
      }
      raf.closeSync();
      if (written == chunk.length) {
        chunk.done = true;
        _saveState();
        return true;
      }
      return false;
    } catch (_) {
      try { raf.closeSync(); } catch (_) {}
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _downloadSequential() async {
    final part = partFile(0);
    final raf = part.openSync(mode: FileMode.write);
    final client = HttpClient();
    try {
      final req = await client.openUrl('GET', Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close();
      var written = 0;
      await for (final data in res) {
        if (_paused || _cancelled) { raf.closeSync(); return; }
        raf.writeFromSync(data, 0, data.length);
        written += data.length;
        _tick(data.length);
      }
      raf.closeSync();
      _total = written;
      if (_chunks.isEmpty) _chunks.add(_Chunk(0, 0, written - 1));
      _chunks[0].done = true;
      _saveState();
    } finally {
      client.close(force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Merge + progress + cleanup
  // ---------------------------------------------------------------------------
  Future<void> _merge() async {
    final out = _finalFile.openSync(mode: FileMode.write);
    try {
      for (final c in _chunks) {
        final p = partFile(c.index);
        if (!p.existsSync()) continue;
        await for (final data in p.openRead()) {
          out.writeFromSync(data, 0, data.length);
        }
      }
      out.flushSync();
    } finally {
      out.closeSync();
    }
    _cleanup();
  }

  void _cleanup() {
    try { if (_partsDir.existsSync()) _partsDir.deleteSync(recursive: true); } catch (_) {}
    try { if (_stateFile.existsSync()) _stateFile.deleteSync(); } catch (_) {}
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
      totalBytes: _total > 0 ? _total : _downloaded,
      downloadedBytes: _downloaded,
      bytesPerSec: _speed,
      error: _error,
    ));
  }
}
