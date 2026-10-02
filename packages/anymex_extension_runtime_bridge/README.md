# anymex_extension_runtime_bridge (vendored fork)

Vendored from [RyanYuuki/AnymeXExtensionRuntimeBridge](https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge)
tag `v2.6.0` (package version 1.6.1), wired in via `dependency_overrides` in the
app's `pubspec.yaml` — the same pattern as the other vendored forks here (see
the "Vendored Forks Resolve From Path" step in `.github/workflows/ci.yml`).

Why vendored: three bugs live upstream and break the product outright on
Android; the fixes below are small and kept as close to upstream code as
possible so they can be offered back as a PR.

## Changes vs. v2.6.0

1. **`Services/CloudStream/CloudStreamSourceMethods.dart` — `getPopular` /
   `getLatestUpdates` were hard-coded empty stubs** (`Pages(list: [], …)`).
   Every CloudStream source therefore returned "Nothing found" in browse mode
   on Android. Both now perform an empty-query search, matching what
   `DesktopCloudStreamSourceMethods` already does (an empty query is the
   catalogue listing for CloudStream's `MainAPI.search`).

2. **`Services/CloudStream/CloudStreamExtensions.dart` — installed-plugin
   self-heal.** `fetchInstalledAnimeExtensions` used to publish an empty
   installed list whenever `getRegisteredProviders` returned empty/failed at a
   cold start (host not warmed yet), which made every installed extension
   "disappear" until reinstalled. It now detects plugin files on disk, reloads
   them into the host and re-queries before ever publishing an empty list.

3. **`Services/CloudStream/CloudStreamExtensions.dart` — install speed.**
   `installSource` awaited a full `fetchAnimeExtensions()` (a re-download of
   every repository manifest) after *each* install; it now trims the local
   availability list instead. `uninstallSource`'s refetch is fire-and-forget
   for the same reason. Explicit repo add/remove still refresh eagerly.

4. **`Models/DMedia.dart` — `fromCs` episode order.** The reversal condition
   `(ep[0] != '0') || (ep[0] != '1')` is always true, so episode order flipped
   depending on what the source returned. Episodes are now sorted
   deterministically with `DEpisode.compareByEpisodeNumber` (ascending).

5. **`ExtensionManager.refreshInstalled()`** — new helper that re-reads every
   backend's installed lists and re-aggregates (no repository network
   traffic). UIs call it on open so a transient empty publish self-heals.

`prebuilt/` and `RuntimeBridges/` from upstream are not vendored (47+ MB of
build-script artifacts; the Flutter build does not reference them).
`dependency_overrides` in upstream's pubspec are stripped — the app root's
overrides apply instead.
