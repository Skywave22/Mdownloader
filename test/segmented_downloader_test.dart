import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdownloader/downloader/segmented_downloader.dart';

void main() {
  test('segmented download is byte-exact and faster than single connection', () async {
    const size = 2 * 1024 * 1024; // 2 MB
    const ratePerConn = 220 * 1024; // 220 KB/s per connection
    final data = List<int>.generate(size, (i) => (i * 37 + 11) & 0xff);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      try {
        final range = req.headers.value('range');
        var start = 0;
        var end = size - 1;
        var partial = false;
        if (range != null && range.startsWith('bytes=')) {
          final spec = range.substring(6).split('-');
          start = int.parse(spec[0]);
          if (spec[1].isNotEmpty) end = min(int.parse(spec[1]), size - 1);
          partial = true;
        }
        final body = data.sublist(start, end + 1);
        if (partial) {
          req.response.statusCode = 206;
          req.response.headers.set('content-range', 'bytes $start-$end/$size');
          req.response.headers.set('accept-ranges', 'bytes');
        } else {
          req.response.headers.set('accept-ranges', 'bytes');
        }
        req.response.headers.set('content-length', '${body.length}');
        const chunk = 8 * 1024;
        final sw = Stopwatch()..start();
        var sent = 0;
        for (var off = 0; off < body.length; off += chunk) {
          final endOff = min(off + chunk, body.length);
          req.response.add(body.sublist(off, endOff));
          sent += endOff - off;
          final waitMs = sent * 1000 / ratePerConn - sw.elapsedMilliseconds;
          if (waitMs > 0) await Future.delayed(Duration(milliseconds: waitMs.round()));
        }
        await req.response.close();
      } catch (_) {
        try { req.response.close(); } catch (_) {}
      }
    });

    final tmp = Directory.systemTemp.createTempSync('mdn_ut_');
    final url = 'http://127.0.0.1:${server.port}/f.bin';

    Future<double> run(int workers, String name) async {
      final dir = Directory('${tmp.path}/$name')..createSync();
      final sw = Stopwatch()..start();
      final dl = SegmentedDownloader(
        url: url, dir: dir, fileName: 'out.bin', maxWorkers: workers, chunkSize: 512 * 1024,
      );
      await dl.start();
      sw.stop();
      final bytes = File('${dir.path}/out.bin').readAsBytesSync();
      expect(_equal(bytes, data), isTrue, reason: '$name must be byte-exact');
      return sw.elapsedMilliseconds / 1000.0;
    }

    final tSingle = await run(1, 'single');
    final tMulti = await run(6, 'multi');
    // ignore: avoid_print
    print('single: ${tSingle.toStringAsFixed(2)}s, segmented: ${tMulti.toStringAsFixed(2)}s, speedup ${(tSingle / tMulti).toStringAsFixed(2)}x');
    expect(tMulti < tSingle, isTrue, reason: 'segmented should beat a single throttled connection');

    server.close(force: true);
    tmp.deleteSync(recursive: true);
  });
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
