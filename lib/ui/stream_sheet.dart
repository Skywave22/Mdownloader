import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/download.dart';
import '../plugins/plugin_manager.dart';
import '../services/locator.dart';

/// Sorts resolved streams best-first: higher resolution MP4 first, HLS last.
List<PluginStreamResult> sortStreams(List<PluginStreamResult> in_) {
  final list = List<PluginStreamResult>.of(in_);
  int score(PluginStreamResult s) {
    final label = s.label.toLowerCase();
    int res = 0;
    for (final m in RegExp(r'(\d{3,4})p').allMatches(label)) {
      final v = int.tryParse(m.group(1) ?? '');
      if (v != null && v > res) res = v;
    }
    if (label.contains('720')) res = 720;
    if (label.contains('1080')) res = 1080;
    if (label.contains('480')) res = res < 480 ? 480 : res;
    if (label.contains('360')) res = res < 360 ? 360 : res;
    return res;
  }

  list.sort((a, b) {
    final sa = score(a);
    final sb = score(b);
    if (sa != sb) return sb.compareTo(sa);
    // direct (MP4) before HLS at equal resolution
    final ka = a.kind == DownloadKind.direct ? 0 : 1;
    final kb = b.kind == DownloadKind.direct ? 0 : 1;
    return ka.compareTo(kb);
  });
  return list;
}

/// Shared bottom sheet: pick a resolved stream and download it immediately.
Future<void> showStreamsSheet(
  BuildContext context, {
  required List<PluginStreamResult> results,
  required String title,
  int? season,
  int? episode,
}) {
  final streams = sortStreams(results);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textHi)),
                      Text('${streams.length} instant link${streams.length == 1 ? '' : 's'} found',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textMid)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: streams.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _StreamTile(
                  result: streams[i],
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final epName = (season != null && episode != null) ? '.S$season.E$episode' : '';
                    final labelPart = streams[i].label.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
                    final ext = streams[i].kind == DownloadKind.hls ? '.ts' : '.mp4';
                    final name = '$title$epName.$labelPart$ext'.replaceAll(' ', '.');
                    await downloadManager.enqueue(
                      name: name,
                      url: streams[i].url,
                      kind: streams[i].kind,
                      headers: streams[i].headers,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Downloading "${streams[i].label}"…')),
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StreamTile extends StatelessWidget {
  final PluginStreamResult result;
  final VoidCallback onTap;
  const _StreamTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isHls = result.kind == DownloadKind.hls;
    final color = isHls ? AppColors.accent3 : AppColors.accent2;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.55)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(isHls ? Icons.motion_photos_on_rounded : Icons.play_arrow_rounded,
                  color: Colors.white, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.label,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textHi, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(result.pluginName,
                      style: const TextStyle(color: AppColors.textLow, fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppColors.gradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.download_rounded, color: Colors.white, size: 17),
            ),
          ],
        ),
      ),
    );
  }
}
