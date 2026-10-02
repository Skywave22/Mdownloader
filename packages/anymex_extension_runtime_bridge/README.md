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

6. **`ExtensionManager` — deterministic, failure-isolated registration.**
   `onInit` used to fire `_initDefaultManagers()` unawaited; any exception in
   that chain (`checkAndInitialize` → `registerAndInitializeManagers` →
   `onRuntimeBridgeInitialization`) silently left Sora/Mangayomi/Legado
   unregistered for the whole session — only CloudStream (registered by the
   app separately) kept working, installed lists stayed empty after restart,
   and `addRepo` no-oped. Now: `ensureInitialized()` memoizes the chain so
   callers can await it; the chain catches/logs errors per step; and
   `registerAndInitializeManagers` isolates each manager's `initialize()`
   with try/catch so one broken backend no longer aborts the loop.

7. **`ExtensionManager.addRepo`/`addRepos` — fail loudly.** A missing
   backend used to return silently ("I added a link and nothing happened").
   Both now throw `StateError('No extension backend "$managerId" is
   registered')` so the UI can show the real cause.

8. **`addRepo` on every backend — re-adding a saved repo re-fetches and
   merges** (Mangayomi/Sora/Aniyomi/Legado). All four used to `return`
   silently when the repo URL was already known, so re-adding a link whose
   earlier fetch had failed (or whose list was stale) showed "nothing" -
   the exact user complaint. The repo entry is still only appended once, but
   its manifest is always re-parsed and merged into the available list.
   Additionally, Legado's `addRepo` no longer silently ignores non-novel
   types (it throws a clear "add them from the Novel tab" error), and the
   app routes Legado links to the novel type automatically.

`prebuilt/` and `RuntimeBridges/` from upstream are not vendored (47+ MB of
build-script artifacts; the Flutter build does not reference them).
`dependency_overrides` in upstream's pubspec are stripped — the app root's
overrides apply instead.
