import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/download.dart';
import '../models/media.dart';
import '../plugins/plugin_manager.dart';
import '../services/locator.dart';
import 'widgets.dart';

class DetailsPage extends StatefulWidget {
  final MediaItem item;
  const DetailsPage({super.key, required this.item});

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  late Future<MediaItem> _future;

  @override
  void initState() {
    super.initState();
    _future = tmdb.details(widget.item);
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
              body: snap.hasError ? ErrorView(message: '${snap.error}', onRetry: () => setState(() => _future = tmdb.details(widget.item))) : const LoadingView(),
            );
          }
          final item = snap.data!;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 230,
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
                      _actions(item),
                      const SizedBox(height: 20),
                      if (item.overview.isNotEmpty) ...[
                        const Text('Overview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textHi)),
                        const SizedBox(height: 8),
                        Text(item.overview, style: const TextStyle(fontSize: 14, height: 1.55, color: AppColors.textMid)),
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
          Container(color: AppColors.surface2),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, AppColors.bg.withValues(alpha: 0.92)],
              stops: const [0.35, 1],
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
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 16, offset: const Offset(0, 8))],
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
                  _metaPill(item.mediaType == 'movie' ? 'Movie' : 'Series'),
                  if (item.runtime != null) _metaPill('${item.runtime} min'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metaPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMid)),
    );
  }

  Widget _actions(MediaItem item) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            icon: const Icon(Icons.download_rounded),
            label: const Text('Find downloads'),
            onPressed: () => _resolveAndShow(item, null, null),
          ),
        ),
      ],
    );
  }

  Widget _tvSeasons(MediaItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final season in item.seasons)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
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
                subtitle: Text('${season.episodes.length} episodes', style: const TextStyle(color: AppColors.textLow, fontSize: 12)),
                children: [
                  for (final ep in season.episodes)
                    ListTile(
                      dense: true,
                      title: Text('E${ep.episodeNumber} · ${ep.name}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, color: AppColors.textMid)),
                      trailing: IconButton(
                        icon: const Icon(Icons.download_outlined, color: AppColors.accent2),
                        onPressed: () => _resolveAndShow(item, ep.seasonNumber, ep.episodeNumber),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _resolveAndShow(MediaItem item, int? season, int? episode) async {
    final pm = plugins;
    if (pm == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Plugin engine not available on this device.'),
      ));
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
    try {
      final List<PluginStreamResult> results =
          await pm.resolveStreams(item, season: season, episode: episode);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No downloads found. Enable more plugins in the Plugins tab.'),
        ));
        return;
      }
      _showResults(results, item, season, episode);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  void _showResults(List<PluginStreamResult> results, MediaItem item, int? season, int? episode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Row(
                children: [
                  Text('Available downloads',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textHi)),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in results)
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: AppColors.gradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                      ),
                      title: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textHi)),
                      subtitle: Text(r.pluginName, style: const TextStyle(color: AppColors.textLow, fontSize: 12)),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        final epName = season != null ? '.S$season.E$episode' : '';
                        final labelPart = r.label.split(' · ').last.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
                        final ext = r.kind == DownloadKind.hls ? '.ts' : '.mp4';
                        final name = '${item.title}$epName.$labelPart$ext'.replaceAll(' ', '.');
                        await downloadManager.enqueue(name: name, url: r.url, kind: r.kind, headers: r.headers);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Added to downloads.')),
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
