import 'dart:async';
import 'dart:io';

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart' show Get;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/logger/app_logger.dart';

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
  /// carries the reason.
  error,
}

class MultiProviderBridgeState {
  const MultiProviderBridgeState({
    this.stage = MultiProviderStage.idle,
    this.message,
  });

  final MultiProviderStage stage;
  final String? message;

  bool get isBusy =>
      stage == MultiProviderStage.initializing ||
      stage == MultiProviderStage.installing;

  /// Extension managers are registered — sources can be listed and played.
  bool get isUsable =>
      stage == MultiProviderStage.ready || stage == MultiProviderStage.partial;

  /// The Runtime Host is loaded, so Aniyomi and CloudStream are available too.
  bool get hasRuntimeHost => stage == MultiProviderStage.ready;

  MultiProviderBridgeState copyWith({
    MultiProviderStage? stage,
    String? message,
  }) =>
      MultiProviderBridgeState(
        stage: stage ?? this.stage,
        message: message,
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
    if (!AnymeXRuntimeBridge.isSupportedPlatform) {
      // iOS has no Runtime Host, and the JS-only backends still work, so this
      // is reported rather than treated as a failure.
      return const MultiProviderBridgeState(
        stage: MultiProviderStage.unsupported,
        message: 'Extension runtimes are not available on this platform.',
      );
    }
    return const MultiProviderBridgeState();
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
    state = const MultiProviderBridgeState(
      stage: MultiProviderStage.initializing,
    );
    try {
      await AnymeXExtensionBridge.init(
        projectName: 'SkyStream',
        getDirectory: _getDirectory,
      );
      // Registers Sora/Mangayomi/Legado immediately and picks up the Runtime
      // Host if it was downloaded on a previous run.
      await AnymeXRuntimeBridge.checkAndInitialize();
      await manager?.onRuntimeBridgeInitialization();
      await _publishStage();
    } catch (e, st) {
      talker.error('MultiProviders: bridge initialization failed', e, st);
      state = MultiProviderBridgeState(
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

    state = const MultiProviderBridgeState(stage: MultiProviderStage.installing);
    try {
      await AnymeXRuntimeBridge.setupRuntime(force: force);
      await manager?.onRuntimeBridgeInitialization(force: force);
      await _publishStage();
    } catch (e, st) {
      talker.error('MultiProviders: runtime host setup failed', e, st);
      state = MultiProviderBridgeState(
        stage: MultiProviderStage.error,
        message: e.toString(),
      );
    }
  }

  Future<void> _publishStage() async {
    final loaded = await AnymeXRuntimeBridge.isLoaded();
    state = MultiProviderBridgeState(
      stage: loaded ? MultiProviderStage.ready : MultiProviderStage.partial,
      message: loaded
          ? null
          : 'Runtime Host not installed — Aniyomi and CloudStream sources are '
              'unavailable until it is.',
    );
  }

  /// The aggregated manager, or null before [initialize] has succeeded.
  ExtensionManager? get manager =>
      Get.isRegistered<ExtensionManager>() ? Get.find<ExtensionManager>() : null;

  Future<void> addRepo(String url, ItemType type, String managerId) async =>
      manager?.addRepo(url.trim(), type, managerId);

  Future<void> refresh({bool refreshAvailableSource = true}) async =>
      manager?.refreshExtensions(
        refreshAvailableSource: refreshAvailableSource,
      );

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
    final backend = manager?.findById(source.managerId ?? '');
    if (backend == null) {
      talker.warning(
        'MultiProviders: no backend registered for "${source.managerId}"',
      );
      return;
    }
    await action(backend);
    await manager?.refreshExtensions(refreshAvailableSource: false);
  }

  /// Unified call surface for one installed source — search, details, videos.
  SourceMethods? methodsFor(Source source) {
    final backend = manager?.findById(source.managerId ?? '');
    return backend?.createSourceMethods(source);
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
  final manager = c.manager;
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
