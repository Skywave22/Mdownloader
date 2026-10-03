import 'JsonX.dart';

class Video {
  String? title;
  String url;
  String quality;
  Map<String, String>? headers;
  List<Track>? subtitles;
  List<Track>? audios;
  Map<String, dynamic>? extraData;

  Video(
    this.title,
    this.url,
    this.quality, {
    this.headers,
    this.subtitles,
    this.audios,
    this.extraData,
  });

  factory Video.fromJson(Map<String, dynamic> json) {
    final title = json['title']?.toString().trim();
    final rawQuality = json['quality']?.toString().trim();
    final validTitle = (title != null && title != 'null' && title.isNotEmpty) ? title : null;
    final validQuality = (rawQuality != null && rawQuality != 'null' && rawQuality.isNotEmpty) ? rawQuality : null;

    var quality = validQuality ?? validTitle ?? 'Default';
    final videoTitle = validTitle ?? validQuality ?? 'Default';

    if (validTitle != null) {
      final titleLower = validTitle.toLowerCase();
      final qualityLower = quality.toLowerCase();
      if ((titleLower.contains('dub') && !qualityLower.contains('dub')) ||
          (titleLower.contains('sub') && !qualityLower.contains('sub'))) {
        quality = validTitle;
      }
    }

    return Video(
      videoTitle,
      (json['url'] ?? '').toString().trim(),
      quality,
      headers: normalizeHeaders(strMapOf(json['headers'])),
      subtitles: [
        for (final e in mapListOf(json['subtitles'])) Track.fromJson(e),
      ],
      audios: [
        for (final e in mapListOf(json['audios'])) Track.fromJson(e),
      ],
      extraData: json,
    );
  }

  factory Video.fromCs(Map<String, dynamic> json) {
    final title = json['title']?.toString().trim();
    final rawQuality = json['quality']?.toString().trim();
    final validTitle = (title != null && title != 'null' && title.isNotEmpty) ? title : null;
    final validQuality = (rawQuality != null && rawQuality != 'null' && rawQuality.isNotEmpty) ? rawQuality : null;

    var quality = validQuality ?? validTitle ?? 'Default';
    final videoTitle = validTitle ?? validQuality ?? 'Default';

    if (validTitle != null) {
      final titleLower = validTitle.toLowerCase();
      final qualityLower = quality.toLowerCase();
      if ((titleLower.contains('dub') && !qualityLower.contains('dub')) ||
          (titleLower.contains('sub') && !qualityLower.contains('sub'))) {
        quality = validTitle;
      }
    }

    return Video(
      videoTitle,
      (json['url'] ?? '').toString().trim(),
      quality,
      headers: normalizeHeaders(
        strMapOf(mapOf(json['extraData'])['allHeaders']),
      ),
      subtitles: [
        for (final e in mapListOf(json['subtitles'])) Track.fromJson(e),
      ],
      audios: [
        for (final e in mapListOf(json['audios'])) Track.fromJson(e),
      ],
      extraData: json,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'quality': quality,
        'headers': normalizeHeaders(headers),
        'subtitles': subtitles?.map((e) => e.toJson()).toList(),
        'audios': audios?.map((e) => e.toJson()).toList(),
        'extraData': extraData,
      };
}

class Track {
  String? file;
  String? label;

  Track({this.file, this.label});

  Track.fromJson(Map<String, dynamic> json) {
    file = json['file']?.toString().trim();
    label = json['label']?.toString().trim();
  }

  Map<String, dynamic> toJson() => {'file': file, 'label': label};
}

Map<String, String>? normalizeHeaders(Map<String, String>? headers) {
  if (headers == null) return null;

  final updated = Map<String, String>.from(headers);

  final refererKey = updated.keys.firstWhere(
    (k) => k.toLowerCase() == 'referer',
    orElse: () => '',
  );

  if (refererKey.isNotEmpty) {
    final value = updated[refererKey];
    if (value != null && !value.endsWith('/')) {
      updated[refererKey] = '$value/';
    }
  }

  return updated;
}