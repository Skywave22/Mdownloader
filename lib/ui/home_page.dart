import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/media.dart';
import '../services/locator.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  final VoidCallback? onSearchTap;
  const HomePage({super.key, this.onSearchTap});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final results = await Future.wait([
      tmdb.trending(),
      tmdb.popularMovies(),
      tmdb.popularTv(),
    ]);
    return _HomeData(trending: results[0], movies: results[1], tv: results[2]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_HomeData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorView(message: 'Could not load the catalog.\n${snap.error}', onRetry: () => setState(() => _future = _load()));
          }
          if (!snap.hasData) return const LoadingView();
          final d = snap.data!;
          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () async => setState(() => _future = _load()),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _hero(context)),
                SliverToBoxAdapter(child: PosterRow(title: 'Trending This Week', items: d.trending)),
                SliverToBoxAdapter(child: PosterRow(title: 'Popular Movies', items: d.movies)),
                SliverToBoxAdapter(child: PosterRow(title: 'Popular Series', items: d.tv)),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _hero(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 6),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withValues(alpha: 0.22),
            AppColors.surface.withValues(alpha: 0.4),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppColors.gradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.download_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MDownloader',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.textHi)),
                  Text('Movies & series, ready to download',
                      style: TextStyle(fontSize: 12, color: AppColors.textMid)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: widget.onSearchTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search_rounded, color: AppColors.textLow),
                  SizedBox(width: 10),
                  Text('Search any movie or series…', style: TextStyle(color: AppColors.textLow, fontSize: 14.5)),
                  Spacer(),
                  GradPill(text: 'TMDB'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeData {
  final List<MediaItem> trending;
  final List<MediaItem> movies;
  final List<MediaItem> tv;
  const _HomeData({required this.trending, required this.movies, required this.tv});
}
