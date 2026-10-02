import 'dart:async';
import 'dart:io';

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart' show Get, Inst;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/storage/settings_repository.dart';

/// Where the bridge is in its lifecycle.
///
/// The Runtime Host (an APK on Android, a JRE + JAR on desktop) is a separate
/// download, so "the plugin is wired up" and "Aniyomi/CloudStream can run" are
/// two different states and the UI has to be able to tell them apart.
enum MultiProviderStage {
  /// Nothing has been attempted yet.
  idle,

  /// `AnymeXExtensionBridge.init` / `checkAndInitialize` in flight.
  initializing,

  /// The Runtime Host is being downloaded or installed.
  installing,

  /// Mangayomi + Sora are usable, the Runtime Host is not installed, so
  /// Aniyomi and CloudStream sources are unavailable.
  partial,

  /// Everything, including the Runtime Host, is live.
  ready,

  /// iOS: the Runtime Host cannot run at all here.
  unsupported,

  /// Initialization or the download failed; [MultiProviderBridgeState.message]
  /// carries the exception text.
  error,
}

class MultiProviderBridgeState {
  const MultiProviderBridgeState({
    this.stage = MultiProviderStage.idle,
    this.message,
    this.disabledSourceIds = const <String>{},
    this.lastSourceId,
  });

  final MultiProviderStage stage;

  /// The exception text when [stage] is [MultiProviderStage.error]. Every other
  /// stage is worded by the screen from its localizations, so no prose lives
  /// here: this layer cannot reach a `BuildContext`, and English hard-coded in
  /// it would show up untranslated in every locale.
  final String? message;

  /// `Source.uniqueId`s the user toggled off. Installed but hidden from
  /// MStream and its search; MultiProviders shows them greyed out.
  final Set<String> disabledSourceIds;

  /// The `Source.uniqueId` the user last browsed in MStream, so the tab reopens
  /// on the same source.
  final String? lastSourceId;

  bool get isBusy =>
      stage == MultiProviderStage.initializing ||
      stage == MultiProviderStage.installing;

  /// Extension managers are registered — sources can be listed and played.
  bool get isUsable =>
      stage == MultiProviderStage.ready || stage == MultiProviderStage.partial;

  /// The Runtime Host is loaded, so Aniyomi and CloudStream are available too.
  bool get hasRuntimeHost => stage == MultiProviderStage.ready;

  bool isDisabled(String sourceId) => disabledSourceIds.contains(sourceId);

  MultiProviderBridgeState copyWith({
    MultiProviderStage? stage,
    String? message,
    Set<String>? disabledSourceIds,
    String? lastSourceId,
  }) => MultiProviderBridgeState(
    stage: stage ?? this.stage,
    message: message ?? this.message,
    disabledSourceIds: disabledSourceIds ?? this.disabledSourceIds,
    lastSourceId: lastSourceId ?? this.lastSourceId,
  );
}

/// Owns the AnymeX extension runtime bridge for the whole app.
///
/// One instance, created lazily the first time MultiProviders or MStream is
/// opened: `AnymeXExtensionBridge.init` opens an Isar database and the Runtime
/// Host loads a whole JVM, so neither belongs on the startup path of a tab the
/// viewer may never visit.
class MultiProviderBridgeController extends Notifier<MultiProviderBridgeState> {
  Future<void>? _inFlight;

  @override
  MultiProviderBridgeState build() {
    // The toggles and the remembered source live in the settings box; read
    // them once up front and carry them in the state so every UI that filters
    // or restores a source sees one snapshot of them.
    final settings = ref.read(settingsRepositoryProvider);
    final disabled = settings.getMstreamDisabledSources().toSet();
    final lastSourceId = settings.getMstreamLastSourceId();
    if (!AnymeXRuntimeBridge.isSupportedPlatform) {
      // iOS has no Runtime Host, and the JS-only backends still work, so this
      // is reported rather than treated as a failure.
      return MultiProviderBridgeState(
        stage: MultiProviderStage.unsupported,
        disabledSourceIds: disabled,
        lastSourceId: lastSourceId,
      );
    }
    return MultiProviderBridgeState(
      disabledSourceIds: disabled,
      lastSourceId: lastSourceId,
    );
  }

  /// Resolves the directories the bridge stores extensions and its database
  /// in. Kept under the app's own support directory so uninstalling the app
  /// takes the sources with it.
  static Future<Directory?> _getDirectory({
    String? subPath,
    bool useCustomPath = false,
    bool useSystemPath = false,
  }) async {
    final base = useCustomPath && !useSystemPath
        ? await getApplicationDocumentsDirectory()
        : await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'MultiProviders'));
    final dir = subPath == null ? root : Directory(p.join(root.path, subPath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Initializes the plugin and picks up an already-downloaded Runtime Host.
  /// Safe to call repeatedly: concurrent callers share one future and a
  /// completed initialization is a no-op.
  Future<void> initialize() {
    if (state.stage == MultiProviderStage.unsupported) return Future.value();
    if (state.isUsable) return Future.value();
    return _inFlight ??= _initialize().whenComplete(() => _inFlight = null);
  }

  Future<void> _initialize() async {
    state = state.copyWith(stage: MultiProviderStage.initializing);
    try {
      await AnymeXExtensionBridge.init(
        projectName: 'SkyStream',
        getDirectory: _getDirectory,
      );
      // Registers Sora/Mangayomi/Legado immediately and picks up the Runtime
      // Host if it was downloaded on a previous run.
      await AnymeXRuntimeBridge.checkAndInitialize();
      await _manager?.onRuntimeBridgeInitialization();
      await _publishStage();
      // Self-heal: a cold-start race can leave a backend publishing an empty
      // installed list; re-read everything once initialization has settled.
      await _manager?.refreshInstalled();
    } catch (e, st) {
      talker.error('MultiProviders: bridge initialization failed', e, st);
      state = state.copyWith(
        stage: MultiProviderStage.error,
        message: e.toString(),
      );
    }
  }

  /// Downloads (or re-downloads, with [force]) the Runtime Host and registers
  /// the Aniyomi and CloudStream backends it unlocks.
  Future<void> setupRuntime({bool force = false}) async {
    if (state.stage == MultiProviderStage.unsupported) return;
    await initialize();
    if (state.stage == MultiProviderStage.error) return;

    state = state.copyWith(stage: MultiProviderStage.installing);
    try {
      await AnymeXRuntimeBridge.setupRuntime(force: force);
      await _manager?.onRuntimeBridgeInitialization(force: force);
      await _publishStage();
    } catch (e, st) {
      talker.error('MultiProviders: runtime host setup failed', e, st);
      state = state.copyWith(
        stage: MultiProviderStage.error,
        message: e.toString(),
      );
    }
  }

  Future<void> _publishStage() async {
    final loaded = await AnymeXRuntimeBridge.isLoaded();
    state = state.copyWith(
      stage: loaded ? MultiProviderStage.ready : MultiProviderStage.partial,
    );
  }

  /// The aggregated manager, or null before [initialize] has succeeded.
  ExtensionManager? get _manager =>
      Get.isRegistered<ExtensionManager>() ? Get.find<ExtensionManager>() : null;

  Future<void> addRepo(String url, ItemType type, String managerId) async =>
      _manager?.addRepo(url.trim(), type, managerId);

  Future<void> refresh({bool refreshAvailableSource = true}) async =>
      _manager?.refreshExtensions(
        refreshAvailableSource: refreshAvailableSource,
      );

  /// Re-reads installed sources from every backend's store without touching
  /// the repositories. Heals a transient empty publish (see the vendored
  /// bridge's `refreshInstalled`); safe to call on every screen open.
  Future<void> refreshInstalled() async => _manager?.refreshInstalled();

  Future<void> install(Source source) async =>
      _withManager(source, (m) => m.installSource(source));

  Future<void> uninstall(Source source) async =>
      _withManager(source, (m) => m.uninstallSource(source));

  Future<void> update(Source source) async =>
      _withManager(source, (m) => m.updateSource(source));

  Future<void> _withManager(
    Source source,
    Future<void> Function(Extension manager) action,
  ) async {
    final backend = _manager?.findById(source.managerId ?? '');
    if (backend == null) {
      talker.warning(
        'MultiProviders: no backend registered for "${source.managerId}"',
      );
      return;
    }
    await action(backend);
    await _manager?.refreshExtensions(refreshAvailableSource: false);
  }

  /// Unified call surface for one installed source — search, details, videos.
  SourceMethods? methodsFor(Source source) {
    final backend = _manager?.findById(source.managerId ?? '');
    return backend?.createSourceMethods(source);
  }

  /// Marks [source] enabled or disabled without uninstalling it.
  ///
  /// A disabled source stays installed and updated, but MStream and its search
  /// stop listing it. Persisted so the toggle survives a restart.
  Future<void> setSourceEnabled(Source source, bool enabled) async {
    final disabled = Set<String>.from(state.disabledSourceIds);
    if (enabled) {
      disabled.remove(source.uniqueId);
    } else {
      disabled.add(source.uniqueId);
    }
    await ref
        .read(settingsRepositoryProvider)
        .setMstreamDisabledSources(disabled.toList(growable: false));
    state = state.copyWith(disabledSourceIds: disabled);
  }

  /// Remembers which source MStream is browsing, so the tab reopens on it.
  Future<void> setLastSourceId(String sourceId) async {
    await ref.read(settingsRepositoryProvider).setMstreamLastSourceId(sourceId);
    state = state.copyWith(lastSourceId: sourceId);
  }

  /// Installs [sources] one at a time and returns how many succeeded.
  ///
  /// Sequential on purpose: each install is a network fetch plus a parse and
  /// a database write, and firing a repository's whole catalogue at the
  /// runtime at once overwhelms phones (and the desktop sidecar) more than it
  /// saves time. [onProgress] is called after each source with (done, total);
  /// [isCancelled] is polled before each install so the caller can stop the
  /// queue midway and keep what already landed.
  Future<int> installAll(
    Iterable<Source> sources, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final queue = List<Source>.of(sources);
    var succeeded = 0;
    var next = 0;
    var done = 0;

    // Three installs at a time: installs are network + host-parse bound, and a
    // strict serial queue made "Install All" crawl on slower links. One bad
    // extension must not abort the run: log it and keep going.
    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() ?? false) return;
        final i = next++;
        if (i >= queue.length) return;
        try {
          await install(queue[i]);
          succeeded++;
        } catch (e, st) {
          talker.error(
            'MultiProviders: install failed for ${queue[i].name}',
            e,
            st,
          );
        }
        done++;
        onProgress?.call(done, queue.length);
      }
    }

    await Future.wait([worker(), worker(), worker()]);
    return succeeded;
  }
}

final multiProviderBridgeProvider =
    NotifierProvider<MultiProviderBridgeController, MultiProviderBridgeState>(
  MultiProviderBridgeController.new,
);

/// Bridges one of the manager's GetX observables into a Riverpod stream so the
/// rest of the app never has to reach for GetX.
///
/// [rx] is an `RxList<Source>`/`Rx<List<Source>>`; both expose `value` and
/// `listen`, and typing it loosely keeps this working across GetX's two
/// reactive list shapes.
Stream<List<Source>> _rxStream(dynamic rx) {
  if (rx == null) return const Stream<List<Source>>.empty();
  late final StreamController<List<Source>> controller;
  StreamSubscription<List<Source>>? sub;
  controller = StreamController<List<Source>>(
    onListen: () {
      controller.add(List<Source>.from(rx.value as List));
      sub = (rx.listen((dynamic v) {
        controller.add(List<Source>.from(v as List));
      }) as StreamSubscription<List<Source>>);
    },
    onCancel: () async => sub?.cancel(),
  );
  return controller.stream;
}

dynamic _aggregated(
  MultiProviderBridgeController c,
  ItemType type, {
  required bool installed,
}) {
  final manager = c._manager;
  if (manager == null) return null;
  switch (type) {
    case ItemType.anime:
      return installed
          ? manager.installedAnimeExtensions
          : manager.availableAnimeExtensions;
    case ItemType.manga:
      return installed
          ? manager.installedMangaExtensions
          : manager.availableMangaExtensions;
    case ItemType.novel:
      return installed
          ? manager.installedNovelExtensions
          : manager.availableNovelExtensions;
  }
}

/// Installed sources of [type], live.
final installedSourcesProvider =
    StreamProvider.family<List<Source>, ItemType>((ref, type) {
  final controller = ref.watch(multiProviderBridgeProvider.notifier);
  // Re-subscribes once the managers exist.
  ref.watch(multiProviderBridgeProvider);
  return _rxStream(_aggregated(controller, type, installed: true));
});

/// Sources offered by the configured repositories, live.
final availableSourcesProvider =
    StreamProvider.family<List<Source>, ItemType>((ref, type) {
  final controller = ref.watch(multiProviderBridgeProvider.notifier);
  ref.watch(multiProviderBridgeProvider);
  return _rxStream(_aggregated(controller, type, installed: false));
});
