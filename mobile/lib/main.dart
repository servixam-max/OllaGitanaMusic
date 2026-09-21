import 'package:flutter/material.dart';
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
    // Probar conectividad inicial con el backend en segundo plano
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
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ..._screens,
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: StageTheme.surface,
        indicatorColor: StageTheme.flameOrange.withValues(alpha: 0.22),
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.queue_music, color: StageTheme.textSecondary),
            selectedIcon: Icon(Icons.queue_music, color: StageTheme.flameOrange),
            label: "Repertorio",
          ),
          NavigationDestination(
            icon: Icon(Icons.celebration, color: StageTheme.textSecondary),
            selectedIcon: Icon(Icons.celebration, color: StageTheme.flameOrange),
            label: "Eventos",
          ),
          NavigationDestination(
            icon: Icon(Icons.tune, color: StageTheme.textSecondary),
            selectedIcon: Icon(Icons.tune, color: StageTheme.flameOrange),
            label: "Mezclador",
          ),
          NavigationDestination(
            icon: Icon(Icons.mic, color: StageTheme.textSecondary),
            selectedIcon: Icon(Icons.mic, color: StageTheme.flameOrange),
            label: "Letras",
          ),
          NavigationDestination(
            icon: Icon(Icons.music_note, color: StageTheme.textSecondary),
            selectedIcon: Icon(Icons.music_note, color: StageTheme.flameOrange),
            label: "Acordes",
          ),
        ],
      ),
    );
  }
}
