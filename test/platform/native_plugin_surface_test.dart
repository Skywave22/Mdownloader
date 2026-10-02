/// What native code every platform build registers, pinned.
///
/// A dependency is added once, in `pubspec.yaml`, usually for one platform —
/// but it is bought for all five, and the bill is paid at **registration**, not
/// at use. `generated_plugin_registrant` constructs every registered plugin at
/// startup, so "no Dart code calls this" does not stop a plugin doing whatever
/// it likes the moment the app launches. Nothing else in this repo records what
/// each platform is carrying.
///
/// That is the mechanism behind both of the worst bugs this project has
/// shipped, and neither was visible to the rest of the suite:
///
///   * `screen_brightness` was added for the mobile player's touch rail. It
///     silently bought a Windows plugin that drives DDC/CI — I²C over the
///     display cable — at its registrar and again on `WM_CLOSE`, for a feature
///     `vlc_player_controls.dart` returns early from on desktop. Users reported
///     SkyStream resetting their monitor's brightness.
///   * `flutter_inappwebview` was added for the Cloudflare bypass. It silently
///     bought a Windows plugin whose constructor builds a WinRT dispatcher
///     queue, a Graphics.Capture probe, a hardware D3D11 device and a
///     compositor before any Dart runs — none of which this app ever uses.
///
/// This test is the ledger. It does not judge; it makes a change to the native
/// surface **impossible to make silently**. When it fails, the diff names the
/// plugin, and someone decides — on purpose, in the pull request — rather than
/// finding out on release day on a platform they cannot build.
///
/// Editing the expected sets is a normal part of adding a dependency. What is
/// not normal is editing them without reading what the new plugin does at
/// registration on the platform you do not build.
///
/// This runs on any host: `flutter pub get` resolves the full five-platform
/// graph regardless of which machine it runs on, and `flutter test` runs
/// `pub get` first, so the manifest is always fresh.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Plugins that compile and register native code, per platform.
///
/// Dart-only plugins are deliberately excluded: they register nothing and cost
/// nothing at startup. `flutter_torrent_server` is the in-repo example — it
/// declares `dartPluginClass` with no `pluginClass` on desktop, so it appears
/// in no registrant at all.
const Map<String, Set<String>> _expected = <String, Set<String>>{
  'android': {
    'android_file_picker',
    // anymex_extension_runtime_bridge, for MultiProviders / MStream. Read before
    // adding: `onAttachedToEngine` creates six channels - anymeXBridge, and the
    // aniyomi-, cloudstream- and kotatsuExtensionBridge ones, a cloudstream
    // video-stream event channel and anymexLogger - and installs handlers. No
    // I/O, no class loading. The Runtime Host APK is only DexClassLoader'd when
    // Dart calls loadAnymeXRuntimeHost, from checkAndInitialize/setupRuntime,
    // which the MultiProviders screen triggers on first open - not at startup.
    'anymex_extension_runtime_bridge',
    'background_downloader',
    'connectivity_plus',
    // From the bridge. Registrar: a method channel and an event channel. The
    // package-install BroadcastReceiver is attached by `onListen`, i.e. only while
    // Dart is subscribed to the app-change stream, which the bridge never is - it
    // only calls isAppInstalled/uninstallApp. packages/device_apps, not upstream:
    // the published build script calls jcenter(), which Gradle 9 removed.
    'device_apps',
    'device_info_plus',
    'dynamic_color',
    'flutter_displaymode',
    // Read before adding, per this file's rule. `onAttachedToEngine` sets up a
    // method channel, an event channel and an `AudioManager` wrapper, and
    // reads or writes nothing. The one global side effect is in the stream
    // handler, not the registrar: while a listener is attached it points the
    // Activity's `volumeControlStream` at STREAM_MUSIC, so the hardware rocker
    // moves media volume rather than the ringer. `onCancel` puts it back to
    // USE_DEFAULT_STREAM_TYPE, and the player cancels on dispose, so it does
    // not outlive the screen the way screen_brightness_windows' write did.
    'flutter_volume_controller',
    // Transitive, from flutter_volume_controller: the first-party helper that
    // hands a plugin the Activity's lifecycle. Registers an observer and
    // nothing else.
    'flutter_plugin_android_lifecycle',
    'flutter_inappwebview_android',
    'flutter_js_ng',
    // QuickJS for the bridge's JavaScript backends. The registrar makes one
    // `flutter_qjs` channel that answers getPlatformVersion; the engine is
    // libqjs.so, loaded by name over FFI. packages/flutter_qjs exists so that
    // Linux, macOS and iOS do not carry it - see the notes on those sets.
    'flutter_qjs',
    'flutter_secure_storage',
    'flutter_torrent_server',
    // From the bridge. The registrar adds a method channel and an
    // ActivityResultListener and reads nothing; what it buys is in the merged
    // manifest: REQUEST_INSTALL_PACKAGES, and an unexported FileProvider
    // (`${applicationId}.installFileProvider.install`) whose path map spans the
    // whole filesystem root. The system installer is only ever handed a URI the
    // plugin minted for one APK. packages/install_plugin, Android only: upstream
    // also registers an iOS plugin whose one method opens an App Store URL.
    'install_plugin',
    'integration_test',
    // Isar's native database binaries. Registration is an empty
    // onAttachedToEngine; libisar loads when Dart opens a database, which the
    // bridge does on first use (AnymeXExtensionBridge.init -> Isar.open).
    'isar_community_flutter_libs',
    'jni',
    'jni_flutter',
    // FFI plugin (`ffiPlugin: true`): no registrar at all. The libtorrent engine
    // is loaded over FFI by TorrentStreamResolver when a torrent source plays.
    // Resolved from the bridge's own copy, which carries the Android and Linux
    // binaries and the `customLibraryPath` hook the hosted package lacks.
    'libtorrent_flutter',
    'open_file_android',
    'package_info_plus',
    'permission_handler_android',
    'screen_brightness_android',
    'share_plus',
    'shared_preferences_android',
    'sqflite_android',
    'url_launcher_android',
    'vlc_player',
    'wakelock_plus',
  },
  'ios': {
    // The bridge does not run on iOS at all (`isSupportedPlatform` is
    // `!Platform.isIOS`), so this and the two below ride along only because a
    // pub dependency cannot be made per-platform. Template channel only.
    'anymex_extension_runtime_bridge',
    'background_downloader',
    'connectivity_plus',
    'device_info_plus',
    'file_picker_darwin',
    'flutter_inappwebview_ios',
    'flutter_js_ng',
    'flutter_secure_storage_darwin',
    'flutter_torrent_server',
    'integration_test',
    // Empty `register`; `dummyMethodToEnforceBundling` exists so the linker keeps
    // libisar.
    'isar_community_flutter_libs',
    // FFI plugin; the Swift class is a no-op placeholder ("all communication
    // happens via Dart FFI"). `pod install` downloads the prebuilt static
    // xcframework from the libtorrent_flutter GitHub release - dead weight on iOS,
    // where the bridge does not run, but a dependency cannot opt out of a platform.
    'libtorrent_flutter',
    'open_file_ios',
    'package_info_plus',
    'permission_handler_apple',
    // See the Android note. On iOS `register` wires two channels and
    // constructs an off-screen `MPVolumeView`, which is the documented way to
    // set the system volume and does nothing until used. The side effect is
    // again in the listener rather than the registrar: `onListen` sets an
    // `AVAudioSession` category. The player only ever starts that listener on
    // a handset, and never on desktop, where the routing is libVLC's own gain.
    'flutter_volume_controller',
    'screen_brightness_ios',
    'share_plus',
    'shared_preferences_foundation',
    'sqflite_darwin',
    'url_launcher_ios',
    'vlc_player',
    'wakelock_plus',
    // Deliberately absent: flutter_qjs and install_plugin. Both are vendored
    // under packages/ so they do not reach iOS - flutter_qjs because its FFI
    // symbols collide with flutter_js_ng's under DynamicLibrary.process(),
    // install_plugin because its iOS half only opens App Store URLs and the
    // bridge never calls it. If either shows up here, a vendored pubspec had its
    // platforms widened: read those READMEs first.
  },
  'macos': {
    // Channels only at `register`; the AVAudioSession work is in the
    // listener, which the player never starts on a desktop - see
    // volume_routing.dart, where desktop is `engineOnly`.
    'flutter_volume_controller',
    // anymex_extension_runtime_bridge: the stock plugin template - one
    // `anymex_extension_runtime_bridge` channel that answers getPlatformVersion.
    // The bridge's real work is Dart, and on Android a separate registrar.
    'anymex_extension_runtime_bridge',
    'connectivity_plus',
    'device_info_plus',
    'dynamic_color',
    'file_picker_darwin',
    'flutter_inappwebview_macos',
    'flutter_js_ng',
    'flutter_secure_storage_darwin',
    // Template channel only; libisar is loaded when Dart opens a database.
    'isar_community_flutter_libs',
    // FFI plugin, no registrar; `pod install` downloads liblibtorrent_flutter.dylib
    // from the libtorrent_flutter GitHub release.
    'libtorrent_flutter',
    'open_file_mac',
    'package_info_plus',
    // Desktop has no touch rail, so nothing reaches brightness here. Kept only
    // because macOS does not use DDC/CI for the built-in display the way the
    // Windows plugin does; revisit if that ever stops being true.
    'screen_brightness_macos',
    'screen_retriever_macos',
    'share_plus',
    'shared_preferences_foundation',
    'sqflite_darwin',
    'url_launcher_macos',
    'vlc_player',
    'wakelock_plus',
    'window_manager',
    // Deliberately absent: flutter_qjs. See packages/flutter_qjs/README.md - its
    // FFI symbols collide with flutter_js_ng's under DynamicLibrary.process().
  },
  'linux': {
    // Channels only at `register_with_registrar`. ALSA is not touched until a
    // method call, and the player makes none on a desktop.
    'flutter_volume_controller',
    // anymex_extension_runtime_bridge: the stock plugin template - one
    // `anymex_extension_runtime_bridge` channel that answers getPlatformVersion.
    // The bridge's real work is Dart, and on Android a separate registrar.
    'anymex_extension_runtime_bridge',
    'dynamic_color',
    'flutter_js_ng',
    'flutter_secure_storage_linux',
    // Template channel only. Bundles libisar.so, loaded when Dart opens a
    // database.
    'isar_community_flutter_libs',
    'jni',
    // FFI plugin: it sits in FLUTTER_FFI_PLUGIN_LIST, so no registrant at all. The
    // bridge's copy bundles liblibtorrent_flutter.so, so this build downloads
    // nothing.
    'libtorrent_flutter',
    'open_file_linux',
    'screen_retriever_linux',
    'url_launcher_linux',
    'vlc_player',
    'window_manager',
    // Deliberately absent: flutter_qjs. Its FFI symbols collide with
    // flutter_js_ng's - both are resolved with DynamicLibrary.process() here, and
    // the plugin libraries are linked alphabetically, so it would call into the
    // wrong engine. See packages/flutter_qjs/README.md.
    // Deliberately absent: there is no flutter_inappwebview_linux in 6.1.5, so
    // Linux has no Cloudflare bypass. If one appears here, a dependency bump
    // has endorsed the 6.2.0-beta line, whose CMake hard-fails without five
    // apt packages CI does not install — that breaks the release artifact leg.
    // Decide in the PR, not on release day.
  },
  'windows': {
    // THE ONE TO WATCH. Unlike the other four platforms, the Windows plugin's
    // constructor runs at `RegisterWithRegistrar` and does real work:
    // `CoInitialize(NULL)`, then `IMMDeviceEnumerator` ->
    // `GetDefaultAudioEndpoint(eRender, eConsole)` -> `Activate
    // (IAudioEndpointVolume)`, held until the plugin is destroyed.
    //
    // It is not the screen_brightness_windows bug: that one *wrote* to the
    // monitor at its registrar and again on WM_CLOSE, and leaked a handle per
    // failed probe. This reads and holds, writes nothing, and releases in its
    // destructor. But it is COM initialisation and an endpoint activation at
    // startup for a feature Windows never uses - the player's desktop routing
    // is libVLC's own gain and calls none of this.
    //
    // Left in rather than stubbed because the package is not federated, so
    // there is no per-platform implementation to override the way
    // packages/screen_brightness_windows overrides one. If this ever needs to
    // go, the move is to put the Android and iOS side into packages/
    // vlc_player instead, which already registers on both and would add no new
    // surface here at all.
    'flutter_volume_controller',
    // anymex_extension_runtime_bridge: the stock plugin template - one
    // `anymex_extension_runtime_bridge` channel that answers getPlatformVersion.
    // The bridge's real work is Dart, and on Android a separate registrar.
    'anymex_extension_runtime_bridge',
    'connectivity_plus',
    'dynamic_color',
    // The D3D11 device at registration. Kept on purpose: Windows Cloudflare
    // support depends on it. See the WebViewEnvironment work in
    // cloudflare_bypass.dart.
    'flutter_inappwebview_windows',
    'flutter_js_ng',
    // QuickJS for the bridge's JavaScript backends. The registrar is empty (the
    // plugin class exists so CMake builds flutter_qjs_plugin.dll); the engine is
    // that DLL, loaded by name over FFI, so it cannot meet flutter_js_ng's
    // flutter_js_plugin.dll. packages/flutter_qjs.
    'flutter_qjs',
    'flutter_secure_storage_windows',
    // Template channel only; libisar is loaded when Dart opens a database.
    'isar_community_flutter_libs',
    'jni',
    // FFI plugin, no registrar. CMake downloads libtorrent_flutter.dll from the
    // GitHub release at configure time.
    'libtorrent_flutter',
    // Dead code on Windows — every Permission.* call site is Platform.isAndroid
    // gated — but its registrar only builds method and event channels, so it is
    // not worth a stub package to remove.
    'permission_handler_windows',
    // OUR STUB, not upstream: packages/screen_brightness_windows is a no-op
    // registrar that keeps the real plugin's DDC/CI traffic off Windows. The
    // "Vendored Forks Resolve From Path" CI step asserts it still resolves from
    // the vendored path; this only asserts it is still the thing registering.
    'screen_brightness_windows',
    'screen_retriever_windows',
    'share_plus',
    'url_launcher_windows',
    'vlc_player',
    'window_manager',
  },
};

void main() {
  test('every platform registers exactly the native plugins we expect', () {
    final manifest = File('.flutter-plugins-dependencies');
    expect(
      manifest.existsSync(),
      isTrue,
      reason:
          'run from the package root; `flutter pub get` writes this file and '
          '`flutter test` runs pub get first, so it should always be here',
    );

    final plugins =
        (jsonDecode(manifest.readAsStringSync())
                as Map<String, dynamic>)['plugins']
            as Map<String, dynamic>;

    final problems = <String>[];

    for (final platform in _expected.keys) {
      final listed = (plugins[platform] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>();
      final actual = listed
          .where((p) => p['native_build'] == true)
          .map((p) => p['name'] as String)
          .toSet();

      final added = actual.difference(_expected[platform]!);
      final removed = _expected[platform]!.difference(actual);

      for (final name in added) {
        problems.add(
          '$platform GAINED "$name". Something now compiles and registers '
          'native code on $platform. Read what it does at registration before '
          'adding it to the list — that is the step both shipped bugs skipped.',
        );
      }
      for (final name in removed) {
        problems.add(
          '$platform LOST "$name". If that was deliberate, delete it from the '
          'expected set. If not, a dependency or override has been dropped.',
        );
      }
    }

    expect(
      problems,
      isEmpty,
      reason:
          'The native plugin surface changed.\n\n${problems.join('\n\n')}\n\n'
          'This list is not a rule, it is a ledger: update it in the same '
          'commit as the dependency change, once you know what the plugin does '
          'when it registers.',
    );
  });
}
