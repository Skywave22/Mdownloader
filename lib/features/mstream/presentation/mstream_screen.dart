import 'dart:async';

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart'
    hide Video;
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
import '../../explore/presentation/view_all_screen.dart';
import '../../explore/presentation/widgets/explore_carousel.dart';
import '../../explore/presentation/widgets/media_horizontal_list.dart';
import '../../multiproviders/data/multiprovider_bridge.dart';
import 'mstream_details_screen.dart';
import 'mstream_feed_grid.dart';

/// Browses and plays the sources installed through MultiProviders.
///
/// The layout is Home's, adapted to extension feeds: the same app-bar chrome
/// (title, circular search button, provider pill in the right corner), the
/// same hero carousel of top titles, and the same horizontal rails with
/// "View All". Everything here goes through the runtime bridge's unified
/// [SourceMethods], so an Aniyomi source, a CloudStream plugin and a
/// Mangayomi/Sora script are all driven by the same calls.
class MStreamScreen extends ConsumerStatefulWidget {
  const MStreamScreen({super.key});

  /// Label shown in the bottom nav bar and the sidebar.
  static const String title = 'MStream';

  @override
  ConsumerState<MStreamScreen> createState() => _MStreamScreenState();
}

class _MStreamScreenState extends ConsumerState<MStreamScreen> {
  Source? _source;

  /// The source's popular feed (page 1). The carousel and the Popular rail
  /// render from it; the rail's "View All" pages it in full.
  List<DMedia> _popular = const <DMedia>[];

  /// The source's latest-updates feed (page 1) for its rail. Empty (and the
  /// rail hidden) when the source has only one listing and both feeds return
  /// the same items.
  List<DMedia> _latest = const <DMedia>[];

  bool _loading = false;
  int _generation = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(multiProviderBridgeProvider.notifier).initialize();
    });
  }

  String get _referer => _source?.baseUrl ?? '';

  Map<String, String> get _imageHeaders => {
        'User-Agent': kDefaultBrowserUserAgent,
        if (_referer.isNotEmpty) 'Referer': _referer,
      };

  /// Loads both feeds for the active source at once. Each feed falls back to
  /// the other listing when the source implements only one of the two (a
  /// common extension shape), so browse mode never comes up empty just
  /// because `getPopular` is missing.
  Future<void> _loadFeeds() async {
    final source = _source;
    if (source == null) return;
    final methods =
        ref.read(multiProviderBridgeProvider.notifier).methodsFor(source);
    if (methods == null) {
      // A source whose methods cannot be resolved (extension not registered/
      // runtime not ready) is a load FAILURE - surface the retry state
      // instead of leaving the screen silently blank.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context)!.failedToLoadContent;
      });
      return;
    }

    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });

    List<DMedia> popular = const <DMedia>[];
    List<DMedia> latest = const <DMedia>[];
    Object? error;

    // Pages 1+2 per feed, deduped by URL: thin page-1 results used to leave
    // the screen at "1-2 items and one row".
    Future<List<DMedia>> twoPages(
      Future<Pages> Function(int page) listing,
    ) async {
      final pages = await Future.wait([listing(1), listing(2)]);
      final seen = <String>{};
      return [
        for (final m in [...pages[0].list, ...pages[1].list])
          if (m.url == null || seen.add(m.url!)) m,
      ];
    }

    try {
      popular = await twoPages(methods.getPopular);
      if (popular.isEmpty) {
        popular = await twoPages(methods.getLatestUpdates);
      }
    } catch (e) {
      error = e;
      try {
        popular = await twoPages(methods.getLatestUpdates);
        error = null;
      } catch (_) {/* keep the first error */}
    }
    try {
      latest = await twoPages(methods.getLatestUpdates);
      if (latest.isEmpty) {
        latest = await twoPages(methods.getPopular);
      }
    } catch (e) {
      error ??= e;
      try {
        latest = await twoPages(methods.getPopular);
        error = null;
      } catch (_) {/* keep the first error */}
    }

    if (!mounted || generation != _generation) return;

    talker.debug(
      'MStream: ${source.name} feeds — popular=${popular.length} '
      'latest=${latest.length} error=$error',
    );

    setState(() {
      _popular = popular;
      // Both rails always render (like Home); sources whose single listing
      // answers both feeds show it under both labels rather than losing one.
      _latest = latest;
      _loading = false;
      _error = (popular.isEmpty && latest.isEmpty) ? error : null;
    });
  }

  void _selectSource(Source source) {
    setState(() {
      _source = source;
      _popular = const <DMedia>[];
      _latest = const <DMedia>[];
      _error = null;
    });
    unawaited(
      ref.read(multiProviderBridgeProvider.notifier).setLastSourceId(
        source.uniqueId,
      ),
    );
    unawaited(_loadFeeds());
  }

  void _openMedia(DMedia media) {
    final source = _source;
    if (source == null) return;
    final methods =
        ref.read(multiProviderBridgeProvider.notifier).methodsFor(source);
    if (methods == null) return;

    // Home's opening experience: a full details page with the poster banner,
    // metadata, synopsis and episode list. Pushed on the ROOT navigator -
    // Home's /details and /player routes live there too, so the player and
    // every dialog below stack exactly like they do on Home (the shell
    // navigation bar is covered instead of peeking beside the player).
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MStreamDetailsScreen(
          media: media,
          methods: methods,
          source: source,
        ),
      ),
    );
  }

  void _openAll(String title, MStreamFeed feed) {
    final source = _source;
    if (source == null) return;
    final methods =
        ref.read(multiProviderBridgeProvider.notifier).methodsFor(source);
    if (methods == null) return;
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MStreamAllScreen(
          title: title,
          methods: methods,
          source: source,
          feed: feed,
        ),
      ),
    );
  }

  /// Home's search affordance: the same circular button opens the same search
  /// UI — scoped to the active extension instead of the global catalog.
  void _openSearch() {
    final source = _source;
    if (source == null) return;
    final methods =
        ref.read(multiProviderBridgeProvider.notifier).methodsFor(source);
    if (methods == null) return;
    final l10n = AppLocalizations.of(context)!;
    unawaited(
      showSearch<void>(
        context: context,
        delegate: _SourceSearchDelegate(
          methods: methods,
          source: source,
          hint: l10n.mstreamSearchHint,
        ),
        useRootNavigator: false,
        maintainState: true,
      ),
    );
  }

  MultimediaItem _toItem(DMedia media) {
    return MultimediaItem(
      title: media.title ?? '',
      url: media.url ?? '',
      posterUrl: ImageUtils.resolveRemoteUrl(
        media.cover ?? '',
        baseUrl: _referer,
      ),
      description: media.description,
      provider: _source?.name ?? MStreamScreen.title,
    );
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
          // 1. Search Action Button — Home's exact button.
          Padding(
            padding: const EdgeInsets.only(right: LayoutConstants.spacingSm),
            child: CardsWrapper(
              onTap: _openSearch,
              borderRadius: BorderRadius.circular(50),
              child: CircleAvatar(
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.1),
                radius: 18,
                child: Icon(
                  Icons.search,
                  color: Theme.of(context).colorScheme.onSurface,
                  size: 18,
                ),
              ),
            ),
          ),

          // 2. Source pill — Home's provider pill, right corner.
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
            Expanded(
              child: sourcesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _EmptyState(
                  message: '$e',
                  actionLabel: l10n.retry,
                  onAction: () => ref.invalidate(installedSourcesProvider),
                ),
                data: (sources) {
                  final installed = _enabledSources(sources, state);
                  if (sources.isEmpty) {
                    return _EmptyState(
                      message: l10n.mstreamNoSources,
                      actionLabel: l10n.mstreamManageProviders,
                      onAction: () =>
                          const MultiProvidersRoute().go(context),
                    );
                  }
                  if (installed.isEmpty) {
                    return _EmptyState(
                      message: l10n.mstreamAllDisabled,
                      actionLabel: l10n.mstreamManageProviders,
                      onAction: () =>
                          const MultiProvidersRoute().go(context),
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
                        unawaited(_loadFeeds());
                      }
                    });
                  }

                  return _buildContent(l10n);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    final source = _source;
    if (source == null) {
      return _EmptyState(message: l10n.mstreamPickSource);
    }

    final error = _error;
    if (error != null) {
      return RefreshIndicator(
        onRefresh: _loadFeeds,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.5,
              child: _EmptyState(
                message: '${l10n.failedToLoadContent}\n$error',
                actionLabel: l10n.retry,
                onAction: () => unawaited(_loadFeeds()),
              ),
            ),
          ],
        ),
      );
    }

    if (_loading && _popular.isEmpty && _latest.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_popular.isEmpty && _latest.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFeeds,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.5,
              child: _EmptyState(
                message: l10n.mstreamNothingFound,
                actionLabel: l10n.retry,
                onAction: () => unawaited(_loadFeeds()),
              ),
            ),
          ],
        ),
      );
    }

    final popularItems = [for (final m in _popular) _toItem(m)];
    final latestItems = [for (final m in _latest) _toItem(m)];
    return RefreshIndicator(
      onRefresh: _loadFeeds,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (popularItems.isNotEmpty)
            SliverToBoxAdapter(
              child: ExploreCarousel(
                movies: popularItems.take(7).toList(),
                httpHeaders: _imageHeaders,
                onTap: (item) {
                  final match = _popular.where(
                    (m) => (m.url ?? '') == item.url,
                  );
                  if (match.isNotEmpty) _openMedia(match.first);
                },
              ),
            ),
          if (popularItems.isNotEmpty)
            SliverToBoxAdapter(
              child: MediaHorizontalList(
                title: l10n.mstreamPopular,
                mediaList: popularItems,
                category: ViewAllCategory.providerContent,
                showViewAll: true,
                heroTagPrefix: 'mstream',
                httpHeaders: _imageHeaders,
                onTap: (item) {
                  final match = _popular.where(
                    (m) => (m.url ?? '') == item.url,
                  );
                  if (match.isNotEmpty) _openMedia(match.first);
                },
                onViewAll: () => _openAll(
                  l10n.mstreamPopular,
                  MStreamFeed.popular,
                ),
              ),
            ),
          if (latestItems.isNotEmpty)
            SliverToBoxAdapter(
              child: MediaHorizontalList(
                title: l10n.mstreamLatest,
                mediaList: latestItems,
                category: ViewAllCategory.providerContent,
                showViewAll: true,
                heroTagPrefix: 'mstream',
                httpHeaders: _imageHeaders,
                onTap: (item) {
                  final match = _latest.where(
                    (m) => (m.url ?? '') == item.url,
                  );
                  if (match.isNotEmpty) _openMedia(match.first);
                },
                onViewAll: () => _openAll(
                  l10n.mstreamLatest,
                  MStreamFeed.latest,
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: LayoutConstants.shellBottomContentPadding(context),
            ),
          ),
        ],
      ),
    );
  }

  List<Source> _enabledSources(
    List<Source> sources,
    MultiProviderBridgeState s,
  ) {
    return sources
        .where((source) => !s.isDisabled(source.uniqueId))
        .toList(growable: false);
  }

  Source _selectedSource(List<Source> enabled) {
    final bridge = ref.read(multiProviderBridgeProvider.notifier);
    bool usable(Source s) => bridge.methodsFor(s) != null;

    // Remember the user's pick across restarts, but only while its extension
    // is actually reachable — a dead remembered/first source used to
    // dead-end the whole screen ("first is not working").
    final wantedId = _source?.uniqueId ??
        ref.read(multiProviderBridgeProvider).lastSourceId;
    if (wantedId != null) {
      for (final source in enabled) {
        if (source.uniqueId == wantedId && usable(source)) return source;
      }
    }
    // Fall back to the first source whose extension resolves.
    for (final source in enabled) {
      if (usable(source)) return source;
    }
    // Nothing is resolvable yet (backend still starting) - keep the old
    // behaviour so the retry state explains the failure.
    return enabled.first;
  }

  void _showSourceSelector(List<Source> enabled, List<Source> all) {
    final selected = _source;
    if (selected == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => _SourceSelectorDialog(
        sources: enabled,
        activeId: selected.uniqueId,
        onSelected: _selectSource,
      ),
    );
  }
}

/// Home's search experience, scoped to the active extension: the same
/// delegate-driven search UI, results paginated in the same poster grid.
class _SourceSearchDelegate extends SearchDelegate<void> {
  _SourceSearchDelegate({
    required this.methods,
    required this.source,
    required this.hint,
  });

  final SourceMethods methods;
  final Source source;
  final String hint;

  @override
  String? get searchFieldLabel => hint;

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context);

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return MStreamFeedGrid(
      key: ValueKey('search_${source.uniqueId}_$query'),
      methods: methods,
      source: source,
      feed: MStreamFeed.search,
      query: query,
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return buildResults(context);
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
