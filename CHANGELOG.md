# Changelogs - Unreleased

### ✨ *New Features & Enhancements*
- **Extension runtime in Settings** – New "Extension runtime bridge" entry in Settings with a one-tap install/update button for the Runtime Host APK (the same download the MultiProviders screen runs) and the bridge author credit.
- **MStream is laid out like Home** – Same chrome (title, circular search button, source pill in the right corner), the same hero carousel of top titles, and the same horizontal rails ("Popular", "Latest updates") with "View All" opening a paginated grid. In-source search opens the same search UI Home uses, scoped to the active extension.
- **MultiProviders redesigned** – Extensions are now rich rounded cards (large icon, name, update badge, language/version/backend chips) with a search filter over the lists and a styled install button on the Available tab.
- **Faster "Install All"** – Installs now run three at a time, and no longer re-download every repository manifest after each individual install (that alone made installs take minutes).
- **MStream opens like Home** – Tapping a title now opens a full details page with the same layout as Home: poster banner with legibility scrims and a shared-element poster flight, title, metadata pills (genres, author, artist, episode count), Play/Download actions, expandable synopsis, and a full episode list with thumbnails and per-episode play/download buttons.
- **MStream posters are Home posters** – The grid now renders the exact Home card (same shimmer placeholder, error fallback, decode bounds, title-position setting and focus scale), with extension-required Referer/User-Agent headers layered on top.
- **Extension runtime credit** – The AnymeX Extension Runtime Bridge by RyanYuuki is credited in-product: a small credit line appears under the add-repository dialog, the install-all progress dialog, the MultiProviders list and the MStream details page.
- **MStream switches sources like Home** – A pill in the top-right corner names the active source and opens a selector dialog (filter chips plus a source list), the same affordance and behaviour as the provider switcher on Home. The last picked source is remembered across restarts.
- **Install all / install one** – MultiProviders' Available tab can install every still-uninstalled source of the selected type in sequence (with progress and a cancel button), or a single source at a time.
- **Enable / disable sources** – Installed sources can be toggled off without uninstalling: they stay installed and updatable but disappear from MStream and its search until re-enabled.
- **MStream pagination and refresh** – Popular and search results load further pages as you scroll, the grid pulls to refresh, and failures show a Retry button instead of a bare error string.

### 🐞 *Bug Fixes & System Stability*
- 🛠️ **Fixed: re-adding a repository link showing nothing** – Every backend (Mangayomi, Sora, Aniyomi, Legado) silently ignored a repo URL it had seen before — so a link whose earlier fetch failed, or whose list was stale, produced no extensions ever again. Re-adding now re-fetches and merges the manifest every time. Legado links also route to the novel type automatically (Legado is a novel backend) instead of being dropped on other tabs, and Legado is now offered in the add-repository dialog at all.
- 🛠️ **Fixed: MStream dead-ending on a broken first source** – The remembered/first source is now preferred only while its extension is actually reachable; otherwise the screen automatically selects the first source that resolves instead of showing "first is not working" forever.
- 🛠️ **Fixed: only CloudStream extensions working; Mangayomi/Sora/Aniyomi/Legado dead** – The bridge's manager registration ran as an unawaited side effect of its GetX `onInit`, and one exception anywhere in that chain silently left every other backend unregistered for the whole session (installed lists stayed empty after restart and "add repository" did nothing). Registration is now a memoized `ensureInitialized()` the app awaits before touching any backend, errors are isolated per backend, and the chain is logged instead of vanishing.
- 🛠️ **Fixed: switching extensions could blank the whole MStream screen** – A malformed cover URL crashed `Uri.resolve` while building the poster grid. Bad paths now fall back to the raw URL and let the image placeholder handle the failure.
- 🛠️ **Fixed: "add repository" showing nothing** – An invalid repo URL or an unregistered backend failed silently. The dialog now shows the failure in a SnackBar (with the real cause) and confirms successful adds; available lists refresh either way.
- 🛠️ **Fixed: MStream silently blank when a source cannot resolve** – Instead of an empty screen with no feedback, a source whose extension cannot be reached now shows the retry state like every other load failure.
- 🛠️ **Fixed: "Nothing found" for every CloudStream extension (root cause found in the runtime bridge)** – The bridge's Android CloudStream adapter shipped hard-coded *empty* `getPopular`/`getLatestUpdates` stubs (the desktop adapter already fell back to an empty-query search). The bridge is now vendored (`packages/anymex_extension_runtime_bridge`) with the fix: browse mode lists the source catalogue like it always should have.
- 🛠️ **Fixed: installed extensions "disappearing" after a restart** – A cold-start race could make a backend publish an empty installed list before its plugins finished loading, and nothing re-read the store afterwards. The vendored bridge reloads persisted plugins and re-queries before ever publishing empty, and the app re-reads installed lists whenever MultiProviders opens.
- 🛠️ **Fixed: slow extension installs** – Installing an extension re-downloaded every repository manifest afterwards; it now updates the local list only. "Install All" additionally installs three extensions concurrently instead of one-by-one.
- 🛠️ **Fixed: episode order flipping between sources** – The bridge's CloudStream adapter (`DMedia.fromCs`) reversed episode order on a condition that is always true; episodes are now sorted deterministically by number (fixed in the vendored bridge, and sorted again at the app layer).
- 🛠️ **Fixed: Downloads of extension content resolving through the wrong provider** – Downloading from MStream used to fall back to the active SkyStream plugin and download an unrelated URL. Extension streams are now passed to the download flow already resolved (with their headers), and "Select Another Source" keeps them instead of re-resolving.
- 🛠️ **Fixed: Downloads refused on hosts without Content-Length** – Sources whose size probe fails no longer get rejected as "doesn't support direct downloading"; only HLS playlists (`.m3u8`) are refused, with a localized message.
- 🛠️ **Fixed: Download filenames like "S0-E3 name"** – Extension episodes carry no season; the season segment only appears when there is one, and empty episode names no longer leave a stray space.
- 🛠️ **Fixed: Episode order flipping between sources** – The bridge's CloudStream adapter (DMedia.fromCs) reverses episode order on a condition that is always true; episodes are now sorted deterministically by number so every extension lists ascending.
- 🛠️ **Fixed: Extension icons not loading in MultiProviders** – Relative icon paths resolve against the source's base URL and fall back to the extension glyph on failure.
- 🛠️ **Fixed: MStream posters failing to load** – Extension covers are now cached and fetched with a browser User-Agent and the source's Referer (many CDNs reject the bare Dart client), and site-relative / protocol-relative cover URLs are resolved against the source instead of failing silently.
- 🛠️ **Fixed: MStream "nothing loads" on some sources** – When a source's popular feed is missing or errors, the tab falls back to its latest feed instead of leaving the grid empty; stale responses from an earlier search or source switch no longer overwrite the current results.
- 🛠️ **Fixed: MultiProviders Available tab listing already-installed sources** – Installed extensions are hidden from the available list (they stay visible under Installed, with update/uninstall).
- 🛠️ **Fixed: CI "Package d4rt" leg dying on exit code 64** – `dart analyze` has no `--no-fatal-infos` option (the flag cannot be negated); the leg now runs plain `dart analyze`, whose defaults match its intent.
- 🌍 New localizations (English, Hindi, Kannada): author/artist labels, the runtime-bridge credit, and the download error messages that were previously hard-coded English.

---

# Changelogs - v2.8.1

### ✨ *New Features & Enhancements*

#### 🧩 Stremio Add-ons & Nuvio (thanks to [Skywave22](https://github.com/Skywave22))
- **Official-style Quick Install and a working Discover tab** – Quick Install lists the two official add-ons (Cinemeta and OpenSubtitles v3). Discover gains search, pull-to-refresh and a retry state, skips broken entries, folds duplicates, and sends add-ons that need configuring to their setup page.
- **Faster link fetching** – Every stream add-on is asked in parallel, each within its own time budget, so one slow or dead add-on no longer holds up the rest, and slow scraping add-ons such as the CNCVerse bridge get long enough to answer.
- **Add-on health badges** – The Manage tab shows whether each installed add-on is working and how fast it answers.
- **Search and provider chips** – Filter the Stremio sources sheet by add-on, provider, quality or label, and search your installed add-ons.
- **Clearer stream rows** – Rows read "Add-on · Provider", with the resolution always shown.
- **Nuvio link fixes** – Embedded stream objects, file names with spaces, `#` or `+`, and scraper ids with special characters no longer break link fetching.

#### 🎬 Player & Playback
- **Smoother seeking** – Quick repeated seeks (arrow keys, D-pad, gamepad shoulder buttons, double-taps) are merged: the first goes at once and the final position follows the moment you stop, instead of a full rebuffer for every press.
- **The seek bar follows your seek at once** – The scrubber and the clock move to where you sent playback straight away, instead of waiting for the stream to get there.
- **Clearer source status** – Sources that are not a video, or that cannot seek, are labelled in the Sources list, and resuming prefers a source that can seek.
- **Half the memory for the network buffer** – libVLC's read-ahead buffer was being allocated twice; the buffer size you choose is now the memory it uses.

#### 💬 Subtitles
- **Subtitle search in the player panel** – Online subtitle search opens as a page inside the player's side panel.
- **Subtitle files drawn by SkyStream** – SRT, WebVTT (including HLS subtitle playlists) and SSA/ASS files are drawn over the video by the app, so Zoom and Stretch no longer push lines off screen, and files that need the source's headers now load.
- **The right file from season packs** – When a provider sends a whole season as one archive, the episode being watched, in the language asked for, is picked instead of the first file in it.
- **Automatic subtitle language** – Auto picks a subtitle in your preferred language from the video's own tracks, however the source names the language.
- **Embedded subtitles with Zoom and Stretch** – Subtitles inside the video stay on screen whichever fit is chosen.

#### 📺 TV & Navigation
- **D-pad text entry** – Text fields no longer steal D-pad directions, so TV keyboards keep all four arrows for picking letters.
- **Back exits from Home** – Back on the home screen now leaves the app instead of doing nothing.
- **Focus rings follow the input** – Focus highlights show when you use a keyboard, remote or gamepad, and stay out of the way on touch.
- **Clear of the bottom bar** – Lists on every screen, settings pages and bookmarks included, scroll clear of the floating bottom navigation.

#### ⚙️ Settings & Extensions
- **Extensions update on launch** – SkyStream plugins, Nuvio scrapers and Stremio add-ons are checked on every launch; followed collections add the repositories they newly list, and what changed is summed up in at most three toasts.
- **TMDB API key check** – A pasted key is cleaned of spaces and invisible characters, pasting TMDB's v4 read token instead of the key is explained, and a network problem is no longer reported as a wrong key.
- **External player** – The chosen default player is honoured end to end, including request headers on Android.

---

### 🐞 *Bug Fixes & System Stability*
- 🛠️ **Fixed: resuming could open to a black screen reading "LIVE"** – Happened when a different source was picked while the resume was still opening.
- 🛠️ **Fixed: some HLS episodes read 27:46:39** – The seek bar, the next-episode card and the end of the episode now use the video's real length.
- 🛠️ **Fixed: "Reconnecting…" after seeking** – A slow refill after a seek is no longer taken for a dead connection, and the recovery step re-issues your seek instead of jumping back to where you were.
- 🛠️ **Fixed: the buffered band on the seek bar** – It no longer vanishes or jumps after a seek, and shows what is really buffered after seeking back.
- 🛠️ **Fixed: Discover stayed empty for hours after a single network error.**
- 🛠️ **Fixed: slow stream add-ons timed out mid-scrape.**


### ⚙️ Improvements
- 🚀 The Riverpod lint rules now run as a reliable CI gate.
- 🚀 Various performance improvements and stability fixes across the app.
