// =============================================================================
//  MDownloader — TEMPLATE PLUGIN
//
//  Copy this whole folder (plugin.json + plugin.js), rename it, edit
//  plugin.json, and implement the functions below. The app auto-detects the
//  four functions — you do NOT need to export anything manually.
//
//  AVAILABLE HELPERS (injected by the app):
//    http_get(url, headers?)          -> Promise<body string>
//    http_post(url, headers?, body)   -> Promise<body string>
//    http_request({method,url,headers,body}) -> Promise<{status,body,headers,error}>
//    sha256(s) / md5(s)               -> hex string
//    btoa(s) / atob(s)                -> base64 (binary string)
//    b64encode(s) / b64decode(s)      -> utf8-safe base64
//    storage_get(key) / storage_set(key, value)   -> persistent per-plugin
//    manifest                         -> your plugin.json object
//    console.log / warn / error
// =============================================================================

// OPTIONAL — homepage categories. Each item:
//   {title, url, posterUrl, type:'movie'|'series', year?}
function getHome(cb) {
  cb({
    success: true,
    data: {
      'Example': [
        {
          title: 'Example title',
          url: 'https://example.com/movie/1',
          posterUrl: 'https://example.com/poster.jpg',
          type: 'movie'
        }
      ]
    }
  });
}

// OPTIONAL — search. Return items like getHome.
function search(query, cb) {
  cb({ success: true, data: [] });
}

// OPTIONAL — details for an item URL your plugin produced.
function load(url, cb) {
  cb({ success: false, message: 'not implemented' });
}

// REQUIRED — resolve downloadable links for a title.
//
// `url` is a JSON string the app passes:
//   { tmdbId, title, year, mediaType:'movie'|'tv', season?, episode? }
//
// Return every downloadable copy. Each stream:
//   { url, label, kind:'direct'|'hls', headers:{...} }
//   kind 'direct' = a file URL (uses the segmented downloader)
//   kind 'hls'    = an .m3u8 playlist (uses the HLS downloader)
function loadStreams(url, cb) {
  try {
    var m = JSON.parse(String(url || '{}'));
    // --- example: fetch the site's page and parse a link out of it ---
    // var html = await http_get('https://mysite.com/search?q=' + encodeURIComponent(m.title));
    // ... parse ...
    // cb({ success: true, data: [
    //   { url: 'https://cdn.example.com/movie.mp4', label: '1080p (MP4)', kind: 'direct' },
    //   { url: 'https://cdn.example.com/movie.m3u8', label: 'HLS', kind: 'hls', headers: {'Referer':'https://mysite.com/'} }
    // ]});

    // no results yet — this is a template
    cb({ success: true, data: [] });
  } catch (e) {
    cb({ success: false, message: String(e && e.message ? e.message : e) });
  }
}
