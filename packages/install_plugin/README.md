# install_plugin (Android only, Gradle 9 build fix)

This is **install_plugin 2.1.0** with its Android build script brought up to
Gradle 9 / AGP 8, and its iOS half removed. It is wired in through
`dependency_overrides` in the app's `pubspec.yaml`. License: MIT, upstream's
(`LICENSE`).

## Who needs it

`anymex_extension_runtime_bridge` calls `InstallPlugin.installApk(...)` from the
Aniyomi backend, on Android, to hand an extension APK to the system installer.

## Why a copy

* Upstream's `android/build.gradle` declares **no `namespace`**, which AGP 8
  requires of every library module, so the Android build fails when it reaches
  this plugin. It also pins its own AGP 7.3 and Kotlin 1.7.10 in a `buildscript`.
* Upstream also registers an **iOS** plugin whose one method opens an App Store
  URL (`gotoAppStore`). The bridge never calls it, and the bridge does not run on
  iOS at all (`AnymeXRuntimeBridge.isSupportedPlatform` is `!Platform.isIOS`).
  This copy declares Android alone, so the iOS build compiles and registers
  nothing for it.

The Kotlin source and the Dart API are untouched.

## What changed

* `android/build.gradle` - `namespace`, Java 17, `androidx.core` for the
  `FileProvider` the plugin extends (upstream got it via the old
  `androidx.legacy:legacy-support-v4`).
* `android/src/main/AndroidManifest.xml` - dropped `package=` (superseded by
  `namespace`).
* `pubspec.yaml` - version `2.1.0+1`, `publish_to: none`, Android platform only.
* The upstream `ios/` directory, example app and IDE files are not copied.

## When to delete this

When the bridge stops using `install_plugin`, or upstream ships a build script
that works on Gradle 9. Then drop the `install_plugin` entry from
`dependency_overrides`.
