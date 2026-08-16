import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mdownloader/plugins/plugin_bootstrap.dart';

void main() {
  test('plugin engine: load plugin -> invoke loadStreams -> http bridge -> result', () async {
    late Directory tmp;
    MdnEngine? engine;
    try {
      tmp = Directory.systemTemp.createTempSync('mdn_engine_');
      engine = MdnEngine(storageDir: Directory('${tmp.path}/data'));
      engine.init();
    } catch (e) {
      markTestSkipped('QuickJS native library unavailable on this host: $e');
      return;
    }

    // A fake "site" the plugin will scrape.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/search') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'results': [{'url': 'http://127.0.0.1:${server.port}/file.mp4', 'label': '1080p'}]}));
      } else if (req.uri.path == '/file.mp4') {
        req.response.headers.set('content-length', '8');
        req.response.add([0, 1, 2, 3, 4, 5, 6, 7]);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });

    const source = r'''
function loadStreams(url, cb) {
  var m = JSON.parse(String(url || '{}'));
  var host = manifest.baseUrl;
  http_get(host + '/search?q=' + encodeURIComponent(m.title)).then(function (html) {
    var j = JSON.parse(html);
    var out = (j.results || []).map(function (r) {
      return { url: r.url, label: r.label, kind: 'direct' };
    });
    cb({ success: true, data: out });
  }).catch(function (e) {
    cb({ success: false, message: String(e) });
  });
}
''';

    engine.loadPlugin('com.test.site', {
      'packageName': 'com.test.site',
      'name': 'Test Site',
      'version': 1,
      'baseUrl': 'http://127.0.0.1:${server.port}',
      'description': '',
      'icon': '',
    }, source);

    final result = await engine.invoke(
      'com.test.site',
      'loadStreams',
      [jsonEncode({'tmdbId': 1, 'title': 'Test Movie', 'year': 2024, 'mediaType': 'movie'})],
    );

    expect(result, isA<Map>());
    expect((result as Map)['success'], true);
    final data = result['data'] as List;
    expect(data.length, 1);
    expect((data[0] as Map)['url'], 'http://127.0.0.1:${server.port}/file.mp4');
    expect((data[0] as Map)['label'], '1080p');

    server.close(force: true);
    engine.dispose();
    tmp.deleteSync(recursive: true);
  });
}
