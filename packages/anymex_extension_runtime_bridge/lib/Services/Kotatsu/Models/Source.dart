import '../../../Models/JsonX.dart';
import '../../../Models/Source.dart';

class KotatsuSource extends Source {
  String? jarName;
  String? pkgName;

  KotatsuSource({
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
    super.hasUpdate,
    super.supportsLatest = false,
    super.supportsPopular = false,
    this.jarName,
    this.pkgName,
  });

  factory KotatsuSource.fromJson(Map<String, dynamic> json) {
    return KotatsuSource(
      id: strOf(json['id']),
      name: strOf(json['name']),
      baseUrl: strOf(json['baseUrl']),
      lang: strOf(json['lang']),
      iconUrl: strOf(json['iconUrl']),
      isNsfw: boolOf(json['isNsfw']),
      version: strOf(json['version']),
      versionLast: strOf(json['versionLast']),
      repo: strOf(json['repo']),
      hasUpdate: boolOr(json['hasUpdate']),
      supportsLatest: boolOr(json['supportsLatest']),
      supportsPopular: boolOr(json['supportsPopular']),
      itemType: Source.itemTypeOf(json['itemType']),
      jarName: strOf(json['jarName']),
      pkgName: strOf(json['pkgName']),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['jarName'] = jarName;
    map['pkgName'] = pkgName;
    return map;
  }
}
