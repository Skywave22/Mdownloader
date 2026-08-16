import 'package:flutter/material.dart';
import '../models/media.dart';
import 'details_page.dart';

/// Shared poster card used in home rows and search results.
class PosterCard extends StatelessWidget {
  final MediaItem item;
  const PosterCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final url = item.posterUrl();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DetailsPage(item: item)),
      ),
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: url.isEmpty
                    ? Container(color: Colors.white12, child: const Icon(Icons.movie))
                    : Image.network(url, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => Container(color: Colors.white12, child: const Icon(Icons.movie))),
              ),
            ),
            const SizedBox(height: 6),
            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            if (item.year != null)
              Text('${item.year} · ${item.mediaType == 'movie' ? 'Movie' : 'Series'}', style: TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

/// Horizontal row of posters.
class PosterRow extends StatelessWidget {
  final String title;
  final List<MediaItem> items;
  const PosterRow({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          height: 205,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => PosterCard(item: items[i]),
          ),
        ),
      ],
    );
  }
}
