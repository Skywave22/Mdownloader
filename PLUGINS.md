# MDownloader — Plugin Guide

MDownloader uses a **plugin system** to find download links. The app itself is a
catalog (TMDB) + download manager; each *site* is a plugin. Plugins are small
JavaScript files the app loads at runtime — add a plugin, and that site's links
show up when you tap **Find downloads**.

## What a plugin is

A plugin is a folder (or a `.zip`/`.sky` containing) two files:

```
my-plugin/
├── plugin.json    ← metadata
└── plugin.js      ← the scraping logic
```

## plugin.json

```json
{
  "packageName": "com.example.mysite",   // unique id (dots allowed)
  "name": "My Site",
  "version": 1,
  "baseUrl": "https://mysite.com",
  "description": "Finds direct/HLS links on mysite.com."
}
```

## plugin.js — the 4 functions

Just define these functions at the top level; the app auto-detects them (no
`export`, no `globalThis` needed):

| Function | Purpose | Required |
|---|---|---|
| `loadStreams(url, cb)` | resolve downloadable links for a title | ✅ yes |
| `search(query, cb)` | search the site | optional |
| `getHome(cb)` | homepage categories | optional |
| `load(url, cb)` | details for one of your items | optional |

Every function receives a callback and must call it exactly once:

```js
cb({ success: true, data: ... });
cb({ success: false, message: 'error text' });
```

### loadStreams — the important one

The app calls it with a **JSON string** describing the title:

```json
{ "tmdbId": 123, "title": "KGF Chapter 2", "year": 2022,
  "mediaType": "movie", "season": null, "episode": null }
```

Parse it, scrape the site, and return every downloadable copy:

```js
function loadStreams(url, cb) {
  try {
    var m = JSON.parse(String(url || '{}'));
    http_get('https://mysite.com/search?q=' + encodeURIComponent(m.title))
      .then(function (html) {
        // ... parse `html` to find the real file URL(s) ...
        cb({ success: true, data: [
          { url: 'https://cdn.mysite.com/movie.mp4',  label: '1080p (MP4)', kind: 'direct' },
          { url: 'https://cdn.mysite.com/movie.m3u8', label: 'HLS',          kind: 'hls',
            headers: { 'Referer': 'https://mysite.com/' } }
        ]});
      })
      .catch(function (e) { cb({ success: false, message: String(e) }); });
  } catch (e) {
    cb({ success: false, message: String(e) });
  }
}
```

**stream object:**

| field | values |
|---|---|
| `url` | the download URL (required) |
| `label` | human label, e.g. `"1080p (MP4)"` |
| `kind` | `"direct"` (a file → segmented downloader) or `"hls"` (an .m3u8 → HLS downloader) |
| `headers` | optional `{ "Referer": "…", "User-Agent": "…" }` to send with every request |

### search / getHome — item shape

```js
{ title: "KGF Chapter 2", url: "https://mysite.com/movie/123",
  posterUrl: "https://img/...jpg", type: "movie" | "series", year: 2022 }
```

## Helpers available to every plugin

| Helper | Returns |
|---|---|
| `http_get(url, headers?)` | `Promise<body string>` |
| `http_post(url, headers?, body)` | `Promise<body string>` |
| `http_request({method,url,headers,body})` | `Promise<{status, body, headers, error}>` |
| `sha256(s)` / `md5(s)` | hex string |
| `btoa(s)` / `atob(s)` | base64 (binary string) |
| `b64encode(s)` / `b64decode(s)` | utf8-safe base64 |
| `storage_get(key)` / `storage_set(key, value)` | persistent per-plugin storage |
| `manifest` | your `plugin.json` object |
| `console.log / warn / error` | logs to the app console |

All helpers are async where sensible — use `async`/`await` freely, or Promise
chains. The engine also supports `fetch` (an alias of `http_request`).

## Install a plugin

1. **Folder** — drop the folder into the app's `plugins/` directory:
   - Windows: `<folder with MDownloader.exe>/plugins/`
   - Android: app documents folder `.../plugins/`
2. **In the app** — Plugins tab → **Install plugin** → pick a `.zip` or `.sky`
   containing `plugin.json` + `plugin.js`.
3. Enable/disable or delete plugins from the Plugins tab.

## Bundled examples

- `assets/plugins/youtube/` — real working plugin (InnerTube API → MP4/HLS).
- `assets/plugins/template/` — commented starter to copy for your own site.

## Notes

- Plugins run in an embedded QuickJS engine (no `window`, no DOM). Use
  `http_*` helpers for network and parse HTML with string/regex, or request
  JSON APIs directly.
- The app passes TMDB context in `loadStreams` so plugins can match by title
  or TMDB id — you don't need your own catalog.
