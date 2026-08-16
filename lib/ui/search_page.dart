import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/media.dart';
import '../services/locator.dart';
import 'widgets.dart';
import 'details_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  List<MediaItem>? _results;
  String _error = '';
  bool _loading = false;

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final r = await tmdb.searchMulti(q.trim());
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _results = [];
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: const InputDecoration(
                hintText: 'Search movies & series…',
                prefixIcon: Icon(Icons.search_rounded),
                suffixIcon: Icon(Icons.arrow_forward_rounded),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error.isNotEmpty) return ErrorView(message: _error, onRetry: () => _search(_controller.text));
    final r = _results;
    if (r == null) {
      return const Center(
        child: Text('Search for a movie or series by title.',
            style: TextStyle(color: AppColors.textLow)),
      );
    }
    if (r.isEmpty) return const Center(child: Text('No results.', style: TextStyle(color: AppColors.textLow)));
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.52,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: r.length,
      itemBuilder: (_, i) => _ResultCard(item: r[i]),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final MediaItem item;
  const _ResultCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final url = item.posterUrl();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailsPage(item: item))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: url.isEmpty
                    ? Container(color: AppColors.surface2, child: const Icon(Icons.movie, color: AppColors.textLow))
                    : Image.network(url, fit: BoxFit.cover, width: double.infinity,
                        errorBuilder: (_, __, ___) => Container(color: AppColors.surface2, child: const Icon(Icons.movie, color: AppColors.textLow))),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textHi)),
          if (item.year != null)
            Text('${item.year}', style: const TextStyle(fontSize: 11, color: AppColors.textLow)),
        ],
      ),
    );
  }
}
