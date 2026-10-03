import 'JsonX.dart';

class DEpisode {
  String? url;
  String? name;
  String? dateUpload;
  String? scanlator;
  String? thumbnail;
  String? description;
  String? memo;
  bool? filler;
  String episodeNumber;
  Map<String, String>? sortMap;

  DEpisode({
    this.url,
    this.name,
    this.dateUpload,
    this.scanlator,
    this.thumbnail,
    this.description,
    this.memo,
    this.filler,
    this.sortMap,
    required this.episodeNumber,
  });

  factory DEpisode.fromJson(Map<String, dynamic> json) {
    double? episodeNum =
        double.tryParse(json['episodeNumber']?.toString() ?? '') ??
            double.tryParse(json['episode_number']?.toString() ?? '');

    String episodeStr;
    if (episodeNum != null) {
      episodeStr = episodeNum == episodeNum.toInt()
          ? episodeNum.toInt().toString()
          : episodeNum.toString();
    } else {
      episodeStr = '';
    }
    return DEpisode(
      url: strOf(json['url']),
      name: strOf(json['name']),
      dateUpload: strOf(json['dateUpload']) ?? strOf(json['date_upload']) ?? '',
      scanlator: strOf(json['scanlator']),
      thumbnail: strOf(json['thumbnail']),
      description: strOf(json['description']),
      memo: strOf(json['memo']) ?? strOf(json['description']),
      filler: boolOf(json['filler']),
      episodeNumber: episodeStr,
      sortMap: json['sortMap'] != null
          ? strMapOf(json['sortMap'])
          : {
              "season": strOf(json['season']) ?? '',
            },
    );
  }

  factory DEpisode.fromCs(Map<String, dynamic> json) {
    final extra = mapOf(json['extraData']);
    return DEpisode(
        url: strOf(json['dataUrl']) ?? strOf(json['url']),
        name: strOf(json['name']),
        dateUpload: strOf(json['dateUpload']) ?? strOf(json['date_upload']) ?? '',
        scanlator: strOf(json['scanlator']),
        thumbnail: strOf(json['thumbnail']) ??
            strOf(json['posterUrl']) ??
            strOf(extra['thumbnail']),
        description: strOf(json['description']),
        memo: strOf(json['memo']) ?? strOf(json['description']),
        filler: boolOf(json['filler']),
        episodeNumber: strOf(json['episodeNumber']) ?? strOf(json['episode']) ?? '1',
        sortMap: {
          "season": strOf(extra['season']) ?? '',
          "type": strOf(extra['episodeGroup']) ?? ''
        });
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'name': name,
        'dateUpload': dateUpload,
        'scanlator': scanlator,
        'thumbnail': thumbnail,
        'description': description,
        if (memo != null) 'memo': memo,
        'filler': filler,
        'episodeNumber': episodeNumber,
        if (sortMap != null) 'sortMap': sortMap,
      };

  static int compareByEpisodeNumber(DEpisode a, DEpisode b) {
    final aNum = double.tryParse(a.episodeNumber);
    final bNum = double.tryParse(b.episodeNumber);

    if (aNum != null && bNum != null) {
      return aNum.compareTo(bNum);
    }
    if (aNum != null) return -1;
    if (bNum != null) return 1;
    return (a.name ?? '').compareTo(b.name ?? '');
  }
}
