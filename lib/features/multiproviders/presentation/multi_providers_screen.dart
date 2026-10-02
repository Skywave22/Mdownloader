import 'dart:async';

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:skystream/l10n/generated/app_localizations.dart';

import '../../../core/network/http_defaults.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/layout_constants.dart';
import '../../mstream/widgets/bridge_credit.dart';
import '../data/multiprovider_bridge.dart';

/// The extension systems a repository can belong to. They are product names, so
/// every locale shows them as written; keeping them as data also keeps them out
/// of the hard-coded-string ratchet, which is there to catch prose.
const List<({String id, String name})> _backends = [
  (id: 'aniyomi', name: 'Aniyomi'),
  (id: 'cloudstream', name: 'CloudStream'),
  (id: 'mangayomi', name: 'Mangayomi'),
  (id: 'sora', name: 'Sora'),
  (id: 'legado', name: 'Legado'),
];

/// Manages the AnymeX extension runtime bridge: the Runtime Host download,
/// the repositories sources come from, and installing/removing those sources.
///
/// Installed sources can be toggled off without uninstalling them, and the
/// Available tab installs either one at a time or all of them in sequence.
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
          IconButton(
            tooltip: l10n.installAll,
            icon: const Icon(Icons.download_for_offline_rounded),
            onPressed: state.isUsable ? () => _installAll() : null,
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
    final added = await showDialog<_NewRepository>(
      context: context,
      builder: (_) => const _AddRepositoryDialog(),
    );
    if (added == null || !mounted) return;

    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(multiProviderBridgeProvider.notifier);
    // Legado sources are novels; pasting a Legado link while on another tab
    // used to be a silent no-op - route it to the right type instead.
    final type = added.backend == 'legado' ? ItemType.novel : _type;
    // Immediate, visible feedback: the fetch can take a while on slow links
    // and "nothing happens" is what a silent wait feels like. The timeout
    // keeps a dead URL from hanging forever.
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.addingRepository), duration: const Duration(seconds: 60)),
    );
    try {
      await controller
          .addRepo(added.url, type, added.backend)
          .timeout(const Duration(seconds: 30));
      await controller
          .refresh()
          .timeout(const Duration(seconds: 60));
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.repositoryAdded(added.url))),
      );
    } on TimeoutException {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failedToAddRepository('timeout'))),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failedToAddRepository('$e'))),
      );
    }
  }

  /// Installs every still-uninstalled source of the current type, one at a
  /// time, with a progress sheet that can cancel the run midway.
  Future<void> _installAll() async {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.read(availableSourcesProvider(_type));
    final installedAsync = ref.read(installedSourcesProvider(_type));
    final available = async.value ?? const <Source>[];
    final installedIds = <String>{
      for (final s in installedAsync.value ?? const <Source>[]) s.uniqueId,
    };
    final queue = [
      for (final s in available)
        if (!installedIds.contains(s.uniqueId)) s,
    ];
    if (queue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.multiProvidersNoAvailable)),
      );
      return;
    }

    final progress = ValueNotifier<(int, int)>((0, queue.length));
    var cancelled = false;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _InstallProgressDialog(
          progress: progress,
          onCancel: () {
            cancelled = true;
            // showDialog pushes on the root navigator; pop the same one.
            Navigator.of(context, rootNavigator: true).pop();
          },
        ),
      ),
    );

    final controller = ref.read(multiProviderBridgeProvider.notifier);
    final succeeded = await controller.installAll(
      queue,
      onProgress: (done, total) => progress.value = (done, total),
      isCancelled: () => cancelled,
    );
    if (!mounted) return;
    if (!cancelled) {
      // The dialog closes only when the queue was not cancelled: a cancel
      // pops it from inside the button handler above.
      Navigator.of(context, rootNavigator: true).pop();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.installAllDone(succeeded))),
    );
  }
}

/// What the add-repository dialog hands back.
typedef _NewRepository = ({String url, String backend});

/// Asks for a repository address and which extension system it belongs to.
///
/// A widget of its own so that the controller is owned by a `State`: the dialog
/// is still mounted for its exit transition after `await showDialog` returns,
/// and a controller disposed by the caller at that point is disposed under a
/// live `TextField` (the lifetime bug that crashed the iOS build).
class _AddRepositoryDialog extends StatefulWidget {
  const _AddRepositoryDialog();

  @override
  State<_AddRepositoryDialog> createState() => _AddRepositoryDialogState();
}

class _AddRepositoryDialogState extends State<_AddRepositoryDialog> {
  final TextEditingController _url = TextEditingController();
  String _backend = _backends.first.id;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    Navigator.of(context).pop<_NewRepository>((url: url, backend: _backend));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.addRepository),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _url,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.multiProvidersRepositoryUrl,
              hintText: 'https://…/index.json',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: LayoutConstants.spacingMd),
          DropdownButtonFormField<String>(
            initialValue: _backend,
            decoration: InputDecoration(labelText: l10n.multiProvidersBackend),
            items: [
              for (final backend in _backends)
                DropdownMenuItem(value: backend.id, child: Text(backend.name)),
            ],
            onChanged: (v) => setState(() => _backend = v ?? _backend),
          ),
          const SizedBox(height: LayoutConstants.spacingMd),
          const BridgeCredit(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.add)),
      ],
    );
  }
}

/// Modal progress for the "install all" queue: how far along it is and a way
/// to stop it without losing what already installed.
class _InstallProgressDialog extends StatelessWidget {
  const _InstallProgressDialog({required this.progress, required this.onCancel});

  final ValueNotifier<(int, int)> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.installAll),
      content: ValueListenableBuilder<(int, int)>(
        valueListenable: progress,
        builder: (context, value, _) {
          final (done, total) = value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
              ),
              const SizedBox(height: LayoutConstants.spacingMd),
              Text(l10n.sourceAttempt(done.clamp(1, total), total)),
            ],
          );
        },
      ),
      actions: [
        TextButton(onPressed: onCancel, child: Text(l10n.cancel)),
      ],
    );
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
                  child: Text(switch (state.stage) {
                    MultiProviderStage.error => l10n.retry,
                    MultiProviderStage.ready => l10n.update,
                    _ => l10n.install,
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceList extends ConsumerStatefulWidget {
  const _SourceList({required this.type, required this.installed});

  final ItemType type;
  final bool installed;

  @override
  ConsumerState<_SourceList> createState() => _SourceListState();
}

class _SourceListState extends ConsumerState<_SourceList> {
  final TextEditingController _filter = TextEditingController();

  /// Selected backend chip: 'all' or a manager id (cloudstream, aniyomi...).
  String _backend = 'all';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bridgeState = ref.watch(multiProviderBridgeProvider);
    final async = widget.installed
        ? ref.watch(installedSourcesProvider(widget.type))
        : ref.watch(availableSourcesProvider(widget.type));
    // The Available tab hides what is already installed: the same extension
    // listed twice - once with a trash can, once with a download button - is
    // the sort of thing people report as "install is broken".
    final installedIds = ref
            .watch(installedSourcesProvider(widget.type))
            .value
            ?.map((s) => s.uniqueId)
            .toSet() ??
        const <String>{};

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LayoutConstants.spacingMd,
            LayoutConstants.spacingSm,
            LayoutConstants.spacingMd,
            0,
          ),
          child: TextField(
            controller: _filter,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l10n.multiProvidersFilterHint,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _filter.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _filter.clear();
                        setState(() {});
                      },
                    ),
              isDense: true,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(50),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        // Backend filter: "these are CloudStream, these are Aniyomi...".
        SizedBox(
          height: 42,
          child: Builder(
            builder: (context) {
              final ids = <String>{
                for (final s in async.value ?? const <Source>[])
                  if ((s.managerId ?? '').isNotEmpty) s.managerId!,
              };
              final sortedIds = ids.toList()..sort();
              final chips = <String>['all', ...sortedIds];
              return ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutConstants.spacingMd,
                  vertical: 4,
                ),
                children: [
                  for (final id in chips)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          id == 'all' ? l10n.all : managerLabelOf(id),
                        ),
                        selected: _backend == id,
                        onSelected: (_) => setState(() => _backend = id),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(LayoutConstants.spacingLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$e', textAlign: TextAlign.center),
                    const SizedBox(height: LayoutConstants.spacingMd),
                    FilledButton.tonal(
                      onPressed: () {
                        ref.invalidate(installedSourcesProvider);
                        ref.invalidate(availableSourcesProvider);
                      },
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            ),
            data: (sources) {
              final installed = widget.installed
                  ? sources
                  : [
                      for (final s in sources)
                        if (!installedIds.contains(s.uniqueId)) s,
                    ];
              final needle = _filter.text.trim().toLowerCase();
              bool matches(Source s) {
                if (_backend != 'all' && s.managerId != _backend) return false;
                if (needle.isEmpty) return true;
                return (s.name ?? '').toLowerCase().contains(needle) ||
                    (s.author ?? '').toLowerCase().contains(needle) ||
                    (s.lang ?? '').toLowerCase().contains(needle) ||
                    (s.managerId ?? '').toLowerCase().contains(needle);
              }

              final visible = [for (final s in installed) if (matches(s)) s];
              if (visible.isEmpty) {
                return Center(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(LayoutConstants.spacingLg),
                    child: Text(
                      needle.isEmpty
                          ? (widget.installed
                              ? l10n.multiProvidersNoInstalled
                              : l10n.multiProvidersNoAvailable)
                          : l10n.mstreamNothingFound,
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (widget.installed) {
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final source = visible[i];
                    return _SourceCard(
                      source: source,
                      installed: widget.installed,
                      disabled: bridgeState.isDisabled(source.uniqueId),
                    );
                  },
                );
              }
              // Available: grouped by developer ("dev") - one expandable
              // group per author with an Install-all button, and each
              // extension inside keeps its own one-by-one install button.
              final groups = <String, List<Source>>{};
              for (final s in visible) {
                groups.putIfAbsent(devNameOf(s), () => <Source>[]).add(s);
              }
              final entries = groups.entries.toList()
                ..sort((a, b) =>
                    a.key.toLowerCase().compareTo(b.key.toLowerCase()));
              return ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final entry = entries[i];
                  return _AuthorGroup(
                    author: entry.key,
                    sources: entry.value,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One extension row: rounded card with the icon, name, a metadata chip row
/// and the action buttons — the same visual language as the rest of the app.
class _SourceCard extends ConsumerWidget {
  const _SourceCard({
    required this.source,
    required this.installed,
    required this.disabled,
  });

  final Source source;
  final bool installed;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(multiProviderBridgeProvider.notifier);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LayoutConstants.spacingMd,
        vertical: 4,
      ),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (!installed) controller.install(source);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _SourceIcon(
                  iconUrl: source.iconUrl,
                  baseUrl: source.baseUrl,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              source.name ?? l10n.unknown,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (source.hasUpdate ?? false) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: Text(
                                l10n.update,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if ((source.lang ?? '').isNotEmpty)
                            _chip(context, source.lang!.toUpperCase()),
                          _chip(context, 'v${source.version ?? '?'}'),
                          if ((source.managerId ?? '').isNotEmpty)
                            _chip(context, source.managerId!),
                          if (disabled) _chip(context, l10n.disabled),
                        ],
                      ),
                    ],
                  ),
                ),
                if (installed)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Keep the source installed but out of MStream and its
                      // search until it is switched back on.
                      Tooltip(
                        message: disabled ? l10n.enable : l10n.disable,
                        child: Switch(
                          value: !disabled,
                          onChanged: (enabled) =>
                              controller.setSourceEnabled(source, enabled),
                        ),
                      ),
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
                else
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(l10n.install),
                    onPressed: () => controller.install(source),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// A source's icon, fetched like a poster (browser UA, cached) because plenty
/// of repository CDNs refuse the bare Dart client's requests. Relative icon
/// paths resolve against the source's base URL, same as MStream covers.
class _SourceIcon extends StatelessWidget {
  const _SourceIcon({required this.iconUrl, this.baseUrl});

  final String? iconUrl;
  final String? baseUrl;

  @override
  Widget build(BuildContext context) {
    final url = ImageUtils.resolveRemoteUrl(
      iconUrl ?? '',
      baseUrl: baseUrl ?? '',
    );
    if (url.isEmpty) return const Icon(Icons.extension_rounded);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 44,
        height: 44,
        httpHeaders: const {'User-Agent': kDefaultBrowserUserAgent},
        errorWidget: (_, _, _) => const Icon(Icons.extension_rounded),
      ),
    );
  }
}

/// Display name for a backend manager id ('-desktop' variants fold into
/// their mobile name).
String managerLabelOf(String id) {
  final base = id.replaceFirst('-desktop', '');
  for (final backend in _backends) {
    if (backend.id == base) return backend.name;
  }
  switch (base) {
    case 'kotatsu':
      return 'Kotatsu';
    case 'legado':
      return 'Legado';
  }
  return base;
}

/// The "dev" behind an extension: its declared author, or the repo owner
/// path segment when the manifest does not declare one.
String devNameOf(Source source) {
  final author = source.author?.trim();
  if (author != null && author.isNotEmpty) return author;
  final segments = Uri.tryParse(source.repo ?? '')
          ?.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList() ??
      const <String>[];
  if (segments.isNotEmpty) return segments.first;
  return source.repo?.isNotEmpty == true ? source.repo! : '—';
}

/// One developer's extensions: an expandable group with an Install-all
/// button in the header and the usual per-extension cards inside.
class _AuthorGroup extends ConsumerStatefulWidget {
  const _AuthorGroup({required this.author, required this.sources});

  final String author;
  final List<Source> sources;

  @override
  ConsumerState<_AuthorGroup> createState() => _AuthorGroupState();
}

class _AuthorGroupState extends ConsumerState<_AuthorGroup> {
  bool _expanded = true;
  bool _installing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bridgeState = ref.watch(multiProviderBridgeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LayoutConstants.spacingMd,
        4,
        LayoutConstants.spacingMd,
        4,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutConstants.spacingMd,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.author,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${widget.sources.length}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _installing ? null : _installAll,
                      icon: _installing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded, size: 18),
                      label: Text(l10n.installAll),
                    ),
                    const SizedBox(width: 4),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
            ),
            if (_expanded)
              for (final source in widget.sources)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: _SourceCard(
                    source: source,
                    installed: false,
                    disabled: bridgeState.isDisabled(source.uniqueId),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _installAll() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _installing = true);
    try {
      final succeeded = await ref
          .read(multiProviderBridgeProvider.notifier)
          .installAll(widget.sources);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.installAllDone(succeeded))),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failedToAddRepository('$e'))),
      );
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }
}
