import 'DMedia.dart';

class Pages {
  List<DMedia> list;
  bool hasNextPage;

  Pages({required this.list, this.hasNextPage = false});

  factory Pages.fromJson(Map<String, dynamic> json) {
    // The runtime host and the desktop adapter disagree on the envelope:
    // `{list: [...]}` is canonical, but bare-ish shapes show up in the wild.
    final dynamic rawList = json['list'] ?? json['results'] ?? json['items'];
    List<DMedia> parsed;
    if (rawList is List) {
      // One malformed entry must not take down the whole page.
      parsed = <DMedia>[];
      for (final e in rawList) {
        if (e is! Map) continue;
        try {
          parsed.add(DMedia.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {
          // skip just this entry
        }
      }
    } else {
      parsed = [];
    }
    return Pages(
      list: parsed,
      // Unknown pagination should not stop after page 1 - thin pages used to
      // leave feeds at "1-2 items" forever. Assume more when the page came
      // back with a reasonable amount of entries.
      hasNextPage: json['hasNextPage'] ?? (parsed.length >= 8),
    );
  }

  Map<String, dynamic> toJson() => {
        'list': list.map((v) => v.toJson()).toList(),
        'hasNextPage': hasNextPage,
      };
}
