import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config.dart';
import '../models/media.dart';

/// Thin TMDB v3 client: search, trending, popular, details, seasons/episodes.
class TmdbService {
  final http.Client _client = http.Client();

  Uri _uri(String path, [Map<String, String>? q]) {
    final query = <String, String>{
      'api_key': AppConfig.tmdbApiKey,
      'language': 'en-US',
      'include_adult': 'false',
      if (q != null) ...q,
    };
    return Uri.parse('${AppConfig.tmdbBase}$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _getJson(String path, [Map<String, String>? q]) async {
    final res = await _client.get(_uri(path, q));
    if (res.statusCode != 200) {
      throw Exception('TMDB ${res.statusCode}: ${res.body.substring(0, res.body.length.clamp(0, 120))}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<MediaItem>> searchMulti(String query) async {
    final j = await _getJson('/search/multi', {'query': query, 'page': '1'});
    final out = <MediaItem>[];
    for (final r in (j['results'] as List? ?? const [])) {
      if (r is! Map) continue;
      final mt = r['media_type'];
      if (mt != 'movie' && mt != 'tv') continue;
      out.add(MediaItem.fromTmdb(r as Map<String, dynamic>));
    }
    return out;
  }

  Future<List<MediaItem>> trending() async {
    final j = await _getJson('/trending/all/week');
    return (j['results'] as List? ?? const [])
        .whereType<Map>()
        .where((r) => r['media_type'] == 'movie' || r['media_type'] == 'tv')
        .map((r) => MediaItem.fromTmdb(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<MediaItem>> popularMovies() async {
    final j = await _getJson('/movie/popular');
    return (j['results'] as List? ?? const [])
        .whereType<Map>()
        .map((r) => MediaItem.fromTmdb(r as Map<String, dynamic>, forceType: 'movie'))
        .toList();
  }

  Future<List<MediaItem>> popularTv() async {
    final j = await _getJson('/tv/popular');
    return (j['results'] as List? ?? const [])
        .whereType<Map>()
        .map((r) => MediaItem.fromTmdb(r as Map<String, dynamic>, forceType: 'tv'))
        .toList();
  }

  Future<MediaItem> details(MediaItem item) async {
    if (item.mediaType == 'movie') {
      final j = await _getJson('/movie/${item.id}');
      return MediaItem.fromTmdb(j, forceType: 'movie');
    }
    final j = await _getJson('/tv/${item.id}');
    final base = MediaItem.fromTmdb(j, forceType: 'tv');
    // load episodes per season (bounded concurrency)
    final seasons = <MediaSeason>[];
    for (final s in base.seasons) {
      try {
        final sj = await _getJson('/tv/${item.id}/season/${s.number}');
        final eps = (sj['episodes'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => MediaEpisode.fromTmdb(s.number, e as Map<String, dynamic>))
            .toList();
        seasons.add(MediaSeason(
          number: s.number,
          name: s.name,
          episodeCount: s.episodeCount,
          posterPath: s.posterPath,
          episodes: eps,
        ));
      } catch (_) {
        seasons.add(s);
      }
    }
    return MediaItem(
      id: base.id,
      mediaType: 'tv',
      title: base.title,
      overview: base.overview,
      posterPath: base.posterPath,
      backdropPath: base.backdropPath,
      releaseDate: base.releaseDate,
      voteAverage: base.voteAverage,
      seasons: seasons,
    );
  }

  void dispose() => _client.close();
}
