import '../Models/DEpisode.dart';
import '../Models/DMedia.dart';
import '../Models/DSection.dart';
import '../Models/Page.dart';
import '../Models/Pages.dart';
import '../Models/Source.dart';
import '../Models/SourceParams.dart';
import '../Models/SourcePreference.dart';
import '../Models/Video.dart';

abstract class SourceMethods {
  Source get source;
  
  SourceMethods();

  Future<Pages> getPopular(int page, {SourceParams? parameters});

  Future<Pages> getLatestUpdates(int page, {SourceParams? parameters});

  Future<Pages> search(String query, int page, List<dynamic> filters,
      {SourceParams? parameters});

  Future<DMedia> getDetail(DMedia media, {SourceParams? parameters});

  Future<List<PageUrl>> getPageList(DEpisode episode,
      {SourceParams? parameters});

  Future<List<Video>> getVideoList(DEpisode episode,
      {SourceParams? parameters});

  Stream<Video>? getVideoListStream(DEpisode episode,
          {SourceParams? parameters}) =>
      null;

  /// Named browse sections the extension itself defines (Legado explore
  /// rows, and any backend hook that grows one). Empty means the app shows
  /// just the standard Popular/Latest rails - those two hooks are extension
  /// code too, this is for extensions that define MORE rows than that.
  Future<List<DSection>> getSections({SourceParams? parameters}) async =>
      const [];

  /// One page of a section returned by [getSections]; [section.id] is the
  /// backend's own handle for the row.
  Future<Pages> getSectionPages(
    DSection section,
    int page, {
    SourceParams? parameters,
  }) async =>
      Pages(list: const []);

  Future<List<dynamic>> getFilterList() async => [];

  Future<void> stopHttpServer() async {}

  Future<String?> getNovelContent(String chapterTitle, String chapterId,
      {SourceParams? parameters});

  Future<void> cancelRequest(String token);

  Future<List<SourcePreference>> getPreference();

  Future<bool> setPreference(SourcePreference pref, dynamic value);
}
