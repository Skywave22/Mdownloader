import 'JsonX.dart';

class Source {
  String? id;
  String? name;
  String? baseUrl;
  String? lang;
  bool? isNsfw;
  String? iconUrl;
  String? version;
  String? versionLast;
  ItemType? itemType;
  String? repo;
  String? managerId;
  bool? hasUpdate;
  bool? isPrivate;
  bool? supportsLatest;
  bool? supportsPopular;

  /// The extension's developer, when the manifest declares one. Used to
  /// group a repo's extensions by author in the manager UI.
  String? author;

  Source({
    this.id = '',
    this.name = '',
    this.baseUrl = '',
    this.lang = '',
    this.iconUrl = '',
    this.isNsfw = false,
    this.version = "0.0.1",
    this.versionLast = "0.0.1",
    this.itemType = ItemType.manga,
    this.repo,
    this.managerId,
    this.hasUpdate = false,
    this.isPrivate,
    this.supportsLatest = false,
    this.supportsPopular = false,
    this.author,
  });

  Source.fromJson(Map<String, dynamic> json) {
    baseUrl = strOf(json['baseUrl']) ?? strOf(json['site']);
    iconUrl = strOf(json['iconUrl']);
    id = strOf(json['id']) ?? '';
    isNsfw = boolOr(json['isNsfw'] ?? json['nsfw']);
    lang = strOf(json['lang']);
    name = strOf(json['name']);
    version = strOf(json['version']);
    versionLast = strOf(json['versionLast']) ?? version;
    repo = strOf(json['repo']);
    managerId = strOf(json['managerId']);
    hasUpdate = boolOr(json['hasUpdate']);
    isPrivate = boolOf(json['isPrivate']) ??
        (boolOf(json['isShared']) != null ? !boolOr(json['isShared']) : null);
    supportsLatest = boolOr(json['supportsLatest']);
    supportsPopular = boolOr(json['supportsPopular']);
    author = Source.authorNameFrom(json['author'] ?? json['authors']);

    final isLnReader = json['site'] != null && json['url'] != null && json['sourceCodeLanguage'] == null;
    if (isLnReader) {
      itemType = ItemType.novel;
    } else {
      itemType = Source.itemTypeOf(json['itemType']);
    }
  }

  /// Manifests disagree: an index, a name string, or absent. Accept all.
  static ItemType itemTypeOf(dynamic raw) {
    final index = intOf(raw);
    if (index != null && index >= 0 && index < ItemType.values.length) {
      return ItemType.values[index];
    }
    final name = strOf(raw)?.toLowerCase();
    if (name != null) {
      for (final t in ItemType.values) {
        if (t.name == name) return t;
      }
    }
    return ItemType.manga;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'lang': lang,
        'iconUrl': iconUrl,
        'isNsfw': isNsfw,
        'version': version,
        'versionLast': versionLast,
        'itemType': itemType?.index ?? 0,
        'repo': repo,
        'managerId': managerId,
        'hasUpdate': hasUpdate,
        'isPrivate': isPrivate,
        'supportsLatest': supportsLatest,
        'supportsPopular': supportsPopular,
        'author': author,
      };

  /// Manifests disagree on the author's shape: a plain string, an
  /// `{name, icon}` object, or a list of either. Accept all.
  static String? authorNameFrom(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return strOf(raw['name'] ?? raw['author']);
    if (raw is List) {
      final names = <String>[];
      for (final e in raw) {
        final s = authorNameFrom(e);
        if (s != null && s.trim().isNotEmpty) names.add(s);
      }
      return names.isEmpty ? null : names.join(', ');
    }
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  String get uniqueId => id ?? '';
}

enum ItemType {
  manga,
  anime,
  novel;

  @override
  String toString() {
    switch (this) {
      case ItemType.manga:
        return 'Manga';
      case ItemType.anime:
        return 'Anime';
      case ItemType.novel:
        return 'Novel';
    }
  }
}
