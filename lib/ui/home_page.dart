import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/media.dart';
import '../services/locator.dart';
import 'settings_page.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  final VoidCallback? onSearchTap;
  final VoidCallback? onDiscoverTap;
  const HomePage({super.key, this.onSearchTap, this.onDiscoverTap});

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
            return ErrorView(
                message: 'Could not load the catalog.\n${snap.error}',
                onRetry: () => setState(() => _future = _load()));
          }
          if (!snap.hasData) return const LoadingView();
          final d = snap.data!;
          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () async => setState(() => _future = _load()),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _hero(context, d.trending)),
                SliverToBoxAdapter(child: _hindiStrip()),
                SliverToBoxAdapter(child: PosterRow(title: 'Trending This Week', items: d.trending)),
                SliverToBoxAdapter(child: PosterRow(title: 'Popular Movies', items: d.movies)),
                SliverToBoxAdapter(child: PosterRow(title: 'Popular Series', items: d.tv)),
                const SliverToBoxAdapter(child: SizedBox(height: 36)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Cinematic hero header using the top trending backdrop.
  Widget _hero(BuildContext context, List<MediaItem> trending) {
    final featured = trending.isNotEmpty ? trending.first : null;
    final backdrop = featured?.backdropUrl() ?? '';
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 4),
      height: 240,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdrop.isNotEmpty)
            Image.network(backdrop, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: AppColors.surface2))
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
          // fade to background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.25),
                  AppColors.bg.withValues(alpha: 0.55),
                  AppColors.bg,
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
          // top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 10, 0),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: AppColors.gradient,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(color: AppColors.accent.withValues(alpha: 0.5), blurRadius: 12),
                      ],
                    ),
                    child: const Icon(Icons.download_rounded, color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: 10),
                  const Text('MDownloader',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          color: Colors.white)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    ),
                    icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 23),
                  ),
                ],
              ),
            ),
          ),
          // bottom-left title + CTA
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (featured != null)
                  Text(featured.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: Colors.white,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 10)])),
                const SizedBox(height: 4),
                const Text('Movies & series, ready to download — instantly.',
                    style: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1))),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: widget.onSearchTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.search_rounded, color: Colors.white),
                        SizedBox(width: 10),
                        Text('Search any movie or series…',
                            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14.5)),
                        Spacer(),
                        GradPill(text: 'TMDB'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One-tap jump into the Hindi-dubbed plugin catalogue.
  Widget _hindiStrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: GestureDetector(
        onTap: widget.onDiscoverTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.accent.withValues(alpha: 0.28),
                AppColors.accent2.withValues(alpha: 0.14),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: const [
              Icon(Icons.movie_filter_rounded, color: AppColors.accent2),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hindi Dubbed — instant links',
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textHi, fontSize: 14.5)),
                    Text('Goldmines · Ultra · Pen Movies · YouTube',
                        style: TextStyle(fontSize: 12, color: AppColors.textMid)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: AppColors.accent2),
            ],
          ),
        ),
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
