import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../downloader/download_manager.dart';
import '../downloader/segmented_downloader.dart';
import '../services/locator.dart';
import 'widgets.dart';
import 'player_page.dart';
import 'settings_page.dart';

class DownloadsPage extends StatefulWidget {
  final bool ready;
  const DownloadsPage({super.key, required this.ready});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  @override
  void initState() {
    super.initState();
    downloadManager.addListener(_onChange);
  }

  @override
  void dispose() {
    downloadManager.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(
            tooltip: 'Download settings',
            icon: const Icon(Icons.folder_rounded, color: AppColors.textMid),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: !widget.ready
          ? const LoadingView()
          : downloadManager.tasks.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                  itemCount: downloadManager.tasks.length,
                  itemBuilder: (_, i) => _TaskTile(task: downloadManager.tasks[i]),
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.download_rounded, size: 36, color: AppColors.textLow),
          ),
          const SizedBox(height: 16),
          const Text('No downloads yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textHi)),
          const SizedBox(height: 6),
          const Text('Search a title, then pick a download link.',
              style: TextStyle(color: AppColors.textMid, fontSize: 13)),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final DownloadTask task;
  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: task,
      builder: (context, _) {
        final pct = task.totalBytes > 0 ? (task.downloadedBytes / task.totalBytes).clamp(0.0, 1.0) : 0.0;
        final active = task.status == DStatus.running || task.status == DStatus.merging;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border),
          ),
          child: Row(
            children: [
              _statusIcon(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textHi)),
                    const SizedBox(height: 6),
                    if (active) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: pct, minHeight: 5, backgroundColor: AppColors.surface2, color: AppColors.accent2),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(_statusLine(task), style: const TextStyle(fontSize: 12, color: AppColors.textMid)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _trailing(context),
            ],
          ),
        );
      },
    );
  }

  Widget _statusIcon() {
    final IconData icon;
    final Color color;
    switch (task.status) {
      case DStatus.completed:
        icon = Icons.check_circle_rounded;
        color = AppColors.ok;
        break;
      case DStatus.running:
      case DStatus.merging:
        icon = Icons.sync_rounded;
        color = AppColors.accent2;
        break;
      case DStatus.error:
        icon = Icons.error_rounded;
        color = AppColors.danger;
        break;
      case DStatus.paused:
        icon = Icons.pause_circle_rounded;
        color = AppColors.textLow;
        break;
      default:
        icon = Icons.schedule_rounded;
        color = AppColors.textLow;
    }
    return Icon(icon, color: color, size: 34);
  }

  String _statusLine(DownloadTask t) {
    switch (t.status) {
      case DStatus.running:
        final kb = (t.bytesPerSec / 1024).toStringAsFixed(0);
        return '${_mb(t.downloadedBytes)} / ${_mb(t.totalBytes)} MB · $kb KB/s';
      case DStatus.merging:
        return 'Merging parts…';
      case DStatus.completed:
        return 'Completed · ${_mb(t.totalBytes)} MB';
      case DStatus.paused:
        return 'Paused · ${_mb(t.downloadedBytes)} / ${_mb(t.totalBytes)} MB';
      case DStatus.error:
        return 'Error — tap to retry';
      case DStatus.cancelled:
        return 'Cancelled';
      case DStatus.idle:
        return 'Queued';
    }
  }

  Widget _trailing(BuildContext context) {
    switch (task.status) {
      case DStatus.running:
      case DStatus.merging:
        return IconButton(icon: const Icon(Icons.pause_rounded, color: AppColors.textHi), onPressed: task.pause);
      case DStatus.paused:
      case DStatus.idle:
      case DStatus.error:
      case DStatus.cancelled:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.play_arrow_rounded, color: AppColors.ok), onPressed: () => downloadManager.retry(task)),
            IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger), onPressed: () => downloadManager.remove(task)),
          ],
        );
      case DStatus.completed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.play_circle_outline_rounded, color: AppColors.accent2), onPressed: () => _open(context)),
            IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger), onPressed: () => downloadManager.remove(task)),
          ],
        );
    }
  }

  Future<void> _open(BuildContext context) async {
    final f = task.file;
    if (task.status == DStatus.completed && f != null && f.existsSync()) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerPage(file: File(f.path))));
    }
  }

  String _mb(num bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
