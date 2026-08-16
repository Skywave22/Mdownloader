import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_js/flutter_js.dart';

/// The JavaScript bridge injected into the QuickJS runtime once.
///
/// Exposes to every plugin:
///  - `sendMessage`/`__mdn_resolve`   (Dart <-> JS transport)
///  - `__mdn` helpers (http, sha256, md5, base64, storage, btoa/atob)
///  - `__mdn_invoke`                  (Dart calls a plugin function by name)
const String pluginBootstrapJs = r'''
var __mdn = (function () {
  var _pending = {};
  var _seq = 0;
  function _newId() { return 'p' + (++_seq); }
  function _call(channel, msg) {
    return new Promise(function (resolve, reject) {
      var id = _newId();
      _pending[id] = { resolve: resolve, reject: reject };
      sendMessage(channel, JSON.stringify(Object.assign({ __id: id }, msg || {})));
    });
  }
  return {
    resolve: function (id, resultJson, isError) {
      var p = _pending[id];
      if (!p) return;
      delete _pending[id];
      if (isError) p.reject(new Error(resultJson));
      else p.resolve(resultJson);
    },
    http: function (opts) { return _call('mdn_http', opts).then(JSON.parse); },
    sha256: function (s) { return sendMessage('mdn_sha256', JSON.stringify(String(s))); },
    md5: function (s) { return sendMessage('mdn_md5', JSON.stringify(String(s))); },
    b64encode: function (s) { return sendMessage('mdn_b64', JSON.stringify({ op: 'encode', data: String(s) })); },
    b64decode: function (s) { return sendMessage('mdn_b64', JSON.stringify({ op: 'decode', data: String(s) })); },
    storage_get: function (ns, key) { return sendMessage('mdn_storage', JSON.stringify({ ns: ns, op: 'get', key: String(key) })); },
    storage_set: function (ns, key, value) { sendMessage('mdn_storage', JSON.stringify({ ns: ns, op: 'set', key: String(key), value: String(value) })); }
  };
})();

function __mdn_resolve(id, resultJson, isError) { __mdn.resolve(id, resultJson, isError); }

function __mdn_get(path) {
  var parts = path.split('.');
  var t = (typeof globalThis !== 'undefined') ? globalThis : this;
  for (var i = 0; i < parts.length; i++) {
    if (t == null) return null;
    t = t[parts[i]];
  }
  return t;
}

function __mdn_invoke(path, argsJson, cbId) {
  var fn = __mdn_get(path);
  function done(result, error) {
    try { sendMessage('mdn_cb', JSON.stringify({ id: cbId, result: result, error: error })); }
    catch (e) { sendMessage('mdn_cb', JSON.stringify({ id: cbId, result: null, error: String(e) })); }
  }
  try {
    if (typeof fn !== 'function') { done(null, 'function not found: ' + path); return; }
    var args = JSON.parse(argsJson);
    var cb = function (res) { done(res, null); };
    args.push(cb);
    var r = fn.apply(null, args);
    if (r && typeof r.then === 'function') {
      r.then(function (res) { done(res == null ? { success: true, data: [] } : res, null); })
       .catch(function (e) { done(null, String(e && e.message ? e.message : e)); });
    }
  } catch (e) {
    done(null, String(e && e.message ? e.message : e));
  }
}

// ---- btoa / atob polyfills (QuickJS has no window.*) ----
var __mdn_b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function __mdn_btoa(str) {
  var bytes = [];
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    if (c < 0x80) bytes.push(c);
    else if (c < 0x800) { bytes.push(0xC0 | (c >> 6), 0x80 | (c & 63)); }
    else if (c < 0x10000) { bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63)); }
    else { bytes.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63)); }
  }
  var out = '';
  for (var i = 0; i < bytes.length; i += 3) {
    var b0 = bytes[i], b1 = i + 1 < bytes.length ? bytes[i + 1] : -1, b2 = i + 2 < bytes.length ? bytes[i + 2] : -1;
    out += __mdn_b64chars[b0 >> 2];
    out += __mdn_b64chars[((b0 & 3) << 4) | (b1 >= 0 ? (b1 >> 4) : 0)];
    out += b1 >= 0 ? __mdn_b64chars[((b1 & 15) << 2) | (b2 >= 0 ? (b2 >> 6) : 0)] : '=';
    out += b2 >= 0 ? __mdn_b64chars[b2 & 63] : '=';
  }
  return out;
}
function __mdn_atob(str) {
  str = String(str).replace(/=+$/, '');
  var bytes = [];
  for (var i = 0; i < str.length; i += 4) {
    var c1 = __mdn_b64chars.indexOf(str[i]);
    var c2 = __mdn_b64chars.indexOf(str[i + 1]);
    var c3 = str[i + 2] === undefined ? -1 : __mdn_b64chars.indexOf(str[i + 2]);
    var c4 = str[i + 3] === undefined ? -1 : __mdn_b64chars.indexOf(str[i + 3]);
    if (c1 < 0) continue;
    bytes.push((c1 << 2) | (c2 >> 4));
    if (c3 >= 0) bytes.push(((c2 & 15) << 4) | (c3 >> 2));
    if (c4 >= 0) bytes.push(((c3 & 3) << 6) | c4);
  }
  var out = '';
  for (var i = 0; i < bytes.length; i++) out += String.fromCharCode(bytes[i]);
  return out;
}
''';

/// Wraps a plugin source so it runs in its own namespace with the standard
/// helpers in scope, and its `getHome/search/load/loadStreams` functions are
/// auto-exported under a global namespace the engine can call.
String pluginWrapper(String ns, Map<String, dynamic> manifest, String source) {
  final safeNs = ns.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  final header = '''
(function () {
  var NS = ${jsonEncode(ns)};
  var manifest = ${jsonEncode(manifest)};
  var http_get = function (url, headers) {
    return __mdn.http({ method: 'GET', url: url, headers: headers || {} })
      .then(function (r) { if (r.error) throw new Error(r.error); return r.body; });
  };
  var http_post = function (url, headers, body) {
    return __mdn.http({ method: 'POST', url: url, headers: headers || {}, body: body == null ? '' : String(body) })
      .then(function (r) { if (r.error) throw new Error(r.error); return r.body; });
  };
  var http_request = function (opts) { return __mdn.http(opts || {}); };
  var fetch = http_request;
  var sha256 = __mdn.sha256;
  var md5 = __mdn.md5;
  var btoa = __mdn_btoa;
  var atob = __mdn_atob;
  var b64encode = __mdn.b64encode;
  var b64decode = __mdn.b64decode;
  var storage_get = function (key) { return __mdn.storage_get(NS, key); };
  var storage_set = function (key, value) { __mdn.storage_set(NS, key, value); };

  // ======================= plugin source =======================
''';
  final footer = '''

  // ======================= export =======================
  var _exports = {};
  if (typeof getHome === 'function') _exports.getHome = getHome;
  if (typeof search === 'function') _exports.search = search;
  if (typeof load === 'function') _exports.load = load;
  if (typeof loadStreams === 'function') _exports.loadStreams = loadStreams;
  globalThis['__mdn_plugin_$safeNs'] = _exports;
})();
''';
  return header + source + footer;
}

/// Thin wrapper around the QuickJS runtime: registers the Dart-side bridge
/// channels and provides `loadPlugin` / `invoke`.
class MdnEngine {
  final Directory storageDir;
  QuickJsRuntime2? _rt;
  final Map<String, Completer<dynamic>> _pending = {};
  int _seq = 0;

  MdnEngine({required this.storageDir});

  bool get isReady => _rt != null;

  void init() {
    if (_rt != null) return;
    final rt = QuickJsRuntime2();
    _rt = rt;
    rt.onMessage('mdn_http', _onHttp);
    rt.onMessage('mdn_sha256', (dynamic a) => crypto.sha256.convert(utf8.encode(a.toString())).toString());
    rt.onMessage('mdn_md5', (dynamic a) => crypto.md5.convert(utf8.encode(a.toString())).toString());
    rt.onMessage('mdn_b64', _onB64);
    rt.onMessage('mdn_storage', _onStorage);
    rt.onMessage('mdn_cb', _onCb);
    rt.evaluate(pluginBootstrapJs);
    _pump();
  }

  void _pump() {
    final rt = _rt;
    if (rt == null) return;
    for (var i = 0; i < 8; i++) {
      rt.executePendingJob();
    }
  }

  void dispose() {
    _rt?.dispose();
    _rt = null;
  }

  void loadPlugin(String ns, Map<String, dynamic> manifest, String source) {
    final rt = _rt;
    if (rt == null) throw StateError('engine not initialised');
    final r = rt.evaluate(pluginWrapper(ns, manifest, source));
    _pump();
    if (r.isError) throw Exception('plugin load error: ${r.stringResult}');
  }

  bool hasPlugin(String ns) {
    final rt = _rt;
    if (rt == null) return false;
    final safe = ns.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final r = rt.evaluate("typeof __mdn_plugin_$safe !== 'undefined'");
    return r.stringResult == 'true';
  }

  Future<dynamic> invoke(
    String ns,
    String fnName,
    List<dynamic> args, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    final rt = _rt;
    if (rt == null) return Future.error(StateError('engine not initialised'));
    final safe = ns.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final id = 'cb_${_seq++}';
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    final code =
        "__mdn_invoke('__mdn_plugin_$safe.$fnName', ${jsonEncode(jsonEncode(args))}, '$id')";
    rt.evaluate(code);
    _pump();
    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('$ns.$fnName timed out');
    });
  }

  void _onCb(dynamic args) {
    if (args is! Map) return;
    final id = args['id']?.toString();
    final c = _pending.remove(id);
    if (c == null) return;
    final err = args['error'];
    if (err != null) {
      c.completeError(err.toString());
    } else {
      c.complete(args['result']);
    }
  }

  // NOTE: must be synchronous void — returning a Future here makes the bridge
  // convert it into a JS Promise that QuickJS can garbage-collect while the
  // request is in flight.
  void _onHttp(dynamic args) {
    _doHttp(args);
  }

  Future<void> _doHttp(dynamic args) async {
    final m = (args is Map) ? args : const <String, dynamic>{};
    final id = m['__id']?.toString() ?? '';

    Future<void> respond(Map<String, dynamic> result) async {
      final rt = _rt;
      if (rt == null) return;
      final jsonStr = jsonEncode(result);
      rt.evaluate("__mdn_resolve('$id', ${jsonEncode(jsonStr)}, ${result['error'] != null})");
      _pump();
    }

    try {
      final method = (m['method'] ?? 'GET').toString().toUpperCase();
      final url = (m['url'] ?? '').toString();
      final rawHeaders = (m['headers'] is Map) ? (m['headers'] as Map) : const {};
      final body = m['body'];
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      try {
        final req = await client
            .openUrl(method, Uri.parse(url))
            .timeout(const Duration(seconds: 12));
        final headers = <String, String>{};
        rawHeaders.forEach((k, v) {
          if (v != null) headers[k.toString()] = v.toString();
        });
        if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
          headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125.0.0.0 Safari/537.36';
        }
        headers.forEach((k, v) => req.headers.set(k, v));
        if (body != null && (method == 'POST' || method == 'PUT' || method == 'PATCH')) {
          req.add(utf8.encode(body.toString()));
        }
        final res = await req.close().timeout(const Duration(seconds: 25));
        final bytes = <int>[];
        await for (final chunk in res) {
          bytes.addAll(chunk);
        }
        await respond({'status': res.statusCode, 'body': utf8.decode(bytes, allowMalformed: true)});
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      await respond({'status': 0, 'body': '', 'error': e.toString()});
    }
  }

  String _onB64(dynamic args) {
    final m = (args is Map) ? args : const <String, dynamic>{};
    final op = (m['op'] ?? 'encode').toString();
    final data = (m['data'] ?? '').toString();
    try {
      if (op == 'decode') return utf8.decode(base64.decode(data), allowMalformed: true);
      return base64.encode(utf8.encode(data));
    } catch (_) {
      return '';
    }
  }

  String _onStorage(dynamic args) {
    final m = (args is Map) ? args : const <String, dynamic>{};
    final ns = (m['ns'] ?? '').toString();
    final op = (m['op'] ?? 'get').toString();
    final key = (m['key'] ?? '').toString();
    if (ns.isEmpty) return '';
    final safe = ns.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final file = File('${storageDir.path}${Platform.pathSeparator}$safe.json');
    try {
      Map<String, dynamic> data = {};
      if (file.existsSync()) {
        try {
          data = (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>();
        } catch (_) {}
      }
      if (op == 'get') return (data[key] ?? '').toString();
      data[key] = (m['value'] ?? '').toString();
      file.writeAsStringSync(jsonEncode(data));
      return 'ok';
    } catch (_) {
      return '';
    }
  }
}
