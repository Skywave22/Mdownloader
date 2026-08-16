import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../plugins/plugin_manager.dart';
import '../services/locator.dart';
import 'widgets.dart';

class PluginsPage extends StatefulWidget {
  final bool ready;
  const PluginsPage({super.key, required this.ready});

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  @override
  void initState() {
    super.initState();
    if (widget.ready) plugins?.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant PluginsPage old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready) plugins?.addListener(_onChange);
  }

  @override
  void dispose() {
    plugins?.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plugins')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        onPressed: _install,
        icon: const Icon(Icons.add),
        label: const Text('Install plugin'),
      ),
      body: !widget.ready
          ? const LoadingView()
          // plugins is non-null here because ready is true
          : plugins!.plugins.isEmpty
              ? const _EmptyPlugins()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                  itemCount: plugins!.plugins.length,
                  itemBuilder: (_, i) => _PluginCard(info: plugins!.plugins[i]),
                ),
    );
  }

  Future<void> _install() async {
    final ok = await plugins!.installFromPicker();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Plugin installed.' : 'Install failed. Make sure the file is a .zip or .sky with plugin.json + plugin.js.'),
    ));
  }
}

class _EmptyPlugins extends StatelessWidget {
  const _EmptyPlugins();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
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
              child: const Icon(Icons.extension_rounded, size: 36, color: AppColors.textLow),
            ),
            const SizedBox(height: 16),
            const Text('No plugins installed',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textHi)),
            const SizedBox(height: 8),
            const Text(
              'Plugins find download links for each site.\nInstall one, or write your own — see PLUGINS.md.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMid, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  final PluginInfo info;
  const _PluginCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final initial = info.name.isNotEmpty ? info.name[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: info.enabled ? AppColors.gradient : const LinearGradient(colors: [Color(0xFF2A3040), Color(0xFF2A3040)]),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(initial, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textHi)),
                const SizedBox(height: 3),
                Text('v${info.version} · ${info.packageName}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textLow)),
                if (info.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(info.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMid)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          Switch(
            value: info.enabled,
            activeTrackColor: AppColors.accent,
            onChanged: (v) => plugins!.setEnabled(info, v),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: const Text('Remove plugin?', style: TextStyle(color: AppColors.textHi)),
                    content: Text('Delete "${info.name}"?', style: const TextStyle(color: AppColors.textMid)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          plugins!.deletePlugin(info);
                        },
                        child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                      ),
                    ],
                  ),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
