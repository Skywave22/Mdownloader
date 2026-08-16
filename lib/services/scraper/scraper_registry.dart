import '../../models/media.dart';
import 'scraper.dart';
import 'youtube_scraper.dart';

/// Central registry of all source scrapers. Runs them in parallel and merges
/// the results so the user sees every available copy at once.
class ScraperRegistry {
  final List<SourceScraper> _scrapers = [
    YoutubeScraper(),
    // Additional scrapers (Hindi DDL sites, vidsrc family, ...) get added here.
  ];

  List<SourceScraper> get scrapers => List.unmodifiable(_scrapers);

  Future<List<ScrapeResult>> resolveMovie(MediaItem item) async {
    final results = await Future.wait(_scrapers.map((s) => s
        .resolveMovie(item.title, item.year)
        .catchError((Object _) => const <ScrapeResult>[])));
    return _flatten(results);
  }

  Future<List<ScrapeResult>> resolveEpisode(MediaItem item, int season, int episode) async {
    final results = await Future.wait(_scrapers.map((s) => s
        .resolveEpisode(item.title, season, episode)
        .catchError((Object _) => const <ScrapeResult>[])));
    return _flatten(results);
  }

  List<ScrapeResult> _flatten(List<List<ScrapeResult>> all) {
    final out = <ScrapeResult>[];
    for (final list in all) {
      out.addAll(list);
    }
    return out;
  }
}
