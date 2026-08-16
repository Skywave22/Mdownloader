import 'dart:convert';
import 'package:http/http.dart' as http;
import 'scraper.dart';

/// YouTube scraper (InnerTube JSON API, no browser needed).
///
/// Searches YouTube for "<title> Hindi dubbed full movie" / "<title> episode",
/// then fetches the player response with the ANDROID client (which returns
/// progressive MP4 download URLs — itag 18 = 360p, itag 22 = 720p — even from
/// datacenter IPs where the WEB client is PO-token gated). Also returns the
/// merged HLS manifest when the WEB client yields one. No ffmpeg, no yt-dlp.
class YoutubeScraper extends SourceScraper {
  static const _key = 'AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w';
  static const _base = 'https://www.youtube.com/youtubei/v1/';

  static const _webCtx = {
    'context': {
      'client': {
        'clientName': 'WEB',
        'clientVersion': '2.20260811.07.00',
        'hl': 'en',
        'gl': 'US',
      },
    },
  };

  static const _androidUa =
      'com.google.android.youtube/21.02.35 (Linux; U; Android 11) gzip';
  static const _androidCtx = {
    'context': {
      'client': {
        'clientName': 'ANDROID',
        'clientVersion': '21.02.35',
        'androidSdkVersion': 30,
        'userAgent': _androidUa,
        'osName': 'Android',
        'osVersion': '11',
        'hl': 'en',
        'gl': 'US',
      },
    },
  };

  final http.Client _client = http.Client();

  @override
  String get name => 'YouTube';

  @override
  Future<List<ScrapeResult>> resolveMovie(String title, int? year) async {
    final query = '$title${year != null ? ' $year' : ''} full movie hindi dubbed';
    return _resolve(query);
  }

  @override
  Future<List<ScrapeResult>> resolveEpisode(String title, int season, int episode) async {
    final query = '$title season $season episode $episode hindi dubbed';
    return _resolve(query);
  }

  Future<List<ScrapeResult>> _resolve(String query) async {
    final ids = await _searchIds(query);
    final out = <ScrapeResult>[];
    for (final id in ids.take(3)) {
      try {
        out.addAll(await _streamsFor(id));
      } catch (_) {}
      if (out.length >= 4) break;
    }
    return _dedupe(out);
  }

  Future<List<String>> _searchIds(String query) async {
    final body = jsonEncode({..._webCtx, 'query': query});
    final res = await _client.post(
      Uri.parse('${_base}search?key=$_key&prettyPrint=false'),
      headers: {'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'},
      body: body,
    );
    if (res.statusCode != 200) return const [];
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final ids = <String>[];
    _walk(j, (obj) {
      final v = obj['videoRenderer'];
      if (v is Map && v['videoId'] is String && !ids.contains(v['videoId'])) {
        ids.add(v['videoId'] as String);
      }
    });
    return ids;
  }

  Future<List<ScrapeResult>> _streamsFor(String videoId) async {
    final out = <ScrapeResult>[];

    // ANDROID client — progressive MP4 (itag 18/22), the reliable download path.
    final android = await _player(_androidCtx, videoId, ua: _androidUa);
    if (_isPlayable(android)) {
      final sd = android['streamingData'] as Map<String, dynamic>?;
      final formats = (sd?['formats'] as List? ?? const []).whereType<Map>();
      for (final f in formats) {
        final url = f['url'];
        if (url is! String) continue;
        final mime = (f['mimeType'] ?? '') as String;
        if (!mime.contains('video/mp4')) continue; // progressive only
        final itag = (f['itag'] as num?)?.toInt();
        String label;
        if (itag == 22) {
          label = '720p (MP4)';
        } else if (itag == 18) {
          label = '360p (MP4)';
        } else {
          label = '${f['height'] ?? itag}p (MP4)';
        }
        out.add(ScrapeResult(source: name, label: label, url: url, kind: DownloadKind.direct));
      }
    }

    // WEB client — merged HLS manifest when available (often gated on DC IPs).
    final web = await _player(_webCtx, videoId, ua: 'Mozilla/5.0');
    if (_isPlayable(web)) {
      final sd = web['streamingData'] as Map<String, dynamic>?;
      final hls = sd?['hlsManifestUrl'];
      if (hls is String && hls.isNotEmpty) {
        out.add(ScrapeResult(
          source: name,
          label: '1080p (HLS)',
          url: hls,
          kind: DownloadKind.hls,
          headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://www.youtube.com/'},
        ));
      }
    }
    return out;
  }

  bool _isPlayable(Map<String, dynamic> r) {
    final ps = r['playabilityStatus'];
    if (ps is! Map) return false;
    final status = ps['status'];
    return status == 'OK' || status == 'CONTENT_CHECK_REQUIRED';
  }

  Future<Map<String, dynamic>> _player(Map<String, dynamic> ctx, String videoId, {String? ua}) async {
    final body = jsonEncode({...ctx, 'videoId': videoId});
    final res = await _client.post(
      Uri.parse('${_base}player?key=$_key&prettyPrint=false'),
      headers: {'Content-Type': 'application/json', if (ua != null) 'User-Agent': ua},
      body: body,
    );
    if (res.statusCode != 200) return const {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void _walk(Object? obj, void Function(Map<String, dynamic>) onMap) {
    if (obj is Map) {
      onMap(obj.cast<String, dynamic>());
      for (final v in obj.values) {
        _walk(v, onMap);
      }
    } else if (obj is List) {
      for (final v in obj) {
        _walk(v, onMap);
      }
    }
  }

  List<ScrapeResult> _dedupe(List<ScrapeResult> inList) {
    final seen = <String>{};
    final out = <ScrapeResult>[];
    for (final r in inList) {
      if (seen.add(r.url)) out.add(r);
    }
    return out;
  }
}
