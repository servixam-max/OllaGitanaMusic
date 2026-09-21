import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/network/api_client.dart';
import 'core/theme/stage_theme.dart';
import 'core/updater/app_updater.dart';
import 'core/widgets/member_selector_dialog.dart';
import 'features/lyrics/lyrics_screen.dart';
import 'features/stems_mixer/mixer_screen.dart';
import 'features/chords/chords_screen.dart';
import 'features/repertoire/repertoire_screen.dart';
import 'features/events/events_screen.dart';
import 'features/settings/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Barra de estado transparente — la app usa todo el alto de pantalla
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: StageTheme.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await ApiClient().ensureInitialized();
  runApp(const OllaGitanaApp());
}

class OllaGitanaApp extends StatelessWidget {
  const OllaGitanaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Olla Gitana Music',
      debugShowCheckedModeBanner: false,
      theme: StageTheme.theme,
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkUpdatesOnStartup();
    _checkUserIdentification();
  }

  void _checkUserIdentification() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    if (!ApiClient().isUserIdentified) {
      await showMemberSelectorDialog(context, barrierDismissible: false);
      if (mounted) setState(() {});
    }
  }

  void _checkUpdatesOnStartup() async {
    ApiClient().checkConnection();
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    final update = await AppUpdater.checkForUpdates();
    if (update != null && update["hasUpdate"] == true && mounted) {
      AppUpdater.showUpdateDialog(context, update);
    }
  }

  final List<Widget> _screens = const [
    RepertoireScreen(),
    EventsScreen(),
    MixerScreen(),
    LyricsScreen(),
    ChordsScreen(),
    SettingsScreen(),
  ];

  static const _destinations = [
    _NavItem(Icons.queue_music_outlined, Icons.queue_music, "Repertorio"),
    _NavItem(Icons.celebration_outlined, Icons.celebration, "Eventos"),
    _NavItem(Icons.tune_outlined, Icons.tune, "Mezclador"),
    _NavItem(Icons.mic_none_outlined, Icons.mic, "Letras"),
    _NavItem(Icons.piano_outlined, Icons.piano, "Acordes"),
    _NavItem(Icons.settings_outlined, Icons.settings, "Ajustes"),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: StageTheme.surface,
          border: Border(top: BorderSide(color: StageTheme.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: [
            for (int i = 0; i < _destinations.length; i++)
              NavigationDestination(
                icon: Icon(_destinations[i].icon),
                selectedIcon: Icon(_destinations[i].activeIcon),
                label: _destinations[i].label,
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}
