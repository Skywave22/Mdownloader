import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../plugins/plugin_manager.dart';
import '../services/locator.dart';
import 'stream_sheet.dart';
import 'widgets.dart';

/// Browse content from installed site plugins (Hindi-dubbed sources, etc.).
class DiscoverPage extends StatefulWidget {
  final bool ready;
  const DiscoverPage({super.key, required this.ready});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _controller = TextEditingController();
  List<PluginSearchItem>? _results;
  bool _loading = false;
  String _error = '';
  String _activeQuery = '';

  static const _quick = [
    'Hindi dubbed full movie',
    'Hindi dubbed series episode',
    'South indian hindi dubbed',
    'New hindi dubbed movie 2026',
    'Bollywood full movie',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _enabledCount {
    final pm = plugins;
    if (pm == null) return 0;
    return pm.plugins.where((p) => p.enabled).length;
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;
    final pm = plugins;
    if (pm == null) {
      setState(() => _error = 'Plugin engine is still starting…');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
      _activeQuery = query;
    });
    try {
      final r = await pm.searchAll(query);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openItem(PluginSearchItem item) async {
    final pm = plugins;
    if (pm == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
    try {
      final streams = await pm.resolveUrl(item.pluginPackage, item.url);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (streams.isEmpty) {
        _toast('No playable links for this title.');
        return;
      }
      await showStreamsSheet(context, results: streams, title: item.title);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast('Failed to resolve links: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: const InputDecoration(
                hintText: 'Search Hindi-dubbed & more in your plugins…',
                prefixIcon: Icon(Icons.search_rounded),
                suffixIcon: Icon(Icons.arrow_forward_rounded),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              itemCount: _quick.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final q = _quick[i];
                final active = _activeQuery == q;
                return GestureDetector(
                  onTap: () {
                    _controller.text = q;
                    _search(q);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: active ? AppColors.gradient : null,
                      color: active ? null : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: active ? Colors.transparent : AppColors.border),
                    ),
                    child: Text(
                      q,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : AppColors.textMid,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (!widget.ready) return const LoadingView();
    if (_enabledCount == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'No plugins enabled.\nEnable Hindi-dubbed plugins in the Plugins tab.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMid, height: 1.5),
          ),
        ),
      );
    }
    if (_loading) return const LoadingView();
    if (_error.isNotEmpty) return ErrorView(message: _error, onRetry: () => _search(_controller.text));
    final r = _results;
    if (r == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'Pick a quick search or type a title.\nResults come straight from your installed plugins.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textLow, height: 1.5),
          ),
        ),
      );
    }
    if (r.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.search_off_rounded, size: 44, color: AppColors.textLow),
            SizedBox(height: 12),
            Text('No results. Try a different phrase.',
                style: TextStyle(color: AppColors.textMid)),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        childAspectRatio: 0.52,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: r.length,
      itemBuilder: (_, i) => _PluginResultCard(item: r[i], onTap: () => _openItem(r[i])),
    );
  }
}

class _PluginResultCard extends StatelessWidget {
  final PluginSearchItem item;
  final VoidCallback onTap;
  const _PluginResultCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final url = item.posterUrl;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 5))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    url.isEmpty
                        ? Container(color: AppColors.surface2, child: const Icon(Icons.play_circle_outline_rounded, color: AppColors.textLow, size: 34))
                        : Image.network(url, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: AppColors.surface2, child: const Icon(Icons.movie, color: AppColors.textLow))),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.accent2.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          item.pluginName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.accent2),
                        ),
                      ),
                    ),
                    const Positioned(
                      bottom: 8,
                      right: 8,
                      child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 26),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, height: 1.25, fontWeight: FontWeight.w600, color: AppColors.textHi)),
          const SizedBox(height: 2),
          const Text('Instant download', style: TextStyle(fontSize: 11, color: AppColors.textLow)),
        ],
      ),
    );
  }
}
