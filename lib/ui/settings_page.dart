import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../services/locator.dart';

/// App settings: download location, connection count, storage, about.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _dir;

  @override
  void initState() {
    super.initState();
    _loadDir();
    AppSettings.instance.addListener(_onSettings);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDir() async {
    final d = await AppSettings.instance.resolveDownloadDir();
    if (mounted) setState(() => _dir = d.path);
  }

  Future<void> _chooseFolder() async {
    try {
      final initial = _dir;
      final picked = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose download folder',
        initialDirectory: (initial != null && Directory(initial).existsSync()) ? initial : null,
      );
      if (picked == null || picked.isEmpty) return;
      if (picked.startsWith('content://')) {
        _toast('On Android the system folder picker cannot be used directly. Using the default Downloads folder.');
        return;
      }
      await downloadManager.setSaveDirectory(picked);
      if (mounted) setState(() => _dir = picked);
      _toast('Downloads will be saved to:\n$picked');
    } catch (e) {
      _toast('Could not open folder picker: $e');
    }
  }

  Future<void> _resetDir() async {
    await AppSettings.instance.setDownloadDir(null);
    await downloadManager.setSaveDirectory((await AppSettings.defaultDownloadDir()).path);
    await _loadDir();
    _toast('Reset to the default folder.');
  }

  Future<void> _openFolder() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      if (Platform.isWindows) {
        await Process.start('explorer', [dir]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [dir]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [dir]);
      }
    } catch (_) {
      _toast('Folder: $dir');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showLink(String title, String url, String body) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: const TextStyle(color: AppColors.textHi, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body, style: const TextStyle(color: AppColors.textMid, height: 1.4)),
            const SizedBox(height: 12),
            SelectableText(url, style: const TextStyle(color: AppColors.accent2, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.of(ctx).pop();
              _toast('Link copied.');
            },
            child: const Text('Copy link'),
          ),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SectionHeader(title: 'Storage'),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.folder_rounded, color: AppColors.accent2, size: 20),
                    SizedBox(width: 8),
                    Text('Download location',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textHi)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _dir ?? 'Loading…',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textMid),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GradButton(label: 'Choose folder', icon: Icons.drive_folder_upload_rounded, onPressed: _chooseFolder),
                    ),
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: _openFolder,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open'),
                    ),
                    TextButton(onPressed: _resetDir, child: const Text('Reset')),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Downloading'),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed_rounded, color: AppColors.accent2, size: 20),
                    const SizedBox(width: 8),
                    const Text('Parallel connections',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textHi)),
                    const Spacer(),
                    Text('${AppSettings.instance.maxWorkers}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent2)),
                  ],
                ),
                const SizedBox(height: 6),
                Slider(
                  value: AppSettings.instance.maxWorkers.toDouble(),
                  min: 2,
                  max: 16,
                  divisions: 14,
                  activeColor: AppColors.accent,
                  inactiveColor: AppColors.surface3,
                  onChanged: (v) => AppSettings.instance.setMaxWorkers(v.round()),
                ),
                const Text('More connections = faster downloads, but some servers throttle.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textLow)),
              ],
            ),
          ),
          const SectionHeader(title: 'Manage downloads'),
          GlassCard(
            child: Column(
              children: [
                _SettingRow(
                  icon: Icons.cleaning_services_rounded,
                  label: 'Clear completed',
                  onTap: () => downloadManager.clearCompleted(),
                ),
                const Divider(height: 1, color: AppColors.border),
                _SettingRow(
                  icon: Icons.delete_sweep_rounded,
                  label: 'Remove all downloads',
                  onTap: () async {
                    for (final t in List.of(downloadManager.tasks)) {
                      await downloadManager.remove(t);
                    }
                  },
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'About'),
          GlassCard(
            child: Column(
              children: [
                _SettingRow(
                  icon: Icons.info_rounded,
                  label: 'Version',
                  value: AppConfig.appVersion,
                ),
                const Divider(height: 1, color: AppColors.border),
                _SettingRow(
                  icon: Icons.shield_rounded,
                  label: 'Security policy',
                  value: 'SECURITY.md',
                  onTap: () => _showLink('Security policy', AppConfig.repoUrl, 'Report vulnerabilities via the SECURITY.md file in the repository.'),
                ),
                const Divider(height: 1, color: AppColors.border),
                _SettingRow(
                  icon: Icons.code_rounded,
                  label: 'Source code & releases',
                  value: 'GitHub',
                  onTap: () => _showLink('GitHub', AppConfig.repoUrl, 'Download the latest APK and Windows builds from the releases page.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'MDownloader · movies & series, instantly.',
              style: TextStyle(color: AppColors.textLow, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  const _SettingRow({required this.icon, required this.label, this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textMid, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textHi)),
            ),
            if (value != null)
              Text(value!, style: const TextStyle(color: AppColors.textLow, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}
