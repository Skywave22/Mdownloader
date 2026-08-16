/// A catalog item backed by TMDB (movie or series).
class MediaItem {
  final int id;
  final String mediaType; // 'movie' | 'tv'
  final String title;
  final String overview;
  final String posterPath;
  final String backdropPath;
  final String releaseDate; // yyyy-mm-dd
  final double voteAverage;
  final int? runtime; // movie only
  final List<MediaSeason> seasons;

  const MediaItem({
    required this.id,
    required this.mediaType,
    required this.title,
    this.overview = '',
    this.posterPath = '',
    this.backdropPath = '',
    this.releaseDate = '',
    this.voteAverage = 0,
    this.runtime,
    this.seasons = const [],
  });

  int? get year {
    if (releaseDate.length >= 4) return int.tryParse(releaseDate.substring(0, 4));
    return null;
  }

  String posterUrl([String size = 'w500']) =>
      posterPath.isNotEmpty ? '${'https://image.tmdb.org/t/p/'}$size$posterPath' : '';

  String backdropUrl([String size = 'w1280']) =>
      backdropPath.isNotEmpty ? '${'https://image.tmdb.org/t/p/'}$size$backdropPath' : '';

  factory MediaItem.fromTmdb(Map<String, dynamic> j, {String? forceType}) {
    final mediaType = forceType ??
        (j['media_type'] as String?) ??
        (j['title'] != null ? 'movie' : 'tv');
    final seasonsRaw = (j['seasons'] as List?) ?? const [];
    final seasons = mediaType == 'tv'
        ? seasonsRaw
              .where((s) => s is Map && (s['season_number'] as num?) != null && (s['season_number'] as num) > 0)
              .map((s) => MediaSeason.fromTmdb(s as Map<String, dynamic>))
              .toList()
        : const <MediaSeason>[];
    return MediaItem(
      id: (j['id'] as num).toInt(),
      mediaType: mediaType,
      title: (j['title'] ?? j['name'] ?? 'Unknown') as String,
      overview: (j['overview'] ?? '') as String,
      posterPath: (j['poster_path'] ?? '') as String,
      backdropPath: (j['backdrop_path'] ?? '') as String,
      releaseDate: (j['release_date'] ?? j['first_air_date'] ?? '') as String,
      voteAverage: ((j['vote_average'] ?? 0) as num).toDouble(),
      runtime: (j['runtime'] as num?)?.toInt(),
      seasons: seasons,
    );
  }
}

class MediaSeason {
  final int number;
  final String name;
  final int episodeCount;
  final String posterPath;
  final List<MediaEpisode> episodes;

  const MediaSeason({
    required this.number,
    required this.name,
    this.episodeCount = 0,
    this.posterPath = '',
    this.episodes = const [],
  });

  factory MediaSeason.fromTmdb(Map<String, dynamic> j) => MediaSeason(
        number: (j['season_number'] as num).toInt(),
        name: (j['name'] ?? 'Season') as String,
        episodeCount: (j['episode_count'] as num?)?.toInt() ?? 0,
        posterPath: (j['poster_path'] ?? '') as String,
      );
}

class MediaEpisode {
  final int seasonNumber;
  final int episodeNumber;
  final String name;
  final String stillPath;

  const MediaEpisode({
    required this.seasonNumber,
    required this.episodeNumber,
    required this.name,
    this.stillPath = '',
  });

  factory MediaEpisode.fromTmdb(int season, Map<String, dynamic> j) => MediaEpisode(
        seasonNumber: season,
        episodeNumber: (j['episode_number'] as num).toInt(),
        name: (j['name'] ?? 'Episode ${j['episode_number']}') as String,
        stillPath: (j['still_path'] ?? '') as String,
      );
}
