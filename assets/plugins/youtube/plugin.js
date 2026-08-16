// =============================================================================
//  MDownloader plugin — YouTube (Hindi Dubbed)
//  Reference implementation. See PLUGINS.md for the full plugin API.
//
//  The app injects these helpers into every plugin (no imports needed):
//    http_get(url, headers?)          -> Promise<response body string>
//    http_post(url, headers?, body)   -> Promise<response body string>
//    http_request({method,url,headers,body}) -> Promise<{status,body,headers,error}>
//    sha256(s) / md5(s)               -> hex string
//    btoa(s) / atob(s) / b64encode(s) / b64decode(s)
//    storage_get(key) / storage_set(key, value)
//    manifest                         -> the plugin.json object
//    console.log / warn / error
//
//  Export by simply defining these functions at the top level (the app
//  auto-detects them):
//    getHome(cb)     -> cb({success, data:{Category:[items]}})
//    search(q, cb)   -> cb({success, data:[items]})
//    load(url, cb)   -> cb({success, data: item})
//    loadStreams(url, cb) -> cb({success, data:[streams]})
//
//  stream = {url, label, kind:'direct'|'hls', headers:{...}}
// =============================================================================

var KEY = 'AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w';
var BASE = 'https://www.youtube.com/youtubei/v1/';

var WEB_CTX = { context: { client: { clientName: 'WEB', clientVersion: '2.20260811.07.00', hl: 'en', gl: 'US' } } };
var ANDROID_CTX = {
  context: {
    client: {
      clientName: 'ANDROID',
      clientVersion: '21.02.35',
      androidSdkVersion: 30,
      userAgent: 'com.google.android.youtube/21.02.35 (Linux; U; Android 11) gzip',
      osName: 'Android',
      osVersion: '11',
      hl: 'en',
      gl: 'US'
    }
  }
};

function innertube(endpoint, body, ua) {
  return http_post(
    BASE + endpoint + '?key=' + KEY + '&prettyPrint=false',
    { 'Content-Type': 'application/json', 'User-Agent': ua || 'Mozilla/5.0' },
    JSON.stringify(body)
  ).then(function (t) {
    if (!t) throw new Error('empty InnerTube response');
    return JSON.parse(t);
  });
}

// Walk a JSON response and collect video ids (videoRenderer + lockupViewModel).
function searchIds(query) {
  return innertube('search', Object.assign({}, WEB_CTX, { query: query })).then(function (j) {
    var ids = [];
    (function walk(o) {
      if (o == null || typeof o !== 'object') return;
      if (Array.isArray(o)) { for (var i = 0; i < o.length; i++) walk(o[i]); return; }
      var v = o.videoRenderer;
      if (v && typeof v.videoId === 'string' && ids.indexOf(v.videoId) < 0) ids.push(v.videoId);
      var lv = o.lockupViewModel;
      if (lv && typeof lv.contentId === 'string' && lv.contentType === 'LOCKUP_CONTENT_TYPE_VIDEO' && ids.indexOf(lv.contentId) < 0) ids.push(lv.contentId);
      var keys = Object.keys(o);
      for (var k = 0; k < keys.length; k++) walk(o[keys[k]]);
    })(j);
    return ids;
  });
}

// ANDROID client returns progressive MP4 download URLs even from datacenter IPs
// where the WEB client is gated. Also surface the WEB merged-HLS manifest.
function streamsFor(videoId) {
  return innertube('player', Object.assign({}, ANDROID_CTX, { videoId: videoId }), ANDROID_CTX.context.client.userAgent)
    .then(function (j) {
      var ps = j.playabilityStatus;
      if (!ps || (ps.status !== 'OK' && ps.status !== 'CONTENT_CHECK_REQUIRED')) return [];
      var sd = j.streamingData || {};
      var out = [];
      (sd.formats || []).forEach(function (f) {
        if (f && typeof f.url === 'string' && (f.mimeType || '').indexOf('video/mp4') >= 0) {
          var label;
          if (f.itag === 22) label = '720p (MP4)';
          else if (f.itag === 18) label = '360p (MP4)';
          else label = (f.height || f.itag) + 'p (MP4)';
          out.push({ url: f.url, label: label, kind: 'direct' });
        }
      });
      if (typeof sd.hlsManifestUrl === 'string' && sd.hlsManifestUrl) {
        out.push({ url: sd.hlsManifestUrl, label: 'HLS (auto)', kind: 'hls', headers: { 'User-Agent': 'Mozilla/5.0', 'Referer': 'https://www.youtube.com/' } });
      }
      return out;
    });
}

// Resolve download links for a title. `url` is a JSON string the app passes:
// {tmdbId, title, year, mediaType:'movie'|'tv', season?, episode?}
function loadStreams(url, cb) {
  try {
    var m = JSON.parse(String(url || '{}'));
    var query;
    if (m.mediaType === 'tv') {
      query = m.title + ' season ' + (m.season || 1) + ' episode ' + (m.episode || 1) + ' hindi dubbed';
    } else {
      query = m.title + (m.year ? ' ' + m.year : '') + ' full movie hindi dubbed';
    }
    searchIds(query).then(function (ids) {
      var jobs = [];
      for (var i = 0; i < Math.min(ids.length, 3); i++) {
        jobs.push(streamsFor(ids[i]).catch(function () { return []; }));
      }
      Promise.all(jobs).then(function (groups) {
        var streams = [];
        groups.forEach(function (g) { streams = streams.concat(g); });
        var seen = {}, out = [];
        streams.forEach(function (s) {
          if (s && s.url && !seen[s.url]) { seen[s.url] = 1; out.push(s); }
        });
        cb({ success: true, data: out });
      }).catch(function (e) { cb({ success: false, message: String(e) }); });
    }).catch(function (e) { cb({ success: false, message: String(e) }); });
  } catch (e) {
    cb({ success: false, message: String(e && e.message ? e.message : e) });
  }
}

function search(query, cb) {
  if (!query) { cb({ success: true, data: [] }); return; }
  searchIds(query).then(function (ids) {
    cb({
      success: true,
      data: ids.slice(0, 20).map(function (id) {
        return {
          title: 'YouTube: ' + id,
          url: JSON.stringify({ v: id }),
          posterUrl: 'https://i.ytimg.com/vi/' + id + '/hqdefault.jpg',
          type: 'movie'
        };
      })
    });
  }).catch(function (e) { cb({ success: false, message: String(e) }); });
}
