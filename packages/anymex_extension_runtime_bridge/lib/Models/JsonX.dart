/// Tolerant JSON coercion.
///
/// Manifests and runtime payloads disagree wildly on shapes: strings arrive
/// as one-element lists, numbers as strings, flags as 0/1, objects as
/// `{name: ...}` maps. Every parser in this package routes raw JSON through
/// these helpers so one odd field can never crash a repository add or a
/// details fetch ("type 'List<dynamic>' is not a subtype of type 'String'").
library;

/// String from anything: numbers and flags stringify, lists join their
/// elements, maps prefer name/url/value/title.
String? strOf(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  if (v is List) {
    final parts = <String>[];
    for (final e in v) {
      final s = strOf(e);
      if (s != null && s.trim().isNotEmpty) parts.add(s);
    }
    return parts.isEmpty ? null : parts.join(', ');
  }
  if (v is Map) {
    return strOf(v['name'] ?? v['url'] ?? v['value'] ?? v['title']);
  }
  return v.toString();
}

/// [strOf] with a non-null fallback.
String strOr(dynamic v, [String fallback = '']) => strOf(v) ?? fallback;

/// String list from a list, a single value, or a comma-separated string
/// (scraper genres commonly arrive as one `"Action, Drama"` string).
List<String> strListOr(dynamic v, {List<String> fallback = const []}) {
  if (v == null) return fallback;
  if (v is List) {
    final out = <String>[];
    for (final e in v) {
      final s = strOf(e);
      if (s != null && s.trim().isNotEmpty) out.add(s);
    }
    return out.isEmpty ? fallback : out;
  }
  final s = strOf(v);
  if (s == null || s.trim().isEmpty) return fallback;
  return [
    for (final part in s.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

/// Map with string values (headers) from any map-ish payload.
Map<String, String> strMapOf(dynamic v) {
  if (v is! Map) return const {};
  final out = <String, String>{};
  v.forEach((key, value) {
    final k = strOf(key);
    if (k != null && k.isNotEmpty) out[k] = strOf(value) ?? '';
  });
  return out;
}

/// Map with dynamic values (rule trees, extra data).
Map<String, dynamic> mapOf(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

/// Bool from bool, 0/1 numbers, or common strings; null when unparseable.
bool? boolOf(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return null;
}

/// [boolOf] with a non-null fallback.
bool boolOr(dynamic v, [bool fallback = false]) => boolOf(v) ?? fallback;

/// Int from int, double, or numeric string; null when unparseable.
int? intOf(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

/// List from a list; a single element wraps itself; anything else is empty.
List<dynamic> listOf(dynamic v) {
  if (v == null) return const [];
  if (v is List) return v;
  return [v];
}

/// Map list for payload arrays whose entries may be loosely typed.
List<Map<String, dynamic>> mapListOf(dynamic v) {
  final out = <Map<String, dynamic>>[];
  for (final e in listOf(v)) {
    if (e is Map) out.add(Map<String, dynamic>.from(e));
  }
  return out;
}
