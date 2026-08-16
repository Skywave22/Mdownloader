/// What a resolved download link points to.
enum DownloadKind {
  /// Direct file URL — fed to the segmented downloader.
  direct,

  /// HLS stream — captured with the HLS downloader.
  hls,
}
