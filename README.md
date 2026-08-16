# MDownloader

**A beautiful, plugin-powered downloader for movies & series — with instant links, a real parallel download engine, and a built-in player.**

One Flutter codebase → **Android APK** + **Windows EXE**, built by GitHub Actions and published to Releases on every `v*` tag.

## What it does

- **Cinematic catalog** — TMDB trending/popular/search + full details (seasons &
  episodes) in a deep-dark, gradient UI.
- **Instant links** — open any title and MDownloader automatically queries every
  enabled plugin in parallel and lists downloadable copies right on the page.
  No "search → scrape → copy URL" dance.
- **Plugin system** — each site is a separate `plugin.js` + `plugin.json` loaded
  at runtime (sandboxed QuickJS). See **[PLUGINS.md](PLUGINS.md)** to write your
  own, and install `.zip`/`.sky` packages from the Plugins tab.
- **Hindi-dubbed sources built in** — Goldmines, Ultra Movie Parlour and Pen
  Movies plugins ship with the app and resolve **direct MP4 + HLS** links
  through YouTube's InnerTube API (no ffmpeg, no yt-dlp).
- **Real segmented downloader** — splits a file into chunks downloaded with up
  to 16 parallel HTTP range requests (the IDM/aria2 technique), with per-chunk
  resume, retry, pause/resume. Proven in tests: **~4× speedup** on
  per-connection-throttled servers, byte-exact output.
  > Honest note: parallel segments multiply throughput only up to your actual
  > internet bandwidth — no software can exceed your ISP line speed.
- **HLS downloader** — captures an .m3u8 stream (segments fetched in parallel,
  concatenated) with no ffmpeg.
- **Download manager** — queue, auto-start, pause/resume/cancel, live speed &
  progress, persisted across restarts, completed files playable in the built-in
  player.
- **Choose your download folder** — Settings → Download location. On Windows it
  defaults to `Downloads\MDownloader`.

## Tabs

| Tab | What it does |
|---|---|
| Home | TMDB hero, Hindi-dubbed shortcut, trending/popular rows |
| Discover | Search inside your installed plugins (Hindi-dubbed & more) — instant links |
| Search | TMDB title search (movies + series) |
| Downloads | Active queue, speed/progress, pause/resume, play, delete |
| Plugins | Enable/disable/delete/install site plugins |

## Bundled plugins

| Plugin | Source |
|---|---|
| Goldmines (Hindi Dubbed) | #1 Hindi-dubbed network |
| Ultra Movie Parlour | Hindi-dubbed + Bollywood |
| Pen Movies (Hindi) | South-Indian / Bollywood |
| YouTube (Hindi Dubbed) | general YouTube search |
| Template | commented starter for your own plugin |

## Security

See **[SECURITY.md](SECURITY.md)** for the security policy, supported versions
and how to report vulnerabilities privately. The plugin engine is sandboxed:
plugins get only `http_*`, hashing, base64 and a tiny per-plugin storage — no
file system, no other app access, no telemetry.

## Build & run

```bash
flutter pub get
flutter run                            # debug
flutter build apk --release            # Android APK
flutter build windows --release        # Windows EXE
```

## Releases (GitHub Actions)

Push a `v*` tag (e.g. `v0.3.0`) → the workflow builds the APK (Ubuntu) and the
EXE (Windows), then attaches `app-release.apk` and `mdownloader-windows-x64.zip`
to the GitHub Release.

## Project layout

```
lib/
├── main.dart                        # app shell (Home/Discover/Search/Downloads/Plugins)
├── core/
│   ├── config.dart                  # TMDB key + downloader defaults
│   ├── settings.dart                # persisted settings (download folder, workers)
│   └── theme.dart                   # design system (glass, gradients, glows)
├── models/
│   ├── media.dart                   # TMDB media/season/episode
│   └── download.dart                # DownloadKind
├── services/
│   ├── tmdb_service.dart            # TMDB client
│   └── locator.dart                 # singletons
├── plugins/
│   ├── plugin_bootstrap.dart        # QuickJS engine + Dart↔JS bridge + plugin wrapper
│   └── plugin_manager.dart          # scan/load/enable/import/search/resolve plugins
├── downloader/
│   ├── segmented_downloader.dart    # parallel range download engine
│   ├── hls_downloader.dart          # HLS capture engine
│   └── download_manager.dart        # queue + persistence
└── ui/                              # screens (home, discover, search, details,
                                     #  downloads, plugins, settings, player)
assets/plugins/                      # bundled plugins (goldmines, ultra, pen, youtube, template)
test/                                # engine + downloader + UI tests
```

## Tests

```bash
flutter test
```

- `segmented_downloader_test` — byte-exact + speedup on a throttled server.
- `hls_downloader_test` — byte-exact segment capture.
- `plugin_engine_test` — loads a real plugin and drives it through the JS
  bridge against a local HTTP server.
- `widget_test` — design-system smoke tests.

## Notes

- Replace the shared TMDB key in `lib/core/config.dart` with your own free key
  from themoviedb.org.
- Downloads are yours: pick any folder in Settings. Files are saved under
  `.mp4` / `.ts` names you can rename freely.
