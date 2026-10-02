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
import '../../../shared/widgets/cards_wrapper.dart';
import '../../../shared/widgets/shimmer_placeholder.dart';
import '../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../multiproviders/data/multiprovider_bridge.dart';

/// Browses and plays the sources installed through MultiProviders.
///
/// Everything here goes through the runtime bridge's unified [SourceMethods],
/// so an Aniyomi source, a CloudStream plugin and a Mangayomi/Sora script are
/// all driven by the same four calls: popular, search, detail, video list.
///
/// The extension-change affordance mirrors Home's: a pill in the top-right
/// corner naming the active source opens a selector dialog, and picking a
/// source reloads the tab.
class MStreamScreen extends ConsumerStatefulWidget {
  const MStreamScreen({super.key});

  /// Label shown in the bottom nav bar and the sidebar.
  static const String title = 'MStream';

  @override
  ConsumerState<MStreamScreen> createState() => _MStreamScreenState();
}

class _MStreamScreenState extends ConsumerState<MStreamScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Source? _source;
  String _query = '';

  final List<DMedia> _items = <DMedia>[];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasNextPage = false;
  int _page = 1;

  /// Bumped on every new request; late responses from a superseded request
  /// see a different number and drop themselves instead of overwriting the
  /// list with stale results.
  int _generation = 0;

  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(multiProviderBridgeProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || _loadingMore || !_hasNextPage) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      unawaited(_fetch(append: true));
    }
  }

  /// Fetches the current page from the active source.
  ///
  /// With no query this is the source's popular feed, falling back to its
  /// latest feed when popular is missing or fails (several extension families
  /// implement only one of the two, and an unguarded popular call is the
  /// classic "the grid never loads" report). With a query it is search.
  Future<Pages> _request(SourceMethods methods, int page) async {
    final query = _query;
    if (query.isEmpty) {
      try {
        return await methods.getPopular(page);
      } catch (_) {
        return methods.getLatestUpdates(page);
      }
    }
    return methods.search(query, page, const <dynamic>[]);
  }

  /// Replaces ([append] false) or extends ([append] true) the grid.
  Future<void> _fetch({bool append = false}) async {
    final source = _source;
    if (source == null) return;
    final methods = ref
        .read(multiProviderBridgeProvider.notifier)
        .methodsFor(source);
    if (methods == null) return;

    final generation = ++_generation;
    setState(() {
      _error = null;
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _hasNextPage = false;
        _page = 1;
      }
    });

    final page = append ? _page + 1 : 1;
    try {
      final pages = await _request(methods, page);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (append) {
          _items.addAll(pages.list);
          _page = page;
        } else {
          _items
            ..clear()
            ..addAll(pages.list);
          _page = 1;
        }
        _hasNextPage = pages.hasNextPage && pages.list.isNotEmpty;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e, st) {
      talker.error('MStream: fetch failed for ${source.name}', e, st);
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (append) {
          // Keep what is on screen; the retry is a plain scroll back into the
          // gap. A full-grid error would throw away results that loaded fine.
          _hasNextPage = true;
        } else {
          _error = e;
        }
      });
    }
  }

  void _selectSource(Source source) {
    setState(() {
      _source = source;
      _query = '';
      _items.clear();
      _error = null;
      _hasNextPage = false;
      _page = 1;
    });
    _searchController.clear();
    unawaited(
      ref.read(multiProviderBridgeProvider.notifier).setLastSourceId(
        source.uniqueId,
      ),
    );
    unawaited(_fetch());
  }

  void _submitQuery(String raw) {
    final query = raw.trim();
    if (query == _query) {
      // Re-submitting the same query is the "try again" gesture for search.
      unawaited(_fetch());
      return;
    }
    setState(() => _query = query);
    unawaited(_fetch());
  }

  void _clearQuery() {
    _searchController.clear();
    if (_query.isEmpty) return;
    setState(() => _query = '');
    unawaited(_fetch());
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
          // Extension pill selector, right corner — the same affordance
          // Home carries, so switching source works the same way in both.
          sourcesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (sources) {
              final enabled = _enabledSources(sources, state);
              return _SourcePill(
                name: _source?.name ?? l10n.none,
                onTap: () => _showSourceSelector(enabled, sources),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (state.isBusy) const LinearProgressIndicator(),
            sourcesAsync.when(
              loading: () => const Expanded(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Expanded(
                child: _EmptyState(
                  message: '$e',
                  actionLabel: l10n.retry,
                  onAction: () =>
                      ref.invalidate(installedSourcesProvider),
                ),
              ),
              data: (sources) {
                final installed = _enabledSources(sources, state);
                if (sources.isEmpty) {
                  return Expanded(
                    child: _EmptyState(
                      message: l10n.mstreamNoSources,
                      actionLabel: l10n.mstreamManageProviders,
                      onAction: () => const MultiProvidersRoute().go(context),
                    ),
                  );
                }
                if (installed.isEmpty) {
                  return Expanded(
                    child: _EmptyState(
                      message: l10n.mstreamAllDisabled,
                      actionLabel: l10n.mstreamManageProviders,
                      onAction: () => const MultiProvidersRoute().go(context),
                    ),
                  );
                }

                // Keep the selection valid: remember the user's pick across
                // restarts, then survive uninstalls/disables by falling back.
                final selected = _selectedSource(installed);
                if (selected.uniqueId != _source?.uniqueId) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (_source == null) {
                      _selectSource(selected);
                    } else {
                      setState(() => _source = selected);
                      unawaited(_fetch());
                    }
                  });
                }

                return _Toolbar(
                  controller: _searchController,
                  onSubmitted: _submitQuery,
                  onClear: _clearQuery,
                  onRefresh: () => unawaited(_fetch()),
                );
              },
            ),
            Expanded(child: _buildResults(l10n)),
          ],
        ),
      ),
    );
  }

  List<Source> _enabledSources(List<Source> sources, MultiProviderBridgeState s) {
    return sources
        .where((source) => !s.isDisabled(source.uniqueId))
        .toList(growable: false);
  }

  Source _selectedSource(List<Source> enabled) {
    final current = _source;
    if (current != null) {
      for (final source in enabled) {
        if (source.uniqueId == current.uniqueId) return source;
      }
    }
    final remembered = ref.read(multiProviderBridgeProvider).lastSourceId;
    if (remembered != null) {
      for (final source in enabled) {
        if (source.uniqueId == remembered) return source;
      }
    }
    return enabled.first;
  }

  Widget _buildResults(AppLocalizations l10n) {
    final source = _source;
    if (source == null) {
      return _EmptyState(message: l10n.mstreamPickSource);
    }

    final error = _error;
    if (error != null) {
      return _EmptyState(
        message: '${l10n.failedToLoadContent}\n$error',
        actionLabel: l10n.retry,
        onAction: () => unawaited(_fetch()),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return _EmptyState(
        message: l10n.mstreamNothingFound,
        actionLabel: l10n.retry,
        onAction: () => unawaited(_fetch()),
      );
    }

    final referer = source.baseUrl ?? '';
    return RefreshIndicator(
      onRefresh: () => _fetch(),
      child: GridView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
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
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return _MediaCard(
            media: _items[i],
            referer: referer,
            onTap: () => _openMedia(_items[i]),
          );
        },
      ),
    );
  }

  void _showSourceSelector(List<Source> enabled, List<Source> installed) {
    final l10n = AppLocalizations.of(context)!;
    if (installed.isEmpty) {
      _showManageDialog(l10n.mstreamNoSources);
      return;
    }
    if (enabled.isEmpty) {
      _showManageDialog(l10n.mstreamAllDisabled);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => _SourceSelectorDialog(
        sources: enabled,
        activeId: _source?.uniqueId,
        // The dialog pops itself through its own context - showDialog pushes
        // on the root navigator, so popping with this screen's context would
        // hit the shell navigator instead and leave the dialog on screen.
        onSelected: _selectSource,
      ),
    );
  }

  void _showManageDialog(String message) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.mstreamManageProviders),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.extension, size: 18),
            label: Text(l10n.mstreamManageProviders),
            onPressed: () {
              Navigator.pop(context);
              const MultiProvidersRoute().go(context);
            },
          ),
        ],
      ),
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
      posterUrl: ImageUtils.resolveRemoteUrl(
        media.cover ?? '',
        baseUrl: source.baseUrl,
      ),
      description: media.description,
      provider: source.name ?? MStreamScreen.title,
      episodes: [
        Episode(
          name: epName,
          url: episode.url ?? '',
          posterUrl: ImageUtils.resolveRemoteUrl(
            episode.thumbnail ?? media.cover ?? '',
            baseUrl: source.baseUrl,
          ),
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

/// The pill naming the active source. Same geometry and styling as the one on
/// Home so the two tabs read as one product.
class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: LayoutConstants.spacingMd),
      child: CardsWrapper(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(50),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.extension,
                color: Theme.of(context).colorScheme.onSurface,
                size: 16,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.onSubmitted,
    required this.onClear,
    required this.onRefresh,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onRefresh;

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
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: l10n.discoverClearSearch,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: onClear,
                        ),
                ),
              ),
              onSubmitted: onSubmitted,
            ),
          ),
          const SizedBox(width: LayoutConstants.spacingSm),
          IconButton(
            tooltip: l10n.refresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.media,
    required this.referer,
    required this.onTap,
  });

  final DMedia media;
  final String referer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = ImageUtils.resolveRemoteUrl(
      media.cover ?? '',
      baseUrl: referer,
    );
    final headers = <String, String>{
      'User-Agent': kDefaultBrowserUserAgent,
      if (referer.isNotEmpty) 'Referer': referer,
    };
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
                  ? ThumbnailErrorPlaceholder(label: media.title)
                  : CachedNetworkImage(
                      imageUrl: cover,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      httpHeaders: headers,
                      placeholder: (context, url) =>
                          ShimmerPlaceholder(borderRadius: 12),
                      errorWidget: (_, _, _) =>
                          ThumbnailErrorPlaceholder(label: media.title),
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

/// The source picker, modelled on Home's provider selector: filter chips over
/// the top, a radio list of sources below.
class _SourceSelectorDialog extends StatefulWidget {
  const _SourceSelectorDialog({
    required this.sources,
    required this.activeId,
    required this.onSelected,
  });

  final List<Source> sources;
  final String? activeId;
  final ValueChanged<Source> onSelected;

  @override
  State<_SourceSelectorDialog> createState() => _SourceSelectorDialogState();
}

class _SourceSelectorDialogState extends State<_SourceSelectorDialog> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _chipsScrollController = ScrollController();

  /// `null` is the "All" chip. Kept local to the dialog: it is a browse-time
  /// filter, not a setting worth persisting.
  ItemType? _filter;
  bool _didInitialScroll = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _chipsScrollController.dispose();
    super.dispose();
  }

  List<ItemType> get _presentTypes {
    final types = <ItemType>{
      for (final s in widget.sources)
        if (s.itemType != null) s.itemType!,
    };
    return [
      for (final type in ItemType.values)
        if (types.contains(type)) type,
    ];
  }

  List<Source> get _filtered => _filter == null
      ? widget.sources
      : widget.sources.where((s) => s.itemType == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final filtered = _filtered;

    return AlertDialog(
      title: Text(l10n.selectProvider),
      contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_presentTypes.length > 1)
              SizedBox(
                height: 48,
                child: ListView(
                  controller: _chipsScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      label: Text(l10n.all),
                      selected: _filter == null,
                      onSelected: (_) => setState(() => _filter = null),
                    ),
                    const SizedBox(width: 8),
                    for (final type in _presentTypes)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          label: Text(_typeLabel(type, l10n)),
                          selected: _filter == type,
                          onSelected: (_) => setState(() => _filter = type),
                        ),
                      ),
                  ],
                ),
              ),
            if (_presentTypes.length > 1) const Divider(),
            Flexible(
                child: RadioGroup<String>(
                  groupValue: widget.activeId,
                  onChanged: (id) {
                    if (id == null) return;
                    for (final source in widget.sources) {
                      if (source.uniqueId == id) {
                        _pick(source);
                        return;
                      }
                    }
                  },
                child: Material(
                  color: Colors.transparent,
                  clipBehavior: Clip.hardEdge,
                  child: ListView.builder(
                    controller: _scrollController,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      if (!_didInitialScroll) {
                        _didInitialScroll = true;
                        _scrollToActive(filtered);
                      }
                      final source = filtered[index];
                      return SizedBox(
                        height: 56,
                        child: Center(
                          child: ListTile(
                            leading: Radio<String>(
                              value: source.uniqueId,
                            ),
                            title: Text(
                              source.name ?? l10n.unknown,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                source.lang?.toUpperCase() ?? '',
                                source.managerId ?? '',
                              ].where((s) => s.isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _pick(source),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }

  void _pick(Source source) {
    // Pops through this dialog's own context: showDialog pushes on the root
    // navigator, and this context hangs under it.
    Navigator.of(context).pop();
    widget.onSelected(source);
  }

  void _scrollToActive(List<Source> filtered) {
    var targetIndex = filtered.indexWhere(
      (s) => s.uniqueId == widget.activeId,
    );
    if (targetIndex == -1) targetIndex = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      const itemHeight = 56.0;
      final itemTop = targetIndex * itemHeight;
      final viewportHeight = _scrollController.position.viewportDimension;
      final offset =
          itemTop - (viewportHeight / 2) + (itemHeight / 2);
      final maxScroll = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(offset.clamp(0.0, maxScroll));
    });
  }

  String _typeLabel(ItemType type, AppLocalizations l10n) {
    switch (type) {
      case ItemType.anime:
        return l10n.anime;
      case ItemType.manga:
        return l10n.manga;
      case ItemType.novel:
        return l10n.novel;
    }
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
          if (snapshot.hasError) {
            return _EmptyState(
              message: '${snapshot.error}',
              actionLabel: l10n.close,
              onAction: () => Navigator.of(context).pop(),
            );
          }
          final episodes = snapshot.data?.episodes ?? const <DEpisode>[];
          if (episodes.isEmpty) return _EmptyState(message: l10n.mstreamNoEpisodes);
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LayoutConstants.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: LayoutConstants.spacingMd),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
