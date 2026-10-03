import '../../../Models/JsonX.dart';
import '../../../Models/Source.dart';

class CloudStreamSource extends Source {
  String? internalName;
  String? pluginUrl;
  String? jarUrl;
  bool hasSettings;

  CloudStreamSource({
    super.id,
    super.name,
    super.baseUrl,
    super.lang,
    super.isNsfw,
    super.iconUrl,
    super.version,
    super.versionLast,
    super.itemType,
    super.repo,
    super.managerId,
    super.hasUpdate,
    super.supportsLatest = false,
    super.supportsPopular = false,
    super.author,
    this.internalName,
    this.pluginUrl,
    this.jarUrl,
    this.hasSettings = false,
  });

  factory CloudStreamSource.fromJson(Map<String, dynamic> json) {
    final language = strOf(json['language']);
    final rawVersion = strOf(json['version']) ?? strOf(json['versionLast']);
    final versionStr = (rawVersion != null && rawVersion.isNotEmpty) ? rawVersion : "1.0.0";
    final name = strOf(json['name']);
    final internalName = strOf(json['internalName']) ?? name;

    return CloudStreamSource(
      id: strOf(json['id'])?.toLowerCase() ?? name?.toLowerCase() ?? '',
      name: name,
      baseUrl: strOf(json['url']),
      lang: (language == null || language.trim().isEmpty) ? 'ALL' : language,
      iconUrl: strOf(json['iconUrl']),
      isNsfw: boolOr(json['isNsfw']),
      version: versionStr,
      versionLast: strOf(json['versionLast']) ?? versionStr,
      repo: strOf(json['repo']),
      managerId: 'cloudstream',
      hasUpdate: boolOr(json['hasUpdate']),
      supportsLatest: boolOr(json['supportsLatest']),
      supportsPopular: boolOr(json['supportsPopular']),
      itemType: ItemType.anime,
      author: Source.authorNameFrom(json['author'] ?? json['authors']),
      jarUrl: strOf(json['jarUrl']) ?? strOf(json['jar']),
      internalName: internalName,
      pluginUrl: strOf(json['pluginUrl']) ?? strOf(json['plugin']) ?? strOf(json['url']),
      hasSettings: json['hasSettings'] as bool? ?? false,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['internalName'] = internalName;
    map['plugin'] = pluginUrl;
    return map;
  }

  @override
  String get uniqueId => '${id}_$internalName';
}
