/// What a resolved download link points to.
enum DownloadKind {
  /// Direct file URL — feed straight to the segmented downloader.
  direct,

  /// HLS stream — needs the HLS capture path (multi-segment fetch).
  hls,

  /// A webpage that must be scraped a second time to find the real link.
  page,
}

class ScrapeResult {
  final String source; // e.g. "YouTube"
  final String label; // e.g. "720p"
  final String url;
  final DownloadKind kind;
  final Map<String, String> headers;
  final String? fileName;

  const ScrapeResult({
    required this.source,
    required this.label,
    required this.url,
    this.kind = DownloadKind.direct,
    this.headers = const {},
    this.fileName,
  });
}

/// A source that can find downloadable copies of a title.
abstract class SourceScraper {
  String get name;

  /// True when this source primarily serves Hindi-dubbed content.
  bool get isHindiDubbed => false;

  Future<List<ScrapeResult>> resolveMovie(String title, int? year);

  Future<List<ScrapeResult>> resolveEpisode(String title, int season, int episode) async => const [];
}
