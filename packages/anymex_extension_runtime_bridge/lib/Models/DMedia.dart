import 'dart:convert';
import 'DEpisode.dart';
import 'JsonX.dart';
import 'Source.dart';

class DMedia {
  String? title;
  String? url;
  String? cover;
  String? description;
  String? author;
  String? artist;
  List<String>? genre;
  List<DEpisode>? episodes;

  DMedia({
    this.title,
    this.url,
    this.cover,
    this.description,
    this.author,
    this.artist,
    this.genre,
    this.episodes,
  });

  factory DMedia.fromJson(Map<String, dynamic> json) {
    final parsedEpisodes = [
      for (final e in mapListOf(json['episodes']))
        DEpisode.fromJson(e),
    ];

    // Unified and CloudStream-shaped payloads both land here; accept the
    // aliases either side uses so nothing degrades to "title only".
    return DMedia(
      title: strOf(json['title']) ?? strOf(json['name']),
      url: strOf(json['url']) ?? strOf(json['link']),
      cover: strOf(json['cover']) ??
          strOf(json['posterUrl']) ??
          strOf(json['thumbnail_url']) ??
          strOf(json['image']) ??
          strOf(json['poster']),
      description: strOf(json['description']) ??
          strOf(json['synopsis']) ??
          strOf(json['plot']),
      artist: strOf(json['artist']),
      author: Source.authorNameFrom(json['author'] ?? json['authors']),
      genre: strListOr(json['genre'] ?? json['genres']),
      episodes: parsedEpisodes,
    );
  }

  factory DMedia.fromCs(Map<String, dynamic> json) {
    final String? mediaTitle = strOf(json['title']) ?? strOf(json['name']);

    final parsedEpisodes = mapListOf(json['episodes']).map((epJson) {
            final Map<String, dynamic> epMap = epJson;
            
            if (mediaTitle != null && mediaTitle.isNotEmpty) {
              final String? urlData =
                  strOf(epMap['url']) ?? strOf(epMap['data']);
              if (urlData != null && urlData.trim().startsWith('{')) {
                try {
                  final decoded = jsonDecode(urlData);
                  if (decoded is Map && !decoded.containsKey('title')) {
                    decoded['title'] = mediaTitle;
                    final injected = jsonEncode(decoded);
                    epMap['url'] = injected;
                    if (epMap.containsKey('data')) {
                      epMap['data'] = injected;
                    }
                  }
                } catch (_) {

                }
              }
            }
            return DEpisode.fromCs(epMap);
          }).toList();

    return DMedia(
      title: mediaTitle,
      url: strOf(json['url']),
      cover: strOf(json['cover']) ?? strOf(json['thumbnail_url']),
      description: strOf(json['description']),
      artist: strOf(json['artist']),
      author: Source.authorNameFrom(json['author'] ?? json['authors']),
      genre: strListOr(json['genre'] ?? json['genres']),
      episodes: parsedEpisodes..sort(DEpisode.compareByEpisodeNumber),
    );
  }

  factory DMedia.withUrl(String url) {
    return DMedia(
      title: '',
      url: url,
      cover: '',
      description: '',
      artist: '',
      author: '',
      genre: [],
      episodes: [],
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'cover': cover,
        'description': description,
        'author': author,
        'artist': artist,
        'genre': genre,
        'episodes': episodes?.map((e) => e.toJson()).toList(),
      };
}
