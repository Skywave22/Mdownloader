import 'package:flutter/material.dart';
import 'core/config.dart';
import 'services/locator.dart';
import 'ui/home_page.dart';
import 'ui/search_page.dart';
import 'ui/downloads_page.dart';

void main() {
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
    downloadManager.init().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomePage(),
      const SearchPage(),
      DownloadsPage(ready: _ready),
    ];
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C4DFF),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Downloads'),
          ],
        ),
      ),
    );
  }
}
