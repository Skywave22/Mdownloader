# MDownloader

**TMDB catalog → plugin-powered multi-site scraping → download anything with a real parallel segmented download engine.**

One Flutter codebase → **Android APK** + **Windows EXE**, built by GitHub Actions and published to Releases on every `v*` tag.

## What it does

- **Catalog** — TMDB search/trending/popular + full details (seasons & episodes).
- **Plugin system** — each site is a separate `plugin.js` + `plugin.json` that
  the app loads at runtime. Tap **Find downloads** and every enabled plugin is
  queried in parallel; all found links are listed and one tap queues the
  download. See **[PLUGINS.md](PLUGINS.md)** to write your own.
- **Real segmented downloader** — splits a file into chunks and downloads them
  with 8 parallel HTTP range requests (the IDM/aria2 technique), with
  per-chunk resume, retry, pause/resume. Proven in tests: **~4–6× speedup** on
  per-connection-throttled servers, byte-exact output.
  > Honest note: parallel segments multiply throughput only up to your actual
  > internet bandwidth — no software can exceed your ISP line speed.
- **HLS downloader** — captures an .m3u8 stream (segments fetched in parallel,
  concatenated) with no ffmpeg.
- **Download manager** — queue, pause/resume/cancel, live speed & progress,
  persisted across restarts, completed files playable in the built-in player.

## Bundled plugins

- `YouTube (Hindi Dubbed)` — resolves movies/episodes via the InnerTube API to
  direct MP4 (360p/720p) and HLS links. Working reference implementation.
- `Template` — a commented starter plugin for building your own.

## Build & run

```bash
flutter create . --platforms android,windows --project-name mdownloader
flutter pub get
flutter run                            # debug
flutter build apk --release            # Android APK
flutter build windows --release        # Windows EXE
```

## Releases (GitHub Actions)

Push a `v*` tag (e.g. `v0.2.0`) → the workflow builds the APK (Ubuntu) and the
EXE (Windows), then attaches `app-release.apk` and `mdownloader-windows-x64.zip`
to the GitHub Release.

## Project layout

```
lib/
├── main.dart                        # app shell (Home/Search/Downloads/Plugins)
├── core/
│   ├── config.dart                  # TMDB key + downloader defaults
│   └── theme.dart                   # design system
├── models/
│   ├── media.dart                   # TMDB media/season/episode
│   └── download.dart                # DownloadKind
├── services/
│   ├── tmdb_service.dart            # TMDB client
│   └── locator.dart                 # singletons
├── plugins/
│   ├── plugin_bootstrap.dart        # QuickJS engine + Dart↔JS bridge + plugin wrapper
│   └── plugin_manager.dart          # scan/load/enable/import plugins, run loadStreams
├── downloader/
│   ├── segmented_downloader.dart    # parallel range download engine
│   ├── hls_downloader.dart          # HLS capture engine
│   └── download_manager.dart        # queue + persistence
└── ui/                              # screens
assets/plugins/                      # bundled example plugins
test/                                # engine + downloader tests
```

## Tests

```bash
flutter test
```

- `segmented_downloader_test` — byte-exact + speedup on a throttled server.
- `hls_downloader_test` — byte-exact segment capture.
- `plugin_engine_test` — loads a real plugin and drives it through the JS
  bridge against a local HTTP server.

## Notes

- Replace the shared TMDB key in `lib/core/config.dart` with your own free key
  from themoviedb.org.
- The built-in player is Android-first; on Windows, open downloaded files with
  any player from `<exe dir>/plugins/../` Documents/downloads.
