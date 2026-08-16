class AppConfig {
  static const appName = 'MDownloader';
  static const appVersion = '0.3.0';
  static const repoUrl = 'https://github.com/Skywave22/Mdownloader';

  // TMDB API (free catalog key). Replace with your own at tmdb.org if you
  // want to be independent of this shared key.
  static const tmdbApiKey = 'aa8db17cefbe569dc21a8809090b7b93';
  static const tmdbBase = 'https://api.themoviedb.org/3';
  static const tmdbImage = 'https://image.tmdb.org/t/p/';

  // Segmented downloader defaults.
  static const maxWorkers = 8;
  static const autoChunkSize = 0; // engine picks (1–16 MB)
}
