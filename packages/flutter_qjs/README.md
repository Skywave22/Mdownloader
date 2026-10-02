# flutter_qjs (Android and Windows only)

This is [`kodjodevf/flutter_qjs`](https://github.com/kodjodevf/flutter_qjs) at
`f3cef51` - the QuickJS binding `anymex_extension_runtime_bridge` runs Mangayomi,
Sora and LnReader JavaScript on - with its **native half restricted to Android and
Windows**, and its Dart half made to fail loudly everywhere else. It is wired in
through `dependency_overrides` in the app's `pubspec.yaml`. License: MIT,
upstream's (`LICENSE`).

## Why

This app already ships a QuickJS: `packages/flutter_js_ng`, which is how SkyStream
plugins run. Both are forks of the same FFI layer, and **they export the same
~50 C symbols** - `jsNewRuntime`, `jsNewContext`, `jsEval`, `jsFreeValue`,
`jsNewObject`, `jsThrow` and so on - while wrapping two different QuickJS source
trees (flutter_js_ng builds `dtoa.c` and no `libbf`; flutter_qjs builds `cutils.c`
and `libbf.c`, see `cxx/quickjs.cmake`).

Each Dart side finds its symbols one of two ways:

| | flutter_js_ng | flutter_qjs (upstream) |
| --- | --- | --- |
| Android | `libfastdev_quickjs_runtime.so` | `libqjs.so` |
| Windows | `flutter_js_plugin.dll` | `flutter_qjs_plugin.dll` |
| Linux | `libflutter_js_plugin.so` | `DynamicLibrary.process()` |
| macOS, iOS | `DynamicLibrary.process()` | `DynamicLibrary.process()` |

A named library resolves its own symbols, so Android and Windows are safe. A
`process()` lookup takes the first definition in the process, and on Linux the
plugin libraries are linked in alphabetical order (`flutter_js_ng`, then
`flutter_qjs`), so upstream's `flutter_qjs` would call into flutter_js_ng's engine
through functions it was not written against. The likely outcome is a crash or
memory corruption the first time a user opens a JavaScript-based source - in a
feature (MultiProviders / MStream) that nothing exercises at startup, so CI would
not see it.

## What changed

* `pubspec.yaml` declares **Android and Windows only**, so Linux, macOS and iOS
  build and link none of it. Upstream also lists those three.
* `lib/quickjs/ffi.dart`: the `DynamicLibrary.process()` fallback is a
  `throw UnsupportedError(...)`. On a platform without its own library the failure
  is immediate and named, instead of a call into the wrong engine.
* `android/build.gradle` modernised: `namespace`, Java 17, no second AGP/Kotlin in a
  `buildscript`. `android/src/main/AndroidManifest.xml` loses `package=`.
* Everything else - the Dart, `cxx/` (QuickJS and the FFI layer), the Kotlin and the
  Windows CMake - is upstream's. The iOS, macOS and Linux directories, the example
  app and `cxx/prebuild.sh` (which only feeds the iOS and macOS pods) are not copied.

## What it costs

On Linux, macOS and iOS the bridge's JavaScript backends (Mangayomi JS, Sora,
LnReader) throw `UnsupportedError` instead of running. Mangayomi's Dart extensions
(through `packages/d4rt`) and, with the Runtime Host, Aniyomi and CloudStream are
unaffected, and Android and Windows get everything.

## Getting those platforms back

Rename the exported symbols so they cannot meet: prefix every `DLLEXPORT` function
in `cxx/ffi.cpp` and the matching `lookup('...')` strings in `lib/quickjs/ffi.dart`,
and compile the C sources of the bundled `quickjs` target with
`-fvisibility=hidden` so `JS_*` stays private too. Then restore `linux`, `macos` and
`ios` in `pubspec.yaml` and the three platform directories from upstream. It has to
be tested by running a script on each platform with both engines loaded, which is
more than the CI smoke test does today.
