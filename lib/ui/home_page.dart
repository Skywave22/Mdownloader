import 'package:flutter/material.dart';
import '../models/media.dart';
import '../services/locator.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
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
      appBar: AppBar(title: const Text('MDownloader')),
      body: FutureBuilder<_HomeData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off, size: 40, color: Colors.white38),
                const SizedBox(height: 12),
                Text('Could not load catalog.\n${snap.error}', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => setState(() => _future = _load()), child: const Text('Retry')),
              ]),
            ));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final d = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              children: [
                PosterRow(title: 'Trending This Week', items: d.trending),
                PosterRow(title: 'Popular Movies', items: d.movies),
                PosterRow(title: 'Popular Series', items: d.tv),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
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
