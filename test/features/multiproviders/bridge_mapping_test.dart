import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/features/multiproviders/presentation/multi_providers_screen.dart';
import 'package:anymex_extension_runtime_bridge/Models/DMedia.dart';
import 'package:anymex_extension_runtime_bridge/Models/Pages.dart';
import 'package:anymex_extension_runtime_bridge/Models/Source.dart';

void main() {
  group('Pages.fromJson', () {
    test('parses the canonical {list, hasNextPage} envelope', () {
      final pages = Pages.fromJson({
        'list': [
          {'title': 'A', 'url': 'https://a'},
          {'title': 'B', 'url': 'https://b'},
        ],
        'hasNextPage': true,
      });
      expect(pages.list.map((m) => m.title), ['A', 'B']);
      expect(pages.hasNextPage, isTrue);
    });

    test('accepts results/items envelope aliases', () {
      for (final key in ['results', 'items']) {
        final pages = Pages.fromJson({
          key: [
            {'title': 'X', 'url': 'https://x'},
          ],
        });
        expect(pages.list, hasLength(1), reason: 'envelope key $key');
      }
    });

    test('one malformed entry does not take down the page', () {
      final pages = Pages.fromJson({
        'list': [
          {'title': 'Good', 'url': 'https://good'},
          'not-a-map',
          42,
          {'title': 'AlsoGood', 'url': 'https://good2'},
        ],
      });
      expect(pages.list.map((m) => m.title), ['Good', 'AlsoGood']);
    });

    test('unknown pagination assumes more when the page is full', () {
      final full = Pages.fromJson({
        'list': [
          for (var i = 0; i < 8; i++) {'title': 'T$i', 'url': 'https://$i'},
        ],
      });
      expect(full.hasNextPage, isTrue,
          reason: 'a full page with unknown pagination should not stop at 1');

      final thin = Pages.fromJson({
        'list': [
          {'title': 'Only', 'url': 'https://only'},
        ],
      });
      expect(thin.hasNextPage, isFalse);
    });
  });

  group('DMedia.fromJson', () {
    test('reads unified keys', () {
      final media = DMedia.fromJson({
        'title': 'T',
        'url': 'https://u',
        'cover': 'https://c',
        'description': 'D',
      });
      expect(media.title, 'T');
      expect(media.url, 'https://u');
      expect(media.cover, 'https://c');
      expect(media.description, 'D');
    });

    test('reads CloudStream-shaped aliases', () {
      final media = DMedia.fromJson({
        'name': 'T',
        'link': 'https://u',
        'posterUrl': 'https://p',
        'synopsis': 'S',
      });
      expect(media.title, 'T');
      expect(media.url, 'https://u');
      expect(media.cover, 'https://p');
      expect(media.description, 'S');
    });

    test('author accepts both string and {name} map', () {
      expect(DMedia.fromJson({'author': 'Dev'}).author, 'Dev');
      expect(DMedia.fromJson({
        'author': {'name': 'Dev'},
      }).author, 'Dev');
    });
  });

  group('Source.authorNameFrom', () {
    test('accepts strings and {name, icon} maps', () {
      expect(Source.authorNameFrom('Dev'), 'Dev');
      expect(Source.authorNameFrom({'name': 'Dev', 'icon': 'x'}), 'Dev');
      expect(Source.authorNameFrom(null), isNull);
    });
  });

  group('extension manager labels and dev grouping', () {
    test('managerLabelOf folds -desktop ids and knows every backend', () {
      expect(managerLabelOf('cloudstream'), 'CloudStream');
      expect(managerLabelOf('aniyomi-desktop'), 'Aniyomi');
      expect(managerLabelOf('mangayomi'), 'Mangayomi');
      expect(managerLabelOf('sora'), 'Sora');
      expect(managerLabelOf('legado'), 'Legado');
      expect(managerLabelOf('kotatsu'), 'Kotatsu');
    });

    test('devNameOf prefers author, then repo owner, then repo', () {
      Source with({String? author, String? repo}) =>
          Source(name: 'n', author: author, repo: repo);

      expect(devNameOf(with(author: 'Dev')), 'Dev');
      expect(
        devNameOf(with(repo: 'https://github.com/some-dev/exts/index.min.json')),
        'some-dev',
      );
      expect(devNameOf(with()), '—');
    });
  });
}
