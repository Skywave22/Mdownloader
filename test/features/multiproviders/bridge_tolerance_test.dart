import 'package:flutter_test/flutter_test.dart';
import 'package:anymex_extension_runtime_bridge/Models/DEpisode.dart';
import 'package:anymex_extension_runtime_bridge/Models/DMedia.dart';
import 'package:anymex_extension_runtime_bridge/Models/JsonX.dart';
import 'package:anymex_extension_runtime_bridge/Models/Pages.dart';
import 'package:anymex_extension_runtime_bridge/Models/Source.dart';
import 'package:anymex_extension_runtime_bridge/Models/Video.dart';
import 'package:anymex_extension_runtime_bridge/Services/Legado/Models/LegadoSource.dart';
import 'package:anymex_extension_runtime_bridge/Services/Legado/LegadoSourceMethods.dart';

/// Regression tests for the tolerant JSON layer: manifests in the wild send
/// strings as one-element lists, versions as numbers, flags as 0/1 - none of
/// which may crash a repository add or a details fetch again
/// (`type 'List<dynamic>' is not a subtype of type 'String'`).
void main() {
  group('JsonX coercion', () {
    test('strOf joins lists and stringifies numbers', () {
      expect(strOf(['Foo']), 'Foo');
      expect(strOf(['A', 'B']), 'A, B');
      expect(strOf(1.0), '1.0');
      expect(strOf(true), 'true');
      expect(strOf({'name': 'X'}), 'X');
      expect(strOf(null), isNull);
    });

    test('strListOr accepts lists, comma strings and single values', () {
      expect(strListOr(['A', 'B']), ['A', 'B']);
      expect(strListOr('Action, Drama'), ['Action', 'Drama']);
      expect(strListOr('Solo'), ['Solo']);
      expect(strListOr(null), isEmpty);
    });

    test('boolOf/boolOr accept flags in every costume', () {
      expect(boolOf(true), isTrue);
      expect(boolOf(1), isTrue);
      expect(boolOf('false'), isFalse);
      expect(boolOf(0), isFalse);
      expect(boolOf('maybe'), isNull);
      expect(boolOr('1'), isTrue);
    });
  });

  group('Source.fromJson tolerance', () {
    test('accepts list-typed and number-typed manifest fields', () {
      final source = Source.fromJson({
        'id': 638504049,
        'name': ['1st Kiss'],
        'baseUrl': 'https://x.example',
        'lang': ['en', 'pt'],
        'version': 1.3,
        'isNsfw': 0,
        'itemType': 'anime',
        'author': [
          {'name': 'Dev A'},
          'Dev B',
        ],
      });
      expect(source.name, '1st Kiss');
      expect(source.lang, 'en, pt');
      expect(source.version, '1.3');
      expect(source.isNsfw, isFalse);
      expect(source.itemType, ItemType.anime);
      expect(source.author, 'Dev A, Dev B');
      expect(source.id, '638504049');
    });

    test('authorNameFrom accepts string, map and list shapes', () {
      expect(Source.authorNameFrom('Solo'), 'Solo');
      expect(Source.authorNameFrom({'name': 'Map'}), 'Map');
      expect(Source.authorNameFrom(['A', {'name': 'B'}]), 'A, B');
      expect(Source.authorNameFrom(null), isNull);
    });
  });

  group('DMedia/DEpisode tolerance', () {
    test('metadata survives list-typed fields and comma genres', () {
      final media = DMedia.fromJson({
        'title': ['Title'],
        'url': 'https://x/1',
        'cover': ['https://x/p.jpg'],
        'genre': 'Action, Drama',
        'author': ['Author'],
        'episodes': {
          'name': 'Ep 1',
          'url': 'https://x/1/1',
          'episodeNumber': 1,
        },
      });
      expect(media.title, 'Title');
      expect(media.cover, 'https://x/p.jpg');
      expect(media.genre, ['Action', 'Drama']);
      expect(media.author, 'Author');
      expect(media.episodes, hasLength(1));
      expect(media.episodes!.first.episodeNumber, '1');
    });

    test('episode fields accept numbers-as-strings and bools-as-ints', () {
      final ep = DEpisode.fromJson({
        'url': 'https://x/e',
        'name': ['Ep'],
        'episodeNumber': '12.0',
        'filler': 1,
        'season': 2,
      });
      expect(ep.name, 'Ep');
      expect(ep.episodeNumber, '12');
      expect(ep.filler, isTrue);
      expect(ep.sortMap?['season'], '2');
    });
  });

  group('Pages/Video tolerance', () {
    test('hasNextPage accepts string flags', () {
      final pages = Pages.fromJson({
        'list': [
          {'title': 'A', 'url': 'https://a'},
        ],
        'hasNextPage': 'true',
      });
      expect(pages.hasNextPage, isTrue);
    });

    test('video headers coerce non-string values and loose subtitle lists', () {
      final video = Video.fromJson({
        'url': 'https://v/1',
        'headers': {
          'X-Num': 42,
          'X-List': ['a'],
        },
        'subtitles': {
          'file': 'https://s/1.vtt',
          'label': 'English',
        },
      });
      expect(video.headers?['X-Num'], '42');
      expect(video.headers?['X-List'], 'a');
      expect(video.subtitles, hasLength(1));
      expect(video.subtitles!.first.label, 'English');
    });
  });

  group('Legado extension sections', () {
    test('exploreUrl rows become named sections', () async {
      final source = LegadoSource.fromLegadoJson({
        'bookSourceName': 'Books',
        'bookSourceUrl': 'https://books.example',
        'exploreUrl': 'Hot::/hot/{{page}}\nLatest::/new/{{page}}',
      });
      final methods = LegadoSourceMethods(source);
      final sections = await methods.getSections();
      expect(sections.map((s) => s.name), ['Hot', 'Latest']);
      expect(sections.map((s) => s.id), ['/hot/{{page}}', '/new/{{page}}']);
    });

    test('a single unnamed explore row leaves the default rails alone', () async {
      final source = LegadoSource.fromLegadoJson({
        'bookSourceName': 'Books',
        'bookSourceUrl': 'https://books.example',
        'exploreUrl': '/all/{{page}}',
      });
      final methods = LegadoSourceMethods(source);
      expect(await methods.getSections(), isEmpty);
    });
  });
}
