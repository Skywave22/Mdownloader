import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:skystream/l10n/generated/app_localizations.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/layout_constants.dart';
import '../data/multiprovider_bridge.dart';

/// The extension systems a repository can belong to. They are product names, so
/// every locale shows them as written; keeping them as data also keeps them out
/// of the hard-coded-string ratchet, which is there to catch prose.
const List<({String id, String name})> _backends = [
  (id: 'aniyomi', name: 'Aniyomi'),
  (id: 'cloudstream', name: 'CloudStream'),
  (id: 'mangayomi', name: 'Mangayomi'),
  (id: 'sora', name: 'Sora'),
];

/// Manages the AnymeX extension runtime bridge: the Runtime Host download,
/// the repositories sources come from, and installing/removing those sources.
///
/// Playback of what gets installed here lives in the MStream tab.
class MultiProvidersScreen extends ConsumerStatefulWidget {
  const MultiProvidersScreen({super.key});

  /// Title used by the screen and by its Settings entry.
  static const String title = 'MultiProviders';

  @override
  ConsumerState<MultiProvidersScreen> createState() =>
      _MultiProvidersScreenState();
}

class _MultiProvidersScreenState extends ConsumerState<MultiProvidersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  ItemType _type = ItemType.anime;

  @override
  void initState() {
    super.initState();
    // Lazy: the bridge opens a database and may load a JVM, so it is started
    // when this screen is first opened rather than at app launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(multiProviderBridgeProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(multiProviderBridgeProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              const SettingsRoute().go(context);
            }
          },
        ),
        title: const Text(MultiProvidersScreen.title),
        actions: [
          IconButton(
            tooltip: l10n.addRepository,
            icon: const Icon(Icons.add_link_rounded),
            onPressed: state.isUsable ? _showAddRepoDialog : null,
          ),
          IconButton(
            tooltip: l10n.refresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: state.isUsable
                ? () => ref.read(multiProviderBridgeProvider.notifier).refresh()
                : null,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [Tab(text: l10n.installed), Tab(text: l10n.available)],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              _RuntimeCard(state: state),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutConstants.spacingMd,
                ),
                child: SegmentedButton<ItemType>(
                  segments: [
                    ButtonSegment(
                      value: ItemType.anime,
                      label: Text(l10n.anime),
                    ),
                    ButtonSegment(
                      value: ItemType.manga,
                      label: Text(l10n.manga),
                    ),
                    ButtonSegment(
                      value: ItemType.novel,
                      label: Text(l10n.novel),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
              ),
              const SizedBox(height: LayoutConstants.spacingSm),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _SourceList(type: _type, installed: true),
                    _SourceList(type: _type, installed: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddRepoDialog() async {
    final urlController = TextEditingController();
    var managerId = _backends.first.id;

    final added = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(l10n.addRepository),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.multiProvidersRepositoryUrl,
                    hintText: 'https://…/index.json',
                  ),
                ),
                const SizedBox(height: LayoutConstants.spacingMd),
                DropdownButtonFormField<String>(
                  initialValue: managerId,
                  decoration: InputDecoration(
                    labelText: l10n.multiProvidersBackend,
                  ),
                  items: [
                    for (final backend in _backends)
                      DropdownMenuItem(
                        value: backend.id,
                        child: Text(backend.name),
                      ),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => managerId = v ?? managerId),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.add),
              ),
            ],
          ),
        );
      },
    );

    final url = urlController.text.trim();
    urlController.dispose();
    if (added != true || url.isEmpty) return;

    await ref
        .read(multiProviderBridgeProvider.notifier)
        .addRepo(url, _type, managerId);
    await ref.read(multiProviderBridgeProvider.notifier).refresh();
  }
}

/// Status of the Runtime Host, and the button that installs or updates it.
class _RuntimeCard extends ConsumerWidget {
  const _RuntimeCard({required this.state});

  final MultiProviderBridgeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    // `idle` lasts one frame: the screen starts the bridge as soon as it is
    // built, so it reads as "starting" rather than getting a word of its own.
    final (IconData icon, String text) = switch (state.stage) {
      MultiProviderStage.idle => (
          Icons.hourglass_empty_rounded,
          l10n.multiProvidersStageStarting,
        ),
      MultiProviderStage.initializing => (
          Icons.downloading_rounded,
          l10n.multiProvidersStageStarting,
        ),
      MultiProviderStage.installing => (
          Icons.downloading_rounded,
          l10n.multiProvidersStageInstalling,
        ),
      MultiProviderStage.partial => (
          Icons.warning_amber_rounded,
          l10n.multiProvidersStageNoHost,
        ),
      MultiProviderStage.ready => (
          Icons.check_circle_rounded,
          l10n.multiProvidersStageReady,
        ),
      MultiProviderStage.unsupported => (
          Icons.block_rounded,
          l10n.multiProvidersStageUnsupported,
        ),
      MultiProviderStage.error => (
          Icons.error_rounded,
          state.message ?? l10n.generalError,
        ),
    };

    return Padding(
      padding: const EdgeInsets.all(LayoutConstants.spacingMd),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(LayoutConstants.spacingMd),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: LayoutConstants.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.multiProvidersRuntimeBridge,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(text, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (state.isBusy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (state.stage != MultiProviderStage.unsupported)
                FilledButton.tonal(
                  onPressed: () => ref
                      .read(multiProviderBridgeProvider.notifier)
                      .setupRuntime(force: state.hasRuntimeHost),
                  child: Text(state.hasRuntimeHost ? l10n.update : l10n.install),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceList extends ConsumerWidget {
  const _SourceList({required this.type, required this.installed});

  final ItemType type;
  final bool installed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = installed
        ? ref.watch(installedSourcesProvider(type))
        : ref.watch(availableSourcesProvider(type));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (sources) {
        if (sources.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(LayoutConstants.spacingLg),
              child: Text(
                installed
                    ? l10n.multiProvidersNoInstalled
                    : l10n.multiProvidersNoAvailable,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: EdgeInsets.only(
            bottom: LayoutConstants.shellBottomContentPadding(context),
          ),
          itemCount: sources.length,
          itemBuilder: (context, i) {
            final source = sources[i];
            final controller = ref.read(multiProviderBridgeProvider.notifier);
            return ListTile(
              leading: (source.iconUrl ?? '').isEmpty
                  ? const Icon(Icons.extension_rounded)
                  : Image.network(
                      source.iconUrl!,
                      width: 32,
                      height: 32,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.extension_rounded),
                    ),
              title: Text(source.name ?? l10n.unknown),
              subtitle: Text(
                [
                  source.lang?.toUpperCase() ?? '',
                  'v${source.version ?? '?'}',
                  source.managerId ?? '',
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
              trailing: installed
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (source.hasUpdate ?? false)
                          IconButton(
                            tooltip: l10n.update,
                            icon: const Icon(Icons.upgrade_rounded),
                            onPressed: () => controller.update(source),
                          ),
                        IconButton(
                          tooltip: l10n.uninstall,
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => controller.uninstall(source),
                        ),
                      ],
                    )
                  : IconButton(
                      tooltip: l10n.install,
                      icon: const Icon(Icons.download_rounded),
                      onPressed: () => controller.install(source),
                    ),
            );
          },
        );
      },
    );
  }
}
