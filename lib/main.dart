import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'services/locator.dart';
import 'ui/downloads_page.dart';
import 'ui/home_page.dart';
import 'ui/plugins_page.dart';
import 'ui/search_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MdownloaderApp());
}

class MdownloaderApp extends StatefulWidget {
  const MdownloaderApp({super.key});

  @override
  State<MdownloaderApp> createState() => _MdownloaderAppState();
}

class _MdownloaderAppState extends State<MdownloaderApp> {
  int _index = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await downloadManager.init();
    try {
      await initPlugins();
    } catch (_) {
      // plugins optional — app still works for browsing
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MDownloader',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            HomePage(onSearchTap: () => setState(() => _index = 1)),
            const SearchPage(),
            DownloadsPage(ready: _ready),
            PluginsPage(ready: _ready),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search_rounded), label: 'Search'),
            NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download_rounded), label: 'Downloads'),
            NavigationDestination(icon: Icon(Icons.extension_outlined), selectedIcon: Icon(Icons.extension_rounded), label: 'Plugins'),
          ],
        ),
      ),
    );
  }
}
