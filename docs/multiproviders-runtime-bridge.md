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

- Dependency is pinned by git ref in `pubspec.yaml`
  (`anymex_extension_runtime_bridge`, ref `v2.6.0`) and pulls in `get`,
  `isar_community` and `libtorrent_flutter`. Run `flutter pub get`; if
  `libtorrent_flutter` cannot be resolved, add a `dependency_overrides` entry
  pointing at the copy vendored in the bridge repo.
- Router code is generated: run `dart run build_runner build -d` after
  changing routes.
- On Windows the Runtime Host can also be installed manually with the
  upstream `scripts/setup-windows.ps1`.
