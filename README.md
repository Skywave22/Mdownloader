# MDownloader

**TMDB catalog → scrape multiple sources → download any movie or series with a real parallel segmented download engine.**

One Flutter codebase builds to **Android APK** and **Windows EXE**; GitHub Actions
builds both and attaches them to a tagged GitHub Release.

## Features

- **TMDB catalog** — trending, popular movies/series, search, full details with seasons & episodes.
- **Multi-source scraping** — pluggable scraper architecture. Each title is resolved
  across all registered sources in parallel and every downloadable copy is listed.
  - ✅ YouTube (official channels, Hindi-dubbed movies/episodes — InnerTube API)
  - ⏳ more sources (Hindi DDL sites, English embeds) are added incrementally.
- **Real segmented downloader** — splits a file into chunks and downloads them with
  8 parallel HTTP range requests (the same technique IDM/aria2 use), with per-chunk
  resume, retry and pause/resume. Verified in tests: **~6× speedup** on a
  per-connection-throttled server, byte-exact output.
  > Honest note: parallel segments multiply throughput only up to your actual
  > internet bandwidth. No software can exceed your ISP line speed.
- **Download manager** — queue, pause/resume/cancel, live speed & progress,
  persisted across restarts, completed files playable in the built-in player (Android).

## Build locally

```bash
flutter create . --platforms android,windows --project-name mdownloader
flutter pub get
flutter run            # debug
flutter build apk --release                 # Android
flutter build windows --release             # Windows
```

## Releases (GitHub Actions)

- Push a tag like `v0.1.0` → builds APK (Ubuntu) + EXE (Windows), then publishes
  `app-release.apk` and `mdownloader-windows-x64.zip` to the release.
- Any push/`workflow_dispatch` builds both artifacts without releasing.

## Project layout

```
lib/
├── main.dart                     # app shell
├── core/config.dart              # TMDB key + downloader defaults
├── models/media.dart             # TMDB-backed media/season/episode models
├── services/
│   ├── tmdb_service.dart         # search / trending / popular / details
│   ├── locator.dart              # app singletons
│   └── scraper/
│       ├── scraper.dart          # SourceScraper interface + ScrapeResult
│       ├── youtube_scraper.dart  # InnerTube search + player → MP4/HLS links
│       └── scraper_registry.dart # runs all scrapers in parallel
├── downloader/
│   ├── segmented_downloader.dart # pure-Dart parallel range download engine
│   └── download_manager.dart     # queue + persistence + progress
└── ui/
    ├── home_page.dart            # trending/popular rows
    ├── search_page.dart          # TMDB search grid
    ├── details_page.dart         # details + "find download links"
    ├── downloads_page.dart       # queue UI
    └── player_page.dart          # built-in local-file player
```

## Notes

- Replace the shared TMDB key in `lib/core/config.dart` with your own free key
  from themoviedb.org to be independent.
- The built-in player is Android-first; on Windows downloaded files can be opened
  with any external player from the Documents/downloads folder.
