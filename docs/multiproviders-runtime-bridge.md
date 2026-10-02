# MultiProviders — AnymeX Extension Runtime Bridge

MultiProviders (Settings → Extensions → MultiProviders) wires SkyStream to
[AnymeXExtensionRuntimeBridge](https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge),
a runtime-agnostic API over **Aniyomi**, **CloudStream**, **Mangayomi** and
**Sora** extension sources. The **MStream** tab browses and plays what is
installed there.

## Layout

| File | Role |
| --- | --- |
| `lib/features/multiproviders/data/multiprovider_bridge.dart` | Lifecycle + Riverpod surface (`multiProviderBridgeProvider`, `installedSourcesProvider`, `availableSourcesProvider`) |
| `lib/features/multiproviders/presentation/multi_providers_screen.dart` | Runtime Host install/update, repositories, install/uninstall sources |
| `lib/features/mstream/presentation/mstream_screen.dart` | Source picker, popular/search grid, episode sheet, playback |

## Lifecycle

1. `AnymeXExtensionBridge.init(projectName: 'SkyStream', getDirectory: …)` —
   opens the bridge's Isar DB under the app support directory
   (`<support>/MultiProviders`).
2. `AnymeXRuntimeBridge.checkAndInitialize()` — picks up a previously
   downloaded Runtime Host.
3. `ExtensionManager.onRuntimeBridgeInitialization()` — registers Aniyomi and
   CloudStream once the host is loaded.

Mangayomi and Sora work without the host (`MultiProviderStage.partial`);
Aniyomi and CloudStream need it (`MultiProviderStage.ready`). iOS reports
`unsupported`. Initialization is lazy — it happens the first time either
screen is opened, never at app launch.

## Playback path

`SourceMethods.getPopular/search → getDetail → getVideoList`, then the
resulting `Video`s are mapped to SkyStream `StreamResult`s and pushed to the
player as `preloadedStreams`, so the player does not try to re-resolve them
through the SkyStream plugin engine.

## Build notes

- The dependency is pinned by git ref in `pubspec.yaml`
  (`anymex_extension_runtime_bridge`, ref `v2.6.0`). It is written for AnymeX,
  whose pins differ from this app's, and a package's own `dependency_overrides`
  are ignored by whoever depends on it - so **the mismatches are settled in this
  repo's `dependency_overrides`**, each with a comment saying why. `flutter pub
  get` fails without them. In short:
  - `file_picker`, `pointycastle`, `flutter_inappwebview` are constraint
    overrides (the last keeps the app off the 6.2 beta, which adds a Linux plugin
    CI cannot build).
  - `libtorrent_flutter` is the bridge's own copy, from its git repository: it has
    the `customLibraryPath` setter the hosted package lacks.
  - `d4rt`, `device_apps`, `install_plugin` and `flutter_qjs` are **vendored under
    `packages/`**, because the published versions cannot be used: d4rt needs
    analyzer 7 and the app resolves 14; device_apps and install_plugin cannot be
    configured by Gradle 9 / AGP 8; flutter_qjs exports the same C symbols as
    `flutter_js_ng`. Each has a README with what changed and when to delete it.
- **JavaScript backends are Android and Windows only.** Mangayomi JS, Sora and
  LnReader run on `flutter_qjs`, which is not built for Linux, macOS or iOS here
  (its symbols would collide with the SkyStream plugin engine); there they throw
  `UnsupportedError` instead. Mangayomi's Dart extensions work everywhere, and
  Aniyomi and CloudStream work wherever the Runtime Host does. See
  `packages/flutter_qjs/README.md` for how to get the other platforms back.
- Android: the bridge brings `REQUEST_INSTALL_PACKAGES` (to hand extension APKs to
  the system installer) and a `FileProvider`, through `install_plugin`.
- `test/platform/native_plugin_surface_test.dart` records what each new plugin
  does at registration.
- Router code is generated: run `dart run build_runner build -d` after changing
  routes.
- On Windows the Runtime Host can also be installed manually with the upstream
  `scripts/setup-windows.ps1`.
- The bridge is licensed under the Unabandon Public License, a GPLv3 variant that
  also requires public source, and `libtorrent_flutter` is GPL-3.0; distributing
  a build that links them is subject to those terms.
