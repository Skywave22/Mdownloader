import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/download.dart';
import '../models/media.dart';
import '../plugins/plugin_manager.dart';
import '../services/locator.dart';
import 'stream_sheet.dart';
import 'widgets.dart';

class DetailsPage extends StatefulWidget {
  final MediaItem item;
  const DetailsPage({super.key, required this.item});

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  late Future<MediaItem> _future;
  List<PluginStreamResult>? _streams;
  bool _resolving = false;
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    _future = tmdb.details(widget.item);
  }

  /// Resolves download links automatically as soon as the page is ready.
  void _maybeAutoResolve(MediaItem item) {
    if (_autoTried) return;
    _autoTried = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve(item, null, null));
  }

  Future<void> _resolve(MediaItem item, int? season, int? episode) async {
    final pm = plugins;
    if (pm == null) return;
    setState(() => _resolving = true);
    try {
      final results = await pm.resolveStreams(item, season: season, episode: episode);
      if (!mounted) return;
      setState(() {
        _streams = results;
        _resolving = false;
      });
    } catch (_) {
      if (mounted) setState(() => _resolving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<MediaItem>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return Scaffold(
              appBar: AppBar(title: Text(widget.item.title)),
              body: snap.hasError
                  ? ErrorView(message: '${snap.error}', onRetry: () => setState(() => _future = tmdb.details(widget.item)))
                  : const LoadingView(),
            );
          }
          final item = snap.data!;
          _maybeAutoResolve(item);
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 250,
                backgroundColor: AppColors.bg,
                foregroundColor: AppColors.textHi,
                flexibleSpace: FlexibleSpaceBar(
                  background: _backdrop(item),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _titleBlock(item),
                      const SizedBox(height: 16),
                      _sourcesSection(item),
                      const SizedBox(height: 20),
                      if (item.overview.isNotEmpty) ...[
                        const Text('Overview',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textHi)),
                        const SizedBox(height: 8),
                        Text(item.overview,
                            style: const TextStyle(fontSize: 14, height: 1.55, color: AppColors.textMid)),
                      ],
                      const SizedBox(height: 20),
                      if (item.mediaType == 'tv') _tvSeasons(item),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _backdrop(MediaItem item) {
    final bg = item.backdropUrl();
    return Stack(
      fit: StackFit.expand,
      children: [
        if (bg.isNotEmpty)
          Image.network(bg, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: AppColors.surface2))
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF17132B), Color(0xFF0B1B2B)],
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, AppColors.bg.withValues(alpha: 0.96)],
              stops: const [0.3, 1],
            ),
          ),
        ),
      ],
    );
  }

  Widget _titleBlock(MediaItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (item.posterUrl().isNotEmpty)
          Container(
            width: 92,
            height: 138,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 16, offset: const Offset(0, 8)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.network(item.posterUrl('w185'), fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: AppColors.surface2)),
            ),
          ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title,
                  style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.textHi)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (item.year != null) GradPill(text: '${item.year}'),
                  if (item.voteAverage > 0) GradPill(text: '★ ${item.voteAverage.toStringAsFixed(1)}'),
                  MetaPill(icon: item.mediaType == 'movie' ? Icons.movie_rounded : Icons.tv_rounded,
                      text: item.mediaType == 'movie' ? 'Movie' : 'Series'),
                  if (item.runtime != null) MetaPill(text: '${item.runtime} min', color: AppColors.amber),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The auto-resolving "instant downloads" section.
  Widget _sourcesSection(MediaItem item) {
    final streams = _streams;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Instant downloads',
          subtitle: 'Links are found automatically from your plugins.',
          trailing: IconButton(
            tooltip: 'Refresh',
            onPressed: _resolving ? null : () => _resolve(item, null, null),
            icon: const Icon(Icons.refresh_rounded, color: AppColors.accent2),
          ),
        ),
        if (_resolving && streams == null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Searching sources…', style: TextStyle(color: AppColors.textMid, fontSize: 13)),
              ],
            ),
          ),
        if (streams != null && streams.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Text('No instant links yet. Enable more plugins or refresh.',
                style: TextStyle(color: AppColors.textLow, fontSize: 13)),
          ),
        if (streams != null && streams.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [
                for (final s in sortStreams(streams).take(4)) _streamRow(item, s),
                const SizedBox(height: 8),
                GradButton(
                  label: 'Show all ${streams.length} links',
                  icon: Icons.playlist_play_rounded,
                  expanded: true,
                  onPressed: () => showStreamsSheet(context, results: streams, title: item.title),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _streamRow(MediaItem item, PluginStreamResult s) {
    final isHls = s.kind == DownloadKind.hls;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(isHls ? Icons.motion_photos_on_rounded : Icons.play_arrow_rounded, color: AppColors.accent2, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textHi, fontSize: 13.5)),
                Text(s.pluginName, style: const TextStyle(color: AppColors.textLow, fontSize: 11)),
              ],
            ),
          ),
          InkWell(
            onTap: () async {
              final labelPart = s.label.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
              final ext = s.kind == DownloadKind.hls ? '.ts' : '.mp4';
              final name = '${item.title}.$labelPart$ext'.replaceAll(' ', '.');
              await downloadManager.enqueue(name: name, url: s.url, kind: s.kind, headers: s.headers);
              _toast('Downloading "${s.label}"…');
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppColors.gradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.download_rounded, color: Colors.white, size: 17),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tvSeasons(MediaItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Episodes'),
        for (final season in item.seasons)
          Container(
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: AppColors.border),
              child: ExpansionTile(
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
                title: Text(season.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textHi)),
                subtitle: Text('${season.episodes.length} episodes',
                    style: const TextStyle(color: AppColors.textLow, fontSize: 12)),
                children: [
                  for (final ep in season.episodes)
                    ListTile(
                      dense: true,
                      title: Text('E${ep.episodeNumber} · ${ep.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, color: AppColors.textMid)),
                      trailing: IconButton(
                        icon: const Icon(Icons.download_outlined, color: AppColors.accent2),
                        onPressed: () => _resolve(item, ep.seasonNumber, ep.episodeNumber),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
