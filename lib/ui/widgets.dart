import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/media.dart';
import 'details_page.dart';

/// A poster card with soft shadow, border and a rating badge.
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
        width: 126,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      url.isEmpty
                          ? Container(color: AppColors.surface2, child: const Icon(Icons.movie, color: AppColors.textLow))
                          : Image.network(url, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: AppColors.surface2, child: const Icon(Icons.movie, color: AppColors.textLow))),
                      if (item.voteAverage > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '★ ${item.voteAverage.toStringAsFixed(1)}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFFFD166)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w600, color: AppColors.textHi)),
            const SizedBox(height: 2),
            Text(
              '${item.year ?? '—'} · ${item.mediaType == 'movie' ? 'Movie' : 'Series'}',
              style: const TextStyle(fontSize: 11, color: AppColors.textLow),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal poster rail with a section header.
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
        SectionHeader(title: title),
        SizedBox(
          height: 226,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => PosterCard(item: items[i]),
          ),
        ),
      ],
    );
  }
}

/// Loading placeholder.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
}

/// Error + retry placeholder.
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 44, color: AppColors.textLow),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMid)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
