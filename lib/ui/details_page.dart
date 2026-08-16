import 'package:flutter/material.dart';
import '../models/media.dart';
import '../services/locator.dart';
import '../services/scraper/scraper.dart';

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
      appBar: AppBar(title: Text(widget.item.title)),
      body: FutureBuilder<MediaItem>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            return const Center(child: CircularProgressIndicator());
          }
          final item = snap.data!;
          return ListView(
            children: [
              _header(item),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.overview),
                    const SizedBox(height: 16),
                    if (item.mediaType == 'movie') _movieActions(item),
                    if (item.mediaType == 'tv') _tvSeasons(item),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(MediaItem item) {
    final bg = item.backdropUrl();
    return SizedBox(
      height: 240,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bg.isNotEmpty)
            Image.network(bg, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: Colors.white10))
          else
            Container(color: Colors.white10),
          Container(color: Colors.black.withValues(alpha: 0.45)),
          Positioned(
            left: 16,
            bottom: 16,
            child: Row(
              children: [
                if (item.posterUrl().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(item.posterUrl('w185'), width: 90, height: 135, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 90, height: 135)),
                  ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 260,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(
                        '${item.mediaType == 'movie' ? 'Movie' : 'Series'}'
                        '${item.year != null ? ' · ${item.year}' : ''}'
                        '${item.voteAverage > 0 ? ' · ★ ${item.voteAverage.toStringAsFixed(1)}' : ''}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _movieActions(MediaItem item) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FilledButton.icon(
        icon: const Icon(Icons.download),
        label: const Text('Find download links'),
        onPressed: () => _resolveAndShow(item, null, null),
      ),
      const SizedBox(height: 8),
      const Text('Sources are scraped from multiple sites when you press the button.',
          style: TextStyle(fontSize: 12, color: Colors.white54)),
    ]);
  }

  Widget _tvSeasons(MediaItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final season in item.seasons)
          ExpansionTile(
            title: Text(season.name),
            subtitle: Text('${season.episodes.length} episodes'),
            children: [
              for (final ep in season.episodes)
                ListTile(
                  dense: true,
                  title: Text('E${ep.episodeNumber} · ${ep.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () => _resolveAndShow(item, ep.seasonNumber, ep.episodeNumber),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _resolveAndShow(MediaItem item, int? season, int? episode) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final List<ScrapeResult> results;
      if (season == null) {
        results = await scraperRegistry.resolveMovie(item);
      } else {
        results = await scraperRegistry.resolveEpisode(item, season, episode!);
      }
      if (!mounted) return;
      Navigator.of(context).pop(); // close spinner
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No downloadable sources found for this title yet.')),
        );
        return;
      }
      _showResults(results, item, season, episode);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scrape failed: $e')));
    }
  }

  void _showResults(List<ScrapeResult> results, MediaItem item, int? season, int? episode) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Available downloads', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            for (final r in results)
              ListTile(
                leading: const Icon(Icons.file_download),
                title: Text(r.label),
                subtitle: Text(r.source),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final epName = season != null ? '.S$season.E$episode' : '';
                  final ext = _extFor(r);
                  await downloadManager.enqueue(
                    name: '${item.title}$epName.${r.label.replaceAll(RegExp(r'[^0-9]'), '')}$ext'.replaceAll(' ', '.'),
                    url: r.url,
                    kind: r.kind,
                    headers: r.headers,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Added to downloads. Check the Downloads tab.')),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  String _extFor(ScrapeResult r) {
    if (r.kind == DownloadKind.hls) return '.ts';
    final u = r.url.split('?').first;
    final dot = u.lastIndexOf('.');
    if (dot > 0 && u.length - dot <= 5) return u.substring(dot);
    return '.mp4';
  }
}
