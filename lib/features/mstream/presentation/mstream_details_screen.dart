import 'dart:async';

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart'
    hide Video;
import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart'
    as bridge show Video;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/logger/app_logger.dart';
import '../../../core/network/http_defaults.dart';
import '../../../core/services/download_service.dart';
import '../../../core/storage/episode_watch_repository.dart';
import '../../../core/storage/history_repository.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../shared/widgets/custom_widgets.dart';
import '../../../shared/widgets/expandable_text.dart';
import '../../../shared/widgets/loading_dialog.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../details/presentation/download_launcher.dart';
import '../../details/presentation/downloaded_file_provider.dart';
import '../../details/presentation/playback_launcher.dart';
import '../../details/presentation/widgets/download_management_dialog.dart';
import '../../details/presentation/widgets/download_progress_dialog.dart';

/// The opening screen for extension media, modelled 1:1 on the Home details
/// experience ([DetailsScreen]): the same banner-with-scrim app bar, the same
/// title + metadata + action row + expandable synopsis, and an episode list.
///
/// Everything on the page comes from the runtime bridge's unified
/// [SourceMethods.getDetail], so an Aniyomi source, a CloudStream plugin and a
/// Mangayomi/Sora script all land here with the same shape of metadata:
/// cover, description, author, artist, genres and episodes.
class MStreamDetailsScreen extends ConsumerStatefulWidget {
  const MStreamDetailsScreen({
    super.key,
    required this.media,
    required this.methods,
    required this.source,
  });

  /// The item as it arrived from the list (popular / latest / search). Carries
  /// enough to render instantly while [getDetail] loads.
  final DMedia media;

  /// The extension API surface, already bound to the owning [source].
  final SourceMethods methods;

  /// The extension that produced [media]; supplies the base URL used to
  /// resolve relative covers and the per-request Referer header.
  final Source source;

  /// Label used as the provider name fallback for player/download metadata.
  static const String title = 'MStream';

  @override
  ConsumerState<MStreamDetailsScreen> createState() =>
      _MStreamDetailsScreenState();
}

class _MStreamDetailsScreenState extends ConsumerState<MStreamDetailsScreen> {
  DMedia? _detail;
  Object? _error;
  bool _loading = true;

  /// Bumped on every load so a slow `getDetail` from a previous tap can never
  /// paint over the page the user is on now.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String get _referer => widget.source.baseUrl ?? '';

  Map<String, String> get _imageHeaders => {
        'User-Agent': kDefaultBrowserUserAgent,
        if (_referer.isNotEmpty) 'Referer': _referer,
      };

  /// Cover/poster URL resolved against the source's base URL. Extension
  /// covers are frequently site-relative paths.
  String _resolve(String? url) =>
      ImageUtils.resolveRemoteUrl(url ?? '', baseUrl: _referer);

  /// The card that opened this page uses this tag, so the poster flies up
  /// into the banner — the same shared-element opening as Home.
  String get _heroTag => 'mstream_poster_${widget.media.url}';

  Future<void> _load() async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.methods.getDetail(widget.media);
      if (!mounted || gen != _generation) return;
      // The bridge's CloudStream adapter (DMedia.fromCs) reverses episode
      // order on a condition that is always true, so the order a source
      // returns its episodes in ends up flipped. Sort deterministically here
      // so every extension lists episodes ascending by number.
      detail.episodes?.sort(DEpisode.compareByEpisodeNumber);
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e, st) {
      talker.error('MStream: getDetail failed', e, st);
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Plays an episode through Home's [PlaybackLauncher] - the exact path the
  /// plugin-based details screen uses, so external players, the downloaded-
  /// file intercept and stream failover all behave the same as Home:
  ///
  /// 1. an already-downloaded episode plays from disk (no network),
  /// 2. otherwise the extension resolves streams behind Home's cancelable
  ///    loading dialog (this used to freeze silently on slow sources),
  /// 3. external players receive stream one; the internal player opens with
  ///    every stream as failover.
  Future<void> _play(DEpisode episode) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final ep = _multimediaEpisode(episode);
    final item = _multimediaItem(episode, ep: ep);

    // Home's play path checks downloads first - a downloaded episode plays
    // from disk instead of hitting the network again.
    final localFile = await ref
        .read(downloadServiceProvider)
        .getDownloadedFile(item, episode: ep);
    if (!mounted) return;
    if (localFile != null) {
      await ref.read(playbackLauncherProvider).playResolved(
            context,
            item: item,
            videoUrl: localFile.path,
            episode: ep,
          );
      return;
    }

    final streams = await _resolveStreamsWithProgress(episode);
    if (streams == null || !mounted) return;
    if (streams.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.mstreamNoStreams)),
      );
      return;
    }

    await ref.read(playbackLauncherProvider).playResolved(
          context,
          item: item,
          videoUrl: streams.first.url,
          episode: ep,
          streams: streams,
        );
  }

  /// Downloads an episode through the same source picker the plugin-based
  /// downloads use. Streams are resolved by the extension first - the
  /// download launcher never talks to a SkyStream provider here - behind the
  /// same cancelable loading dialog the play path shows.
  Future<void> _download(DEpisode episode) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final streams = await _resolveStreamsWithProgress(episode);
    if (streams == null || !mounted) return;
    if (streams.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.mstreamNoStreams)),
      );
      return;
    }

    final ep = _multimediaEpisode(episode);
    final item = _multimediaItem(episode, ep: ep);
    await ref.read(downloadLauncherProvider).launch(
          context,
          item,
          episodeUrl: ep.url,
          preloadedStreams: streams,
        );
  }

  /// Wraps [_resolveStreams] in Home's [LoadingDialog] - visible progress
  /// with a working Cancel instead of a silent await. Returns null when the
  /// user cancels; the dialog lives on the root navigator (showDialog).
  Future<List<StreamResult>?> _resolveStreamsWithProgress(
    DEpisode episode,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    var canceled = false;
    unawaited(
      LoadingDialog.show(
        context,
        message: l10n.resolving,
        onCancel: () => canceled = true,
      ),
    );
    final streams = await _resolveStreams(episode);
    if (!mounted) return null;
    if (!canceled) {
      // Dismiss the loading dialog we opened - never a page below it.
      Navigator.of(context, rootNavigator: true).pop();
    }
    return canceled ? null : streams;
  }

  Future<List<StreamResult>?> _resolveStreams(DEpisode episode) async {
    final l10n = AppLocalizations.of(context)!;
    List<bridge.Video> videos;
    try {
      videos = await widget.methods.getVideoList(episode);
    } catch (e, st) {
      talker.error('MStream: getVideoList failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorPrefix('$e'))),
        );
      }
      return null;
    }
    return [
      for (final v in videos)
        StreamResult(
          url: v.url,
          source: v.quality,
          providerName: widget.source.name ?? MStreamDetailsScreen.title,
          headers: v.headers,
          subtitles: [
            for (final t in v.subtitles ?? const <Track>[])
              if ((t.file ?? '').isNotEmpty)
                SubtitleFile(url: t.file!, label: t.label ?? l10n.unknown),
          ],
        ),
    ];
  }

  /// The [Episode] twin of a bridge episode: the shape the player, the
  /// downloader and the history/download repos key their bookkeeping by.
  /// Always exactly one per bridge episode - no `!` anywhere downstream.
  Episode _multimediaEpisode(DEpisode episode) {
    final detail = _detail ?? widget.media;
    final l10n = AppLocalizations.of(context)!;
    final epName =
        episode.name ?? l10n.mstreamEpisodeNumber(episode.episodeNumber);
    return Episode(
      name: epName,
      url: episode.url ?? '',
      posterUrl: _resolve(episode.thumbnail ?? detail.cover),
      episode: int.tryParse(episode.episodeNumber) ?? 0,
    );
  }

  MultimediaItem _multimediaItem(DEpisode episode, {required Episode ep}) {
    final detail = _detail ?? widget.media;
    return MultimediaItem(
      title: detail.title ?? '',
      url: widget.media.url ?? '',
      posterUrl: _resolve(detail.cover ?? widget.media.cover),
      description: detail.description ?? widget.media.description,
      provider: widget.source.name ?? MStreamDetailsScreen.title,
      episodes: [ep],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The list copy renders instantly; the detail copy (with episodes) replaces
    // it when getDetail lands. Same idea as Home's optimistic title block.
    final media = _detail ?? widget.media;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(context, media, l10n),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      media.title ?? '',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _MetadataBar(
                      media: media,
                      episodeCount: _detail?.episodes?.length,
                    ),
                    const SizedBox(height: 24),
                    _buildActions(context, l10n),
                    const SizedBox(height: 24),
                    Text(
                      l10n.synopsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ExpandableText(
                      text: media.description?.isNotEmpty == true
                          ? media.description!
                          : l10n.noDescription,
                      maxLines: 4,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).textTheme.bodyMedium?.color,
                            height: 1.5,
                          ),
                    ),
                    const SizedBox(height: 32),
                    _buildEpisodes(context, l10n),
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    DMedia media,
    AppLocalizations l10n,
  ) {
    final cover = _resolve(media.cover ?? widget.media.cover);
    return SliverAppBar(
      pinned: true,
      expandedHeight: LayoutConstants.detailsExpandedHeightMobile,
      stretch: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [
          StretchMode.zoomBackground,
          StretchMode.blurBackground,
        ],
        background: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: _heroTag,
              child: cover.isEmpty
                  ? ThumbnailErrorPlaceholder(
                      label: media.title ?? '',
                      isBackdrop: true,
                    )
                  : CachedNetworkImage(
                      imageUrl: cover,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      httpHeaders: _imageHeaders,
                      // Bound the decoded bitmap exactly like the Home
                      // details banner; extension covers are often served at
                      // source resolution.
                      memCacheWidth: ImageUtils.coverDecodeWidth(
                        context,
                        width: MediaQuery.sizeOf(context).width,
                        height: LayoutConstants.detailsExpandedHeightMobile,
                        sourceAspectRatio: ImageUtils.backdropAspectRatio,
                      ),
                      placeholder: (context, url) =>
                          Container(color: Theme.of(context).dividerColor),
                      errorWidget: (_, _, _) => ThumbnailErrorPlaceholder(
                        label: media.title ?? '',
                        isBackdrop: true,
                      ),
                    ),
            ),
            // Legibility scrim — identical stops to the Home details banner.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.65),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
            // Blend-into-page transition — theme-aware eased fade to surface.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(context)
                        .scaffoldBackgroundColor
                        .withValues(alpha: 0.0),
                    Theme.of(context)
                        .scaffoldBackgroundColor
                        .withValues(alpha: 0.15),
                    Theme.of(context)
                        .scaffoldBackgroundColor
                        .withValues(alpha: 0.45),
                    Theme.of(context)
                        .scaffoldBackgroundColor
                        .withValues(alpha: 0.8),
                    Theme.of(context).scaffoldBackgroundColor,
                  ],
                  stops: const [0.0, 0.5, 0.75, 0.9, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
      leading: CustomButton(
        shape: const CircleBorder(),
        backgroundColor: Colors.black45,
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Icon(
          Icons.arrow_back_rounded,
          color: Colors.white,
        ),
      ),
    );
  }

  /// What the big Play/Download buttons act on: the first episode for
  /// series, the media itself for movies and one-shots. Movies must behave
  /// like Home — two buttons and nothing else.
  DEpisode get _playable {
    final episodes = _detail?.episodes ?? const <DEpisode>[];
    if (episodes.isNotEmpty) return episodes.first;
    return DEpisode(
      url: widget.media.url,
      name: widget.media.title,
      episodeNumber: '1',
    );
  }

  /// Movies and one-shots: Home shows just Play/Download and no episode
  /// strip. Only real multi-episode series get the episode list.
  bool get _showEpisodeList => (_detail?.episodes?.length ?? 0) >= 2;

  Widget _buildActions(BuildContext context, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(l10n.play),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => unawaited(_play(_playable)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.download_rounded),
            label: Text(l10n.download),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => unawaited(_download(_playable)),
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodeTile(DEpisode episode) {
    final ep = _multimediaEpisode(episode);
    return _EpisodeTile(
      episode: episode,
      item: _multimediaItem(episode, ep: ep),
      ep: ep,
      referer: _referer,
      imageHeaders: _imageHeaders,
      fallbackCover: _detail?.cover ?? widget.media.cover,
      onTap: () => unawaited(_play(episode)),
      onDownload: () => unawaited(_download(episode)),
    );
  }

  Widget _buildEpisodes(BuildContext context, AppLocalizations l10n) {
    final episodes = _detail?.episodes ?? const <DEpisode>[];
    // Movies/one-shots: no episode strip (Home shows just Play/Download).
    if (!_showEpisodeList) {
      // getDetail can still fail for metadata enrichment; the poster and
      // title above always render, so just offer a compact retry here.
      if (_error != null) {
        return _DetailErrorNotice(
          error: _error!,
          onRetry: () => unawaited(_load()),
        );
      }
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.episodes,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              '${episodes.length}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: AppLoadingIndicator()),
          )
        else if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context)!
                    .errorPrefix(_error.toString())),
                const SizedBox(height: 8),
                CustomButton(
                  isPrimary: true,
                  onPressed: () => unawaited(_load()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(l10n.retry),
                  ),
                ),
              ],
            ),
          )
        else if (episodes.isEmpty)
          Text(
            l10n.noEpisodesFound,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
          )
        else
          for (final episode in episodes) _buildEpisodeTile(episode),
      ],
    );
  }
}

/// The metadata row under the title: genres, author, artist and the episode
/// count, presented as the same style of compact pills Home uses.
class _MetadataBar extends StatelessWidget {
  const _MetadataBar({required this.media, this.episodeCount});

  final DMedia media;
  final int? episodeCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chips = <Widget>[
      for (final genre in media.genre ?? const <String>[])
        if (genre.trim().isNotEmpty) _pill(context, genre.trim()),
      if ((media.author ?? '').trim().isNotEmpty)
        _pill(context, '${l10n.author}: ${media.author!.trim()}'),
      if ((media.artist ?? '').trim().isNotEmpty)
        _pill(context, '${l10n.artist}: ${media.artist!.trim()}'),
      if (episodeCount != null)
        _pill(context, '$episodeCount ${l10n.episodes}'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  Widget _pill(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// One episode row: thumbnail, number + name, air date, and play/download
/// affordances. Same information hierarchy as the Home episode list.
/// One episode row. Carries the same two live states Home's EpisodeCard
/// shows: watch progress (badge + progress bar over the thumbnail) and
/// download state - management dialog when downloaded, progress dialog while
/// downloading, the source-picker launcher otherwise (never a silent
/// re-download of an owned file).
class _EpisodeTile extends ConsumerStatefulWidget {
  const _EpisodeTile({
    required this.episode,
    required this.item,
    required this.ep,
    required this.referer,
    required this.imageHeaders,
    required this.onTap,
    required this.onDownload,
    this.fallbackCover,
  });

  /// The bridge episode as rendered (name, thumbnail, dates).
  final DEpisode episode;

  /// Multimedia twins used for player/download/history bookkeeping - the
  /// same keys [EpisodeCard] and the download launcher use on Home.
  final MultimediaItem item;
  final Episode ep;

  final String referer;
  final Map<String, String> imageHeaders;
  final String? fallbackCover;
  final VoidCallback onTap;

  /// Invoked only when the episode is neither downloaded nor downloading -
  /// the resolve-then-launch flow.
  final VoidCallback onDownload;

  @override
  ConsumerState<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends ConsumerState<_EpisodeTile> {
  @override
  void initState() {
    super.initState();
    // Surface the download state on first paint (Home's card does this too).
    Future.microtask(_checkDownloaded);
  }

  @override
  void didUpdateWidget(covariant _EpisodeTile old) {
    super.didUpdateWidget(old);
    if (old.ep.url != widget.ep.url) {
      Future.microtask(_checkDownloaded);
    }
  }

  void _checkDownloaded() {
    if (!mounted) return;
    ref
        .read(downloadedFilesProvider.notifier)
        .checkFile(widget.item, episode: widget.ep);
  }

  void _onDownloadPressed() {
    final downloadedFile = ref.read(downloadedFilesProvider)[widget.ep.url];
    final isDownloading = ref
        .read(activeDownloadsProvider)
        .contains(widget.ep.url);
    if (downloadedFile != null) {
      // Owned file: manage (play local / delete) instead of re-downloading.
      DownloadManagementDialog.show(
        context,
        widget.item,
        downloadedFile,
        episode: widget.ep,
      );
    } else if (isDownloading) {
      DownloadProgressDialog.show(
        context,
        '${widget.item.title} - ${widget.ep.name}',
        widget.ep.url,
      );
    } else {
      widget.onDownload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final episode = widget.episode;

    // Watch progress - same repositories and keying as Home's EpisodeCard.
    final historyRepo = ref.watch(historyRepositoryProvider);
    final epPos = historyRepo.getEpisodePosition(
      widget.ep.url,
      mainUrl: widget.item.url,
      season: widget.ep.season,
      episode: widget.ep.episode,
    );
    final epDur = historyRepo.getEpisodeDuration(
      widget.ep.url,
      mainUrl: widget.item.url,
      season: widget.ep.season,
      episode: widget.ep.episode,
    );
    ref.watch(episodeWatchRevisionProvider);
    final episodeWatchRepo = ref.watch(episodeWatchRepositoryProvider);
    final progress = epDur > 0 ? (epPos / epDur).clamp(0.0, 1.0) : 0.0;
    final isWatched = episodeWatchRepo.isWatched(widget.item.url, widget.ep);
    final displayedProgress = isWatched ? 1.0 : progress;

    String? statusBadge;
    if (isWatched) {
      statusBadge = l10n.watched.toUpperCase();
    } else if (progress > 0.02) {
      statusBadge = l10n.watching.toUpperCase();
    }

    // Download state.
    final downloadedFile = ref.watch(downloadedFilesProvider)[widget.ep.url];
    final isDownloading = ref
        .watch(activeDownloadsProvider)
        .contains(widget.ep.url);
    final downloadProgress =
        ref.watch(downloadProgressProvider)[widget.ep.url]?.progress ?? 0.0;

    final thumb = ImageUtils.resolveRemoteUrl(
      episode.thumbnail ?? widget.fallbackCover ?? '',
      baseUrl: widget.referer,
    );
    final epLabel = episode.episodeNumber.isNotEmpty
        ? l10n.mstreamEpisodeNumber(episode.episodeNumber)
        : l10n.episodes;

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 112,
                    height: 64,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        thumb.isEmpty
                            ? ThumbnailErrorPlaceholder(label: epLabel)
                            : CachedNetworkImage(
                                imageUrl: thumb,
                                fit: BoxFit.cover,
                                httpHeaders: widget.imageHeaders,
                                placeholder: (context, url) =>
                                    const ColoredBox(color: Colors.black12),
                                errorWidget: (_, _, _) =>
                                    ThumbnailErrorPlaceholder(label: epLabel),
                              ),
                        // Watch progress along the bottom edge of the
                        // thumbnail, video-style.
                        if (displayedProgress > 0.02)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: LinearProgressIndicator(
                              value: displayedProgress,
                              minHeight: 3,
                              backgroundColor: Colors.black26,
                            ),
                          ),
                        if (statusBadge != null)
                          Align(
                            alignment: Alignment.topLeft,
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isWatched
                                    ? Colors.green.withValues(alpha: 0.9)
                                    : colorScheme.primary.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                statusBadge,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (episode.name == null ||
                                episode.name!.trim().isEmpty)
                            ? epLabel
                            : episode.name!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          epLabel,
                          if ((episode.dateUpload ?? '').isNotEmpty)
                            episode.dateUpload!,
                          if ((episode.scanlator ?? '').isNotEmpty)
                            episode.scanlator!,
                        ].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n.download,
                  icon: isDownloading
                      // Live progress ring while the download runs.
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            value: downloadProgress > 0
                                ? downloadProgress
                                : null,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Icon(
                          downloadedFile != null
                              ? Icons.download_done_rounded
                              : Icons.download_outlined,
                          size: 20,
                          color: downloadedFile != null ? Colors.green : null,
                        ),
                  onPressed: _onDownloadPressed,
                ),
                IconButton(
                  tooltip: l10n.play,
                  icon: Icon(
                    Icons.play_circle_fill_rounded,
                    size: 32,
                    color: colorScheme.primary,
                  ),
                  onPressed: widget.onTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact "couldn't load more details" note used where a full-page retry
/// would hide the metadata and poster that are already on screen.
class _DetailErrorNotice extends StatelessWidget {
  const _DetailErrorNotice({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.errorPrefix(error.toString())),
          const SizedBox(height: 8),
          CustomButton(
            isPrimary: true,
            onPressed: onRetry,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(l10n.retry),
            ),
          ),
        ],
      ),
    );
  }
}
