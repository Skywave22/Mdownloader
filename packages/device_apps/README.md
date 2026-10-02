# device_apps (Gradle 9 build fix)

This is **device_apps 2.2.0**, byte-for-byte except for `android/build.gradle`
and the `package=` attribute of the manifest. It is wired in through
`dependency_overrides` in the app's `pubspec.yaml` and exists only because the
published package cannot be built by this app's toolchain. License: Apache-2.0,
upstream's (`LICENSE`).

## Who needs it

`anymex_extension_runtime_bridge` calls it from the Aniyomi backend, on Android
only, to ask whether an extension APK is installed as a system package
(`isAppInstalled`) and to remove one (`uninstallApp`). The plugin is Android-only
upstream as well.

## Why a copy

Upstream's build script is from 2021, and this app builds with Gradle 9.1 and
AGP 8.13:

* It resolves its plugins from **`jcenter()`**, which Gradle 9.0 removed. The
  script fails to evaluate, so the whole Android build stops before compiling a
  line.
* It declares **no `namespace`**, which AGP 8 requires of every library module.

The Java source did not need to change: it uses plain Android APIs and
`androidx.annotation`, and the v2 plugin embedding.

## What changed

* `android/build.gradle` - no `buildscript`/`jcenter()`, `namespace`, Java 17.
* `android/src/main/AndroidManifest.xml` - dropped `package=` (superseded by
  `namespace`; AGP 8 warns about having both).
* `pubspec.yaml` - version `2.2.0+1`, `publish_to: none`; no iOS entry, as
  upstream.

## When to delete this

When the bridge stops using `device_apps`, or upstream ships a build script that
works on Gradle 9. Then drop the `device_apps` entry from `dependency_overrides`;
nothing in the app imports it directly, it is only reached through the bridge.
