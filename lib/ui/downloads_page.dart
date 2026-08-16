import 'dart:io';
import 'package:flutter/material.dart';
import '../downloader/download_manager.dart';
import '../downloader/segmented_downloader.dart';
import '../services/locator.dart';
import 'player_page.dart';

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
      appBar: AppBar(title: const Text('Downloads')),
      body: !widget.ready
          ? const Center(child: CircularProgressIndicator())
          : downloadManager.tasks.isEmpty
              ? const Center(child: Text('No downloads yet.\nSearch a title and pick a download link.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: downloadManager.tasks.length,
                  itemBuilder: (_, i) => _TaskTile(task: downloadManager.tasks[i]),
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
        final pct = task.totalBytes > 0 ? task.downloadedBytes / task.totalBytes : 0.0;
        return Card(
          child: ListTile(
            title: Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.status == DStatus.running || task.status == DStatus.merging) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: pct.clamp(0.0, 1.0)),
                  const SizedBox(height: 4),
                  Text(_statusLine(task)),
                ] else
                  Text(_statusLine(task)),
              ],
            ),
            trailing: _trailing(context),
            onTap: () => _open(context),
          ),
        );
      },
    );
  }

  String _statusLine(DownloadTask t) {
    switch (t.status) {
      case DStatus.running:
        final kbPerSec = (t.bytesPerSec / 1024).toStringAsFixed(0);
        return '${_mb(t.downloadedBytes)} / ${_mb(t.totalBytes)} MB · $kbPerSec KB/s';
      case DStatus.merging:
        return 'Merging parts…';
      case DStatus.completed:
        return 'Completed · ${_mb(t.totalBytes)} MB';
      case DStatus.paused:
        return 'Paused · ${_mb(t.downloadedBytes)} / ${_mb(t.totalBytes)} MB';
      case DStatus.error:
        return 'Error: ${t.error ?? 'unknown'}';
      case DStatus.cancelled:
        return 'Cancelled';
      case DStatus.idle:
        return 'Queued';
    }
  }

  Widget? _trailing(BuildContext context) {
    switch (task.status) {
      case DStatus.running:
      case DStatus.merging:
        return IconButton(icon: const Icon(Icons.pause), onPressed: task.pause);
      case DStatus.paused:
      case DStatus.idle:
      case DStatus.error:
      case DStatus.cancelled:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.play_arrow), onPressed: () => task.start(downloadManager.saveDir)),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => downloadManager.remove(task)),
          ],
        );
      case DStatus.completed:
        return IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => downloadManager.remove(task));
    }
  }

  Future<void> _open(BuildContext context) async {
    if (task.status == DStatus.completed && task.file != null && task.file!.existsSync()) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerPage(file: File(task.file!.path)),
      ));
    }
  }

  String _mb(num bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
