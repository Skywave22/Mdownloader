import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdownloader/downloader/hls_downloader.dart';
import 'package:mdownloader/downloader/segmented_downloader.dart';

void main() {
  test('HLS downloader captures + concatenates all segments byte-exactly', () async {
    // Build a synthetic HLS: master -> variant -> media playlist with 12 TS segments.
    const segCount = 12;
    final segments = <List<int>>[];
    for (var i = 0; i < segCount; i++) {
      segments.add(List<int>.generate(64 * 1024 + i * 7, (j) => (i * 131 + j) & 0xff));
    }
    final expected = segments.expand((s) => s).toList();

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    server.listen((req) async {
      try {
        final path = req.uri.path;
        if (path == '/master.m3u8') {
          req.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
          req.response.write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1920x1080\n'
              '/variant.m3u8\n');
        } else if (path == '/variant.m3u8') {
          req.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
          final sb = StringBuffer('#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:6\n#EXT-X-PLAYLIST-TYPE:VOD\n');
          for (var i = 0; i < segCount; i++) {
            sb.writeln('#EXTINF:6.0,');
            sb.writeln('/seg_$i.ts');
          }
          sb.writeln('#EXT-X-ENDLIST');
          req.response.write(sb.toString());
        } else if (path.startsWith('/seg_')) {
          final i = int.parse(path.replaceAll(RegExp(r'[^0-9]'), ''));
          req.response.add(segments[i]);
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      } catch (_) {
        try { req.response.close(); } catch (_) {}
      }
    });

    final tmp = Directory.systemTemp.createTempSync('mdn_hls_');
    final statuses = <DStatus>[];
    final dl = HlsDownloader(
      url: 'http://127.0.0.1:$port/master.m3u8',
      dir: Directory('${tmp.path}/out'),
      fileName: 'movie.ts',
      workers: 6,
      onProgress: (p) {
        if (statuses.isEmpty || statuses.last != p.status) statuses.add(p.status);
      },
    );
    await dl.start();

    final out = File('${tmp.path}/out/movie.ts');
    expect(out.existsSync(), isTrue);
    final got = out.readAsBytesSync();
    expect(got.length, expected.length);
    expect(_equal(got, expected), isTrue, reason: 'concatenated TS must be byte-exact');
    expect(statuses.last, DStatus.completed);

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
