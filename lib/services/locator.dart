import '../downloader/download_manager.dart';
import '../plugins/plugin_manager.dart';
import 'tmdb_service.dart';

/// App-wide singletons.
final tmdb = TmdbService();
final downloadManager = DownloadManager();

/// Created in main() because it needs async setup; read via [plugins].
PluginManager? _plugins;

PluginManager? get plugins => _plugins;

bool get pluginsReady => _plugins != null;

Future<PluginManager> initPlugins() async {
  _plugins = await PluginManager.create();
  await _plugins!.init();
  return _plugins!;
}
