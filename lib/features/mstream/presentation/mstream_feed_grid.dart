import 'dart:async';

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

import '../../../core/network/http_defaults.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../shared/widgets/multimedia_card.dart';
import '../../../shared/widgets/thumbnail_error_placeholder.dart';
import 'mstream_details_screen.dart';

/// Which feed a [MStreamFeedGrid] pages through.
enum MStreamFeed {
  /// The source's popular listing, falling back to its latest feed.
  popular,

  /// The source's latest-updates listing, falling back to its popular feed.
  latest,

  /// A search query against the source.
  search,
}

/// The paginated extension-content grid, in the same card style Home's grids
/// use. Powers the "View All" screens and the in-source search results.
class MStreamFeedGrid extends StatefulWidget {
  const MStreamFeedGrid({
    super.key,
    required this.methods,
    required this.source,
    required this.feed,
    this.query,
  });

  final SourceMethods methods;
  final Source source;
  final MStreamFeed feed;

  /// Only for [MStreamFeed.search].
  final String? query;

  @override
  State<MStreamFeedGrid> createState() => _MStreamFeedGridState();
}

class _MStreamFeedGridState extends State<MStreamFeedGrid> {
  final ScrollController _scrollController = ScrollController();
  final List<DMedia> _items = <DMedia>[];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasNextPage = false;
  int _page = 1;
  int _generation = 0;
  Object? _error;

  String get _referer => widget.source.baseUrl ?? '';

  Map<String, String> get _imageHeaders => {
        'User-Agent': kDefaultBrowserUserAgent,
        if (_referer.isNotEmpty) 'Referer': _referer,
      };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_fetch());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || _loadingMore || !_hasNextPage) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      unawaited(_fetch(append: true));
    }
  }

  Future<Pages> _request(int page) async {
    switch (widget.feed) {
      case MStreamFeed.search:
        return widget.methods.search(widget.query ?? '', page, const <dynamic>[]);
      case MStreamFeed.popular:
        try {
          return await widget.methods.getPopular(page);
        } catch (_) {
          return widget.methods.getLatestUpdates(page);
        }
      case MStreamFeed.latest:
        try {
          return await widget.methods.getLatestUpdates(page);
        } catch (_) {
          return widget.methods.getPopular(page);
        }
    }
  }

  Future<void> _fetch({bool append = false}) async {
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
      final pages = await _request(page);
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
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (append) {
          _hasNextPage = true;
        } else {
          _error = e;
        }
      });
    }
  }

  void _open(DMedia media) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MStreamDetailsScreen(
          media: media,
          methods: widget.methods,
          source: widget.source,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return _FeedEmptyState(
        message: l10n.errorPrefix('$error'),
        actionLabel: l10n.retry,
        onAction: () => unawaited(_fetch()),
      );
    }
    if (_items.isEmpty) {
      return _FeedEmptyState(
        message: l10n.mstreamNothingFound,
        actionLabel: l10n.retry,
        onAction: () => unawaited(_fetch()),
      );
    }

    final isDesktop = context.isDesktop;
    final maxExtent = isDesktop
        ? (MediaQuery.sizeOf(context).width > 1200 ? 240.0 : 200.0)
        : 150.0;
    final crossAxisCount =
        (MediaQuery.sizeOf(context).width / maxExtent).ceil();

    return RefreshIndicator(
      onRefresh: () => _fetch(),
      child: GridView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.55,
        ),
        itemCount: _items.length + (_hasNextPage ? crossAxisCount : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final media = _items[i];
          return MultimediaCard(
            imageUrl: ImageUtils.resolveRemoteUrl(
              media.cover ?? '',
              baseUrl: _referer,
            ),
            title: media.title ?? '',
            heroTag: 'mstream_poster_${media.url}',
            httpHeaders: _imageHeaders,
            onTap: () => _open(media),
          );
        },
      ),
    );
  }
}

/// Full-page "View All" over one feed, styled like the app's View All screen.
class MStreamAllScreen extends StatelessWidget {
  const MStreamAllScreen({
    super.key,
    required this.title,
    required this.methods,
    required this.source,
    required this.feed,
  });

  final String title;
  final SourceMethods methods;
  final Source source;
  final MStreamFeed feed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: MStreamFeedGrid(
        methods: methods,
        source: source,
        feed: feed,
      ),
    );
  }
}

class _FeedEmptyState extends StatelessWidget {
  const _FeedEmptyState({
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ThumbnailErrorPlaceholder(),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
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
