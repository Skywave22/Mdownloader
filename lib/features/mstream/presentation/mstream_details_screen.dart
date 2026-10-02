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
import '../../../core/router/app_router.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../shared/widgets/custom_widgets.dart';
import '../../../shared/widgets/expandable_text.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../details/presentation/download_launcher.dart';

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

  /// Resolves the episode's streams and hands them to the player already
  /// resolved: these come from an extension, not from a SkyStream plugin, so
  /// the player must not try to resolve the URL again.
  Future<void> _play(DEpisode episode) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final streams = await _resolveStreams(episode);
    if (streams == null || !mounted) return;
    if (streams.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.mstreamNoStreams)),
      );
      return;
    }

    final item = _multimediaItem(episode);
    await PlayerRoute(
      $extra: PlayerRouteExtra(
        item: item,
        videoUrl: streams.first.url,
        episode: item.episodes!.first,
        preloadedStreams: streams,
      ),
    ).push<void>(context);
  }

  /// Downloads an episode through the same source picker the plugin-based
  /// downloads use. Streams are resolved by the extension first — the
  /// download launcher never talks to a SkyStream provider here.
  Future<void> _download(DEpisode episode) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final streams = await _resolveStreams(episode);
    if (streams == null || !mounted) return;
    if (streams.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.mstreamNoStreams)),
      );
      return;
    }

    final item = _multimediaItem(episode);
    await ref.read(downloadLauncherProvider).launch(
          context,
          item,
          episodeUrl: episode.url ?? '',
          preloadedStreams: streams,
        );
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

  MultimediaItem _multimediaItem(DEpisode episode) {
    final detail = _detail ?? widget.media;
    final l10n = AppLocalizations.of(context)!;
    final epName =
        episode.name ?? l10n.mstreamEpisodeNumber(episode.episodeNumber);
    return MultimediaItem(
      title: detail.title ?? '',
      url: widget.media.url ?? '',
      posterUrl: _resolve(detail.cover ?? widget.media.cover),
      description: detail.description ?? widget.media.description,
      provider: widget.source.name ?? MStreamDetailsScreen.title,
      episodes: [
        Episode(
          name: epName,
          url: episode.url ?? '',
          posterUrl: _resolve(episode.thumbnail ?? detail.cover),
          episode: int.tryParse(episode.episodeNumber) ?? 0,
        ),
      ],
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
          for (final episode in episodes)
            _EpisodeTile(
              episode: episode,
              referer: _referer,
              imageHeaders: _imageHeaders,
              fallbackCover: _detail?.cover ?? widget.media.cover,
              onTap: () => unawaited(_play(episode)),
              onDownload: () => unawaited(_download(episode)),
            ),
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
class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.referer,
    required this.imageHeaders,
    required this.onTap,
    required this.onDownload,
    this.fallbackCover,
  });

  final DEpisode episode;
  final String referer;
  final Map<String, String> imageHeaders;
  final String? fallbackCover;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final thumb = ImageUtils.resolveRemoteUrl(
      episode.thumbnail ?? fallbackCover ?? '',
      baseUrl: referer,
    );
    final epLabel = episode.episodeNumber.isNotEmpty
        ? l10n.mstreamEpisodeNumber(episode.episodeNumber)
        : l10n.episodes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 112,
                    height: 64,
                    child: thumb.isEmpty
                        ? ThumbnailErrorPlaceholder(label: epLabel)
                        : CachedNetworkImage(
                            imageUrl: thumb,
                            fit: BoxFit.cover,
                            httpHeaders: imageHeaders,
                            placeholder: (context, url) =>
                                const ColoredBox(color: Colors.black12),
                            errorWidget: (_, _, _) =>
                                ThumbnailErrorPlaceholder(label: epLabel),
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
                  icon: const Icon(Icons.download_outlined, size: 20),
                  onPressed: onDownload,
                ),
                IconButton(
                  tooltip: l10n.play,
                  icon: Icon(
                    Icons.play_circle_fill_rounded,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: onTap,
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
