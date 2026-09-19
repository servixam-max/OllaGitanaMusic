import 'package:flutter/material.dart';
import 'core/theme/stage_theme.dart';
import 'features/lyrics/lyrics_screen.dart';
import 'features/stems_mixer/mixer_screen.dart';
import 'features/chords/chords_screen.dart';
import 'features/repertoire/repertoire_screen.dart';
import 'features/settings/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

  final List<Widget> _screens = const [
    RepertoireScreen(),
    MixerScreen(),
    LyricsScreen(),
    ChordsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.how_to_vote),
            label: "Repertorio",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tune),
            label: "Mezclador",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mic),
            label: "Letras",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.music_note),
            label: "Acordes",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: "Ajustes",
          ),
        ],
      ),
    );
  }
}
