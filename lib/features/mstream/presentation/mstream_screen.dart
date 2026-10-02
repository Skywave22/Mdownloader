import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart'
    hide Video;
import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart'
    as bridge show Video;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/logger/app_logger.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/layout_constants.dart';
import '../../multiproviders/data/multiprovider_bridge.dart';

/// Browses and plays the sources installed through MultiProviders.
///
/// Everything here goes through the runtime bridge's unified [SourceMethods],
/// so an Aniyomi source, a CloudStream plugin and a Mangayomi/Sora script are
/// all driven by the same four calls: popular, search, detail, video list.
class MStreamScreen extends ConsumerStatefulWidget {
  const MStreamScreen({super.key});

  /// Label shown in the bottom nav bar and the sidebar.
  static const String title = 'MStream';

  @override
  ConsumerState<MStreamScreen> createState() => _MStreamScreenState();
}

class _MStreamScreenState extends ConsumerState<MStreamScreen> {
  final _searchController = TextEditingController();
  Source? _source;
  String _query = '';
  Future<Pages>? _results;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(multiProviderBridgeProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _load() {
    final source = _source;
    if (source == null) {
      setState(() => _results = null);
      return;
    }
    final methods = ref.read(multiProviderBridgeProvider.notifier).methodsFor(
          source,
        );
    if (methods == null) {
      setState(() => _results = null);
      return;
    }
    setState(() {
      _results = _query.isEmpty
          ? methods.getPopular(1)
          : methods.search(_query, 1, const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(multiProviderBridgeProvider);
    final sourcesAsync = ref.watch(installedSourcesProvider(ItemType.anime));
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: const Text(MStreamScreen.title),
        actions: [
          IconButton(
            tooltip: l10n.mstreamManageProviders,
            icon: const Icon(Icons.extension_rounded),
            onPressed: () => const MultiProvidersRoute().go(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (state.isBusy) const LinearProgressIndicator(),
            sourcesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => _Message('$e'),
              data: (sources) {
                if (sources.isEmpty) {
                  return Expanded(child: _Message(l10n.mstreamNoSources));
                }
                // Keep the selection valid when a source is uninstalled.
                final selected = sources.firstWhere(
                  (s) => s.uniqueId == _source?.uniqueId,
                  orElse: () => sources.first,
                );
                if (selected.uniqueId != _source?.uniqueId) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() => _source = selected);
                    _load();
                  });
                }
                return _Toolbar(
                  sources: sources,
                  selected: selected,
                  controller: _searchController,
                  onSourceChanged: (s) {
                    setState(() => _source = s);
                    _load();
                  },
                  onSubmitted: (q) {
                    setState(() => _query = q.trim());
                    _load();
                  },
                );
              },
            ),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    final l10n = AppLocalizations.of(context)!;
    final future = _results;
    if (future == null) {
      return _Message(l10n.mstreamPickSource);
    }
    return FutureBuilder<Pages>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _Message('${snapshot.error}');
        }
        final items = snapshot.data?.list ?? const <DMedia>[];
        if (items.isEmpty) return _Message(l10n.mstreamNothingFound);
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            LayoutConstants.spacingMd,
            LayoutConstants.spacingMd,
            LayoutConstants.spacingMd,
            LayoutConstants.shellBottomContentPadding(context),
          ),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            childAspectRatio: 0.58,
            crossAxisSpacing: LayoutConstants.spacingSm,
            mainAxisSpacing: LayoutConstants.spacingSm,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => _MediaCard(
            media: items[i],
            onTap: () => _openMedia(items[i]),
          ),
        );
      },
    );
  }

  Future<void> _openMedia(DMedia media) async {
    final source = _source;
    if (source == null) return;
    final methods =
        ref.read(multiProviderBridgeProvider.notifier).methodsFor(source);
    if (methods == null) return;

    final episode = await showModalBottomSheet<DEpisode>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _EpisodeSheet(
        title: media.title ?? '',
        detail: methods.getDetail(media),
      ),
    );
    if (episode == null || !mounted) return;
    await _play(media, episode, methods, source);
  }

  /// Resolves the episode's streams and hands them to the player already
  /// resolved: these come from an extension, not from a SkyStream plugin, so
  /// the player must not try to resolve the URL again.
  Future<void> _play(
    DMedia media,
    DEpisode episode,
    SourceMethods methods,
    Source source,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    List<bridge.Video> videos;
    try {
      videos = await methods.getVideoList(episode);
    } catch (e, st) {
      talker.error('MStream: getVideoList failed', e, st);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!mounted) return;
    if (videos.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.mstreamNoStreams)),
      );
      return;
    }

    final streams = [
      for (final v in videos)
        StreamResult(
          url: v.url,
          source: v.quality,
          providerName: source.name ?? MStreamScreen.title,
          headers: v.headers,
          subtitles: [
            for (final t in v.subtitles ?? const <Track>[])
              if ((t.file ?? '').isNotEmpty)
                SubtitleFile(url: t.file!, label: t.label ?? l10n.unknown),
          ],
        ),
    ];

    final title = media.title ?? '';
    final epName =
        episode.name ?? l10n.mstreamEpisodeNumber(episode.episodeNumber);
    final item = MultimediaItem(
      title: title,
      url: media.url ?? '',
      posterUrl: media.cover ?? '',
      description: media.description,
      provider: source.name ?? MStreamScreen.title,
      episodes: [
        Episode(
          name: epName,
          url: episode.url ?? '',
          posterUrl: episode.thumbnail ?? media.cover ?? '',
          episode: int.tryParse(episode.episodeNumber) ?? 0,
        ),
      ],
    );

    if (!mounted) return;
    await PlayerRoute(
      $extra: PlayerRouteExtra(
        item: item,
        videoUrl: streams.first.url,
        episode: item.episodes!.first,
        preloadedStreams: streams,
      ),
    ).push<void>(context);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.sources,
    required this.selected,
    required this.controller,
    required this.onSourceChanged,
    required this.onSubmitted,
  });

  final List<Source> sources;
  final Source selected;
  final TextEditingController controller;
  final ValueChanged<Source> onSourceChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(LayoutConstants.spacingMd),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: l10n.mstreamSearchHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: onSubmitted,
            ),
          ),
          const SizedBox(width: LayoutConstants.spacingSm),
          DropdownButton<String>(
            value: selected.uniqueId,
            underline: const SizedBox.shrink(),
            items: [
              for (final s in sources)
                DropdownMenuItem(
                  value: s.uniqueId,
                  child: Text(s.name ?? l10n.unknown),
                ),
            ],
            onChanged: (id) {
              final next = sources.firstWhere((s) => s.uniqueId == id);
              onSourceChanged(next);
            },
          ),
        ],
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.media, required this.onTap});

  final DMedia media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = media.cover ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: cover.isEmpty
                  ? const ColoredBox(
                      color: Colors.black12,
                      child: Center(child: Icon(Icons.movie_outlined)),
                    )
                  : Image.network(
                      cover,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Colors.black12,
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            media.title ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Episode picker: loads the full detail, then lists what can be played.
class _EpisodeSheet extends StatelessWidget {
  const _EpisodeSheet({required this.title, required this.detail});

  final String title;
  final Future<DMedia> detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FractionallySizedBox(
      heightFactor: 0.8,
      child: FutureBuilder<DMedia>(
        future: detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _Message('${snapshot.error}');
          final episodes = snapshot.data?.episodes ?? const <DEpisode>[];
          if (episodes.isEmpty) return _Message(l10n.mstreamNoEpisodes);
          return ListView.builder(
            itemCount: episodes.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return ListTile(
                  title: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              }
              final ep = episodes[i - 1];
              return ListTile(
                leading: const Icon(Icons.play_circle_outline_rounded),
                title: Text(
                  ep.name ?? l10n.mstreamEpisodeNumber(ep.episodeNumber),
                ),
                subtitle: ep.episodeNumber.isEmpty
                    ? null
                    : Text(l10n.mstreamEpisodeNumber(ep.episodeNumber)),
                onTap: () => Navigator.of(context).pop(ep),
              );
            },
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(LayoutConstants.spacingLg),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}
