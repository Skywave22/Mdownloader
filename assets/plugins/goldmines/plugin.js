// =============================================================================
//  MDownloader plugin — Goldmines (Hindi Dubbed Movies & Series)
//
//  Goldmines is the largest official Hindi-dubbed network on YouTube
//  (South-Indian blockbusters + dubbed serials). This plugin searches their
//  channels via the InnerTube API and resolves direct MP4 (360p/720p) plus HLS
//  download links — no ffmpeg, no yt-dlp, instant links.
//
//  Exports: search(query, cb)  and  loadStreams(url, cb)
// =============================================================================

var KEY = 'AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w';
var BASE = 'https://www.youtube.com/youtubei/v1/';
var CHANNEL = 'Goldmines';
var HINT = 'hindi dubbed';

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

function textOf(t) {
  if (!t) return '';
  if (typeof t === 'string') return t;
  if (t.runs && t.runs.length) return t.runs.map(function (r) { return r.text || ''; }).join('');
  if (t.simpleText) return t.simpleText;
  if (t.content) return t.content;
  return '';
}

function thumbOf(t) {
  try {
    if (t && t.thumbnails && t.thumbnails.length) return t.thumbnails[t.thumbnails.length - 1].url || '';
    if (t && t.sources && t.sources.length) return t.sources[0].url || '';
  } catch (e) {}
  return '';
}

// Search YouTube and collect {id, title, thumb} for every video result.
function searchItems(query) {
  return innertube('search', Object.assign({}, WEB_CTX, { query: query })).then(function (j) {
    var out = [];
    function add(id, title, thumb) {
      if (typeof id !== 'string' || !id) return;
      for (var i = 0; i < out.length; i++) if (out[i].id === id) return;
      out.push({ id: id, title: title || '', thumb: thumb || '' });
    }
    (function walk(o) {
      if (o == null || typeof o !== 'object') return;
      if (Array.isArray(o)) { for (var i = 0; i < o.length; i++) walk(o[i]); return; }
      var v = o.videoRenderer;
      if (v && typeof v.videoId === 'string') {
        add(v.videoId, textOf(v.title), thumbOf(v.thumbnail));
      }
      var lv = o.lockupViewModel;
      if (lv && typeof lv.contentId === 'string' && lv.contentType === 'LOCKUP_CONTENT_TYPE_VIDEO') {
        var m = (lv.metadata && lv.metadata.lockupMetadataViewModel) || {};
        var img = (lv.contentImage && lv.contentImage.thumbnailViewModel && lv.contentImage.thumbnailViewModel.image) || null;
        add(lv.contentId, textOf(m.title), thumbOf(img));
      }
      var keys = Object.keys(o);
      for (var k = 0; k < keys.length; k++) walk(o[keys[k]]);
    })(j);
    return out;
  });
}

// ANDROID client returns progressive MP4 download URLs from anywhere; also
// surface the merged-HLS manifest when available.
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

// url is a JSON string: either {v:'<videoId>'} (instant) or
// {tmdbId, title, year, mediaType, season?, episode?} (search by title).
function loadStreams(url, cb) {
  try {
    var m = JSON.parse(String(url || '{}'));
    if (m && m.v) {
      streamsFor(m.v).then(function (s) { cb({ success: true, data: s }); })
        .catch(function (e) { cb({ success: false, message: String(e) }); });
      return;
    }
    var query;
    if (m.mediaType === 'tv') {
      query = m.title + ' season ' + (m.season || 1) + ' episode ' + (m.episode || 1) + ' ' + HINT + ' ' + CHANNEL;
    } else {
      query = m.title + (m.year ? ' ' + m.year : '') + ' full movie ' + HINT + ' ' + CHANNEL;
    }
    searchItems(query).then(function (items) {
      var jobs = items.slice(0, 3).map(function (it) {
        return streamsFor(it.id).catch(function () { return []; });
      });
      Promise.all(jobs).then(function (groups) {
        var seen = {}, out = [];
        groups.forEach(function (g) {
          g.forEach(function (s) {
            if (s && s.url && !seen[s.url]) { seen[s.url] = 1; out.push(s); }
          });
        });
        cb({ success: true, data: out });
      }).catch(function (e) { cb({ success: false, message: String(e) }); });
    }).catch(function (e) { cb({ success: false, message: String(e) }); });
  } catch (e) {
    cb({ success: false, message: String(e && e.message ? e.message : e) });
  }
}

function search(query, cb) {
  var q = String(query || '').trim();
  if (!q) { cb({ success: true, data: [] }); return; }
  searchItems(q + ' ' + HINT + ' ' + CHANNEL).then(function (items) {
    cb({
      success: true,
      data: items.slice(0, 24).map(function (it) {
        return {
          title: it.title || ('YouTube · ' + it.id),
          url: JSON.stringify({ v: it.id }),
          posterUrl: it.thumb || '',
          type: 'movie'
        };
      })
    });
  }).catch(function (e) { cb({ success: false, message: String(e) }); });
}
