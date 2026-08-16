import 'package:flutter/material.dart';
import '../models/media.dart';
import '../services/locator.dart';
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
    setState(() { _loading = true; _error = ''; });
    try {
      final r = await tmdb.searchMulti(q.trim());
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _results = []; });
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
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: false,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: const InputDecoration(hintText: 'Search movies & series…', border: InputBorder.none),
        ),
        actions: [
          IconButton(onPressed: _loading ? null : () => _search(_controller.text), icon: const Icon(Icons.search)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Text(_error))
              : _results == null
                  ? const Center(child: Text('Search for a movie or series by title.'))
                  : _results!.isEmpty
                      ? const Center(child: Text('No results.'))
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 160,
                            childAspectRatio: 0.55,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _results!.length,
                          itemBuilder: (_, i) => _ResultCard(item: _results![i]),
                        ),
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
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DetailsPage(item: item),
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: url.isEmpty
                  ? Container(color: Colors.white12, child: const Icon(Icons.movie))
                  : Image.network(url, fit: BoxFit.cover, width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(color: Colors.white12, child: const Icon(Icons.movie))),
            ),
          ),
          const SizedBox(height: 6),
          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
          if (item.year != null) Text('${item.year}', style: TextStyle(fontSize: 11, color: Colors.white54)),
        ],
      ),
    );
  }
}
