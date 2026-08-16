import '../downloader/download_manager.dart';
import 'scraper/scraper_registry.dart';
import 'tmdb_service.dart';

/// App-wide singletons (kept simple on purpose).
final tmdb = TmdbService();
final scraperRegistry = ScraperRegistry();
final downloadManager = DownloadManager();
