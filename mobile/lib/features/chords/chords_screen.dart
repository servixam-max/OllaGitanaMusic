import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/stage_theme.dart';
import '../../core/widgets/profile_app_bar_button.dart';

// Modelo de acordes de guitarra para diagramas de mástil
class ChordDiagramData {
  final String name;
  final List<int> frets; // -1: X (mute), 0: O (open), 1..5: traste
  final int baseFret;
  final List<int>? fingers;

  const ChordDiagramData({
    required this.name,
    required this.frets,
    this.baseFret = 1,
    this.fingers,
  });
}

// Diccionario de acordes estándar de guitarra (flamenca / española / acústica)
const Map<String, ChordDiagramData> kGuitarChords = {
  "Am": ChordDiagramData(name: "Am", frets: [-1, 0, 2, 2, 1, 0], fingers: [0, 0, 2, 3, 1, 0]),
  "A": ChordDiagramData(name: "A", frets: [-1, 0, 2, 2, 2, 0], fingers: [0, 0, 1, 2, 3, 0]),
  "A7": ChordDiagramData(name: "A7", frets: [-1, 0, 2, 0, 2, 0], fingers: [0, 0, 1, 0, 2, 0]),
  "C": ChordDiagramData(name: "C", frets: [-1, 3, 2, 0, 1, 0], fingers: [0, 3, 2, 0, 1, 0]),
  "C7": ChordDiagramData(name: "C7", frets: [-1, 3, 2, 3, 1, 0], fingers: [0, 3, 2, 4, 1, 0]),
  "D": ChordDiagramData(name: "D", frets: [-1, -1, 0, 2, 3, 2], fingers: [0, 0, 0, 1, 3, 2]),
  "Dm": ChordDiagramData(name: "Dm", frets: [-1, -1, 0, 2, 3, 1], fingers: [0, 0, 0, 2, 3, 1]),
  "D7": ChordDiagramData(name: "D7", frets: [-1, -1, 0, 2, 1, 2], fingers: [0, 0, 0, 2, 1, 3]),
  "E": ChordDiagramData(name: "E", frets: [0, 2, 2, 1, 0, 0], fingers: [0, 2, 3, 1, 0, 0]),
  "Em": ChordDiagramData(name: "Em", frets: [0, 2, 2, 0, 0, 0], fingers: [0, 2, 3, 0, 0, 0]),
  "E7": ChordDiagramData(name: "E7", frets: [0, 2, 0, 1, 0, 0], fingers: [0, 2, 0, 1, 0, 0]),
  "F": ChordDiagramData(name: "F", frets: [1, 3, 3, 2, 1, 1], baseFret: 1, fingers: [1, 3, 4, 2, 1, 1]),
  "F#m": ChordDiagramData(name: "F#m", frets: [2, 4, 4, 2, 2, 2], baseFret: 2, fingers: [1, 3, 4, 1, 1, 1]),
  "G": ChordDiagramData(name: "G", frets: [3, 2, 0, 0, 0, 3], fingers: [2, 1, 0, 0, 0, 3]),
  "G7": ChordDiagramData(name: "G7", frets: [3, 2, 0, 0, 0, 1], fingers: [3, 2, 0, 0, 0, 1]),
  "B7": ChordDiagramData(name: "B7", frets: [-1, 2, 1, 2, 0, 2], fingers: [0, 2, 1, 3, 0, 4]),
  "Bm": ChordDiagramData(name: "Bm", frets: [-1, 2, 4, 4, 3, 2], baseFret: 2, fingers: [0, 1, 3, 4, 2, 1]),
  "B": ChordDiagramData(name: "B", frets: [-1, 2, 4, 4, 4, 2], baseFret: 2, fingers: [0, 1, 2, 3, 4, 1]),
  "Bb": ChordDiagramData(name: "Bb", frets: [-1, 1, 3, 3, 3, 1], baseFret: 1, fingers: [0, 1, 2, 3, 4, 1]),
  "F7": ChordDiagramData(name: "F7", frets: [1, 3, 1, 2, 1, 1], baseFret: 1, fingers: [1, 3, 1, 2, 1, 1]),
  "Am7": ChordDiagramData(name: "Am7", frets: [-1, 0, 2, 0, 1, 0], fingers: [0, 0, 2, 0, 1, 0]),
  "Dm7": ChordDiagramData(name: "Dm7", frets: [-1, -1, 0, 2, 1, 1], fingers: [0, 0, 0, 2, 1, 1]),
  "Em7": ChordDiagramData(name: "Em7", frets: [0, 2, 2, 0, 3, 0], fingers: [0, 2, 3, 0, 4, 0]),
  "Gm": ChordDiagramData(name: "Gm", frets: [3, 5, 5, 3, 3, 3], baseFret: 3, fingers: [1, 3, 4, 1, 1, 1]),
  "Cmaj7": ChordDiagramData(name: "Cmaj7", frets: [-1, 3, 2, 0, 0, 0], fingers: [0, 3, 2, 0, 0, 0]),
  "Fmaj7": ChordDiagramData(name: "Fmaj7", frets: [-1, -1, 3, 2, 1, 0], fingers: [0, 0, 3, 2, 1, 0]),
  "Gmaj7": ChordDiagramData(name: "Gmaj7", frets: [3, 2, 0, 0, 0, 2], fingers: [2, 1, 0, 0, 0, 3]),
  "Amaj7": ChordDiagramData(name: "Amaj7", frets: [-1, 0, 2, 1, 2, 0], fingers: [0, 0, 2, 1, 3, 0]),
  "Dmaj7": ChordDiagramData(name: "Dmaj7", frets: [-1, -1, 0, 2, 2, 2], fingers: [0, 0, 0, 1, 2, 3]),
  "Emaj7": ChordDiagramData(name: "Emaj7", frets: [0, 2, 1, 1, 0, 0], fingers: [0, 3, 1, 2, 0, 0]),
  "C#m": ChordDiagramData(name: "C#m", frets: [-1, 4, 6, 6, 5, 4], baseFret: 4, fingers: [0, 1, 3, 4, 2, 1]),
  "G#m": ChordDiagramData(name: "G#m", frets: [4, 6, 6, 4, 4, 4], baseFret: 4, fingers: [1, 3, 4, 1, 1, 1]),
  "F#m7": ChordDiagramData(name: "F#m7", frets: [2, 4, 2, 2, 2, 2], baseFret: 2, fingers: [1, 3, 1, 1, 1, 1]),
  "Bm7": ChordDiagramData(name: "Bm7", frets: [-1, 2, 4, 2, 3, 2], baseFret: 2, fingers: [0, 1, 3, 1, 2, 1]),
  "Cadd9": ChordDiagramData(name: "Cadd9", frets: [-1, 3, 2, 0, 3, 0], fingers: [0, 2, 1, 0, 3, 0]),
  "Dsus4": ChordDiagramData(name: "Dsus4", frets: [-1, -1, 0, 2, 3, 3], fingers: [0, 0, 0, 1, 2, 3]),
  "Asus4": ChordDiagramData(name: "Asus4", frets: [-1, 0, 2, 2, 3, 0], fingers: [0, 0, 1, 2, 3, 0]),
  "Esus4": ChordDiagramData(name: "Esus4", frets: [0, 2, 2, 2, 0, 0], fingers: [0, 1, 2, 3, 0, 0]),
};

// Dibujante de diagrama de acordes de guitarra en lienzo (CustomPainter)
class GuitarChordPainter extends CustomPainter {
  final ChordDiagramData chord;

  GuitarChordPainter({required this.chord});

  @override
  void paint(Canvas canvas, Size size) {
    final paintFret = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1.5;

    final paintNut = Paint()
      ..color = StageTheme.amberGold
      ..strokeWidth = 4.0;

    final paintString = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.2;

    final paintDot = Paint()
      ..color = StageTheme.flameOrange
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    const int numStrings = 6;
    const int numFrets = 4;
    const double topMargin = 24.0;
    const double leftMargin = 22.0;
    const double rightMargin = 22.0;
    const double bottomMargin = 16.0;

    final double width = size.width - leftMargin - rightMargin;
    final double height = size.height - topMargin - bottomMargin;
    final double stringSpacing = width / (numStrings - 1);
    final double fretSpacing = height / numFrets;

    // Cejuela o traste base
    if (chord.baseFret == 1) {
      canvas.drawLine(
        const Offset(leftMargin, topMargin),
        Offset(leftMargin + width, topMargin),
        paintNut,
      );
    } else {
      canvas.drawLine(
        const Offset(leftMargin, topMargin),
        Offset(leftMargin + width, topMargin),
        paintFret,
      );
      textPainter.text = TextSpan(
        text: "${chord.baseFret}ª",
        style: const TextStyle(color: StageTheme.amberGold, fontSize: 11, fontWeight: FontWeight.bold),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(leftMargin - 18, topMargin + fretSpacing / 2 - 6));
    }

    // Trastes horizontales
    for (int i = 1; i <= numFrets; i++) {
      final y = topMargin + i * fretSpacing;
      canvas.drawLine(Offset(leftMargin, y), Offset(leftMargin + width, y), paintFret);
    }

    // Cuerdas verticales y digitación
    for (int i = 0; i < numStrings; i++) {
      final x = leftMargin + i * stringSpacing;
      canvas.drawLine(Offset(x, topMargin), Offset(x, topMargin + height), paintString);

      final fretVal = chord.frets.length > i ? chord.frets[i] : 0;

      if (fretVal == -1) {
        textPainter.text = const TextSpan(
          text: "X",
          style: TextStyle(color: StageTheme.alertRed, fontSize: 12, fontWeight: FontWeight.bold),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - textPainter.width / 2, 4));
      } else if (fretVal == 0) {
        textPainter.text = const TextSpan(
          text: "O",
          style: TextStyle(color: StageTheme.electricGreen, fontSize: 12, fontWeight: FontWeight.bold),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - textPainter.width / 2, 4));
      } else {
        final relativeFret = fretVal - chord.baseFret + 1;
        if (relativeFret >= 1 && relativeFret <= numFrets) {
          final dotY = topMargin + (relativeFret - 0.5) * fretSpacing;
          canvas.drawCircle(Offset(x, dotY), 8, paintDot);

          final finger = (chord.fingers != null && chord.fingers!.length > i) ? chord.fingers![i] : 0;
          if (finger > 0) {
            textPainter.text = TextSpan(
              text: "$finger",
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            );
            textPainter.layout();
            textPainter.paint(canvas, Offset(x - textPainter.width / 2, dotY - textPainter.height / 2));
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant GuitarChordPainter oldDelegate) => oldDelegate.chord != chord;
}

class ChordsScreen extends StatefulWidget {
  const ChordsScreen({super.key});

  @override
  State<ChordsScreen> createState() => _ChordsScreenState();
}

class _ChordsScreenState extends State<ChordsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ApiClient _api = ApiClient();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Estado pestaña búsqueda
  List<dynamic> _searchResults = [];
  bool _isSearching = false;

  // Estado pestaña detector por audio
  bool _isAnalyzing = false;
  Map<String, dynamic>? _analysisResult;
  String? _analysisError;
  List<dynamic> _chordHistory = [];
  bool _isLoadingHistory = false;

  // Estado del reproductor sincronizado
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  bool _isPlayingAudio = false;
  String? _manuallySelectedChord;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _audioPlayer.positionStream.listen((pos) {
      if (mounted) setState(() => _audioPosition = pos);
    });

    _audioPlayer.durationStream.listen((dur) {
      if (mounted) setState(() => _audioDuration = dur ?? Duration.zero);
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlayingAudio = state.playing);
    });

    _loadChordHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadChordHistory() async {
    setState(() => _isLoadingHistory = true);
    final history = await _api.getChordHistory();
    if (mounted) {
      setState(() {
        _chordHistory = history;
        _isLoadingHistory = false;
      });
    }
  }

  Future<void> _deleteHistoryItem(String id, String filename) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StageTheme.surface,
        title: const Text("Eliminar Canción"),
        content: Text("¿Deseas eliminar '$filename' de la biblioteca de acordes?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar", style: TextStyle(color: StageTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: StageTheme.alertRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Eliminar", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_analysisResult != null && _analysisResult!["id"] == id) {
        await _audioPlayer.stop();
        setState(() {
          _analysisResult = null;
          _manuallySelectedChord = null;
        });
      }
      await _api.deleteChordAnalysis(id);
      _loadChordHistory();
    }
  }

  Future<void> _loadAnalysisIntoPlayer(Map<String, dynamic> analysis) async {
    await _audioPlayer.stop();
    setState(() {
      _analysisResult = analysis;
      _manuallySelectedChord = null;
      _audioPosition = Duration.zero;
      _audioDuration = Duration.zero;
    });

    final audioUrl = analysis["audio_url"];
    if (audioUrl != null && audioUrl.toString().isNotEmpty) {
      try {
        final fullUrl = _api.getFullUrl(audioUrl);
        await _audioPlayer.setUrl(fullUrl);
      } catch (e) {
        print("[ChordsScreen] Error cargando audio: $e");
      }
    }
  }

  Future<void> _searchChords() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isSearching = true);
    final results = await _api.searchChords(query);
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  Future<void> _analyzeAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac', 'ogg', 'm4a'],
      withData: true,
    );

    if (result == null || (result.files.single.path == null && result.files.single.bytes == null)) return;
    final picked = result.files.single;

    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
      _analysisError = null;
    });

    final analysis = await _api.extractChords(
      filePath: picked.path,
      fileBytes: picked.bytes,
      fileName: picked.name,
    );

    final error = analysis?["error"] as String?;
    setState(() {
      _isAnalyzing = false;
      _analysisResult = (analysis != null && error == null) ? analysis : null;
      _analysisError = analysis == null
          ? "No se pudo conectar con el servidor para analizar el audio."
          : error;
    });

    if (analysis != null && error == null) {
      _loadChordHistory();
      _loadAnalysisIntoPlayer(analysis);
    }
  }

  String? _getCurrentActiveChord() {
    if (_manuallySelectedChord != null) return _manuallySelectedChord;
    if (_analysisResult == null) return null;
    final timeline = _analysisResult!["timeline"] as List<dynamic>? ?? [];
    final currentSec = _audioPosition.inMilliseconds / 1000.0;
    for (final seg in timeline) {
      final start = (seg["start"] as num?)?.toDouble() ?? 0.0;
      final end = (seg["end"] as num?)?.toDouble() ?? 0.0;
      if (currentSec >= start && currentSec < end) {
        return seg["chord"] as String?;
      }
    }
    return _analysisResult!["estimated_key"];
  }

  ChordDiagramData? _getChordDiagramData(String? chordName) {
    if (chordName == null || chordName.isEmpty) return null;
    String clean = chordName.trim();
    if (kGuitarChords.containsKey(clean)) return kGuitarChords[clean];

    // Normalizar variaciones comunes (ej. Amin -> Am, Cmaj -> C, Emin -> Em)
    if (clean.endsWith("min")) clean = "${clean.substring(0, clean.length - 3)}m";
    if (clean.endsWith("maj7")) {
      // "maj7" es una calidad válida; solo normalizar el sufijo suelto "maj"
    } else if (clean.endsWith("maj")) {
      clean = clean.substring(0, clean.length - 3);
    }
    if (kGuitarChords.containsKey(clean)) return kGuitarChords[clean];

    // Si no hay diagrama exacto, intentar la tríada base (Am7 -> Am, F#m7 -> F#m)
    for (final suffix in ["maj7", "m7", "7", "add9", "sus4", "dim"]) {
      if (clean.endsWith(suffix)) {
        final base = clean.substring(0, clean.length - suffix.length);
        if (kGuitarChords.containsKey(base)) return kGuitarChords[base];
      }
    }

    return null;
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Acordes & Tonalidad"),
        actions: const [
          ProfileAppBarButton(),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: StageTheme.flameOrange,
          labelColor: StageTheme.flameOrange,
          unselectedLabelColor: StageTheme.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          tabs: const [
            Tab(icon: Icon(Icons.search), text: "Buscador Cifrados"),
            Tab(icon: Icon(Icons.analytics), text: "Detector de Audio"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSearchTab(),
          _buildAudioAnalysisTab(),
        ],
      ),
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Buscar canción para ver acordes...",
                    filled: true,
                    fillColor: StageTheme.surfaceElevated,
                    prefixIcon: const Icon(Icons.queue_music, color: StageTheme.amberGold),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _searchChords(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isSearching ? null : _searchChords,
                child: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text("Buscar"),
              ),
            ],
          ),
        ),
        Expanded(
          child: _searchResults.isNotEmpty
              ? ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final item = _searchResults[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: StageTheme.surfaceElevated,
                          child: Icon(Icons.music_note, color: StageTheme.flameOrange),
                        ),
                        title: Text(item["title"] ?? "Sin título", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(item["artist"] ?? "Desconocido", style: const TextStyle(color: StageTheme.textSecondary)),
                        trailing: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              label: Text("Songsterr", style: TextStyle(fontSize: 11, color: Colors.white)),
                              backgroundColor: StageTheme.surfaceElevated,
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios, size: 14, color: StageTheme.textMuted),
                          ],
                        ),
                        onTap: () => _openChordDetails(item),
                      ),
                    );
                  },
                )
              : const Center(
                  child: Text(
                    "Busca una canción para consultar sus acordes y tablaturas",
                    style: TextStyle(color: StageTheme.textSecondary),
                  ),
                ),
        ),
      ],
    );
  }

  void _openChordDetails(Map<String, dynamic> item) {
    int transpose = 0;
    final title = item["title"] ?? "Canción";
    final artist = item["artist"] ?? "Artista";
    final url = item["url"] ?? "https://www.songsterr.com";

    final standardChords = ["Am", "G", "F", "E7", "C", "Dm", "E", "A7", "D", "Em"];
    final notes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

    String transposeChord(String chord, int semitones) {
      if (semitones == 0) return chord;
      for (int i = 0; i < notes.length; i++) {
        final n = notes[i];
        if (chord.startsWith(n)) {
          final nextIndex = (i + semitones) % 12;
          final adjustedIndex = nextIndex < 0 ? nextIndex + 12 : nextIndex;
          final remainder = chord.substring(n.length);
          return "${notes[adjustedIndex]}$remainder";
        }
      }
      return chord;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: StageTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: StageTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.queue_music, color: StageTheme.amberGold, size: 32),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            Text(artist, style: const TextStyle(fontSize: 15, color: StageTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: StageTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Transporte (Cejilla):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle, color: StageTheme.flameOrange),
                              onPressed: () => setSheetState(() => transpose--),
                            ),
                            Text(
                              transpose == 0 ? "Original (0)" : (transpose > 0 ? "+$transpose" : "$transpose"),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: StageTheme.amberGold),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle, color: StageTheme.flameOrange),
                              onPressed: () => setSheetState(() => transpose++),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text("Acordes de Referencia:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: standardChords.map((ch) {
                      final transposed = transposeChord(ch, transpose);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: StageTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: StageTheme.amberGold.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          transposed,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: StageTheme.amberGold),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 20),
                      label: const Text("Abrir Tablatura Completa en Songsterr", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StageTheme.flameOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        try {
                          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        } catch (_) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text("No se pudo abrir la tablatura")),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAudioAnalysisTab() {
    final activeChord = _getCurrentActiveChord();
    final chordData = _getChordDiagramData(activeChord);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner de carga de audio para análisis
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: StageTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: StageTheme.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.graphic_eq, size: 52, color: StageTheme.amberGold),
                const SizedBox(height: 10),
                const Text(
                  "Detección Armónica de Audio",
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Sube una grabación o canción para detectar acordes, tonalidad y reproducirla con seguimiento en tiempo real.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: StageTheme.textSecondary, fontSize: 13, height: 1.3),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text("Seleccionar Audio para Analizar"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StageTheme.flameOrange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isAnalyzing ? null : _analyzeAudioFile,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_isAnalyzing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(28.0),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: StageTheme.flameOrange),
                    SizedBox(height: 16),
                    Text("Detectando beats, acordes y tonalidad con librosa..."),
                  ],
                ),
              ),
            ),

          if (_analysisError != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: StageTheme.alertRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: StageTheme.alertRed),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: StageTheme.alertRed),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _analysisError!,
                      style: const TextStyle(color: StageTheme.alertRed, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // VISTA ACTIVA: Reproductor Sincronizado + Diagrama de Acordes
          if (_analysisResult != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: StageTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: StageTheme.amberGold.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título de la canción cargada y botón cerrar
                  Row(
                    children: [
                      const Icon(Icons.music_note, color: StageTheme.flameOrange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _analysisResult!["filename"] ?? "Audio Analizado",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: StageTheme.textMuted),
                        tooltip: "Cerrar reproductor",
                        onPressed: () {
                          _audioPlayer.stop();
                          setState(() {
                            _analysisResult = null;
                            _manuallySelectedChord = null;
                          });
                        },
                      ),
                    ],
                  ),
                  const Divider(color: StageTheme.border),

                  // Tonalidad dominante y cadencia
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Tonalidad Dominante:", style: TextStyle(color: StageTheme.textSecondary, fontSize: 13)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: StageTheme.flameOrange,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _analysisResult!["estimated_key"] ?? "N/A",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      if (_analysisResult!["tempo"] != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text("Tempo:", style: TextStyle(color: StageTheme.textSecondary, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              "${_analysisResult!["tempo"]} BPM",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: StageTheme.electricGreen),
                            ),
                          ],
                        ),
                      if (activeChord != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text("Acorde Sonando:", style: TextStyle(color: StageTheme.textSecondary, fontSize: 13)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: StageTheme.amberGold,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                activeChord,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Diagrama de mástil de guitarra para el acorde activo
                  if (chordData != null)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: StageTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: StageTheme.amberGold.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              "Posición en Guitarra: ${chordData.name}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: StageTheme.amberGold),
                            ),
                            const SizedBox(height: 8),
                            CustomPaint(
                              size: const Size(180, 160),
                              painter: GuitarChordPainter(chord: chordData),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "6ª (Mi) ➔ 1ª (mi)",
                              style: TextStyle(fontSize: 11, color: StageTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Controles de reproducción sincronizada
                  Row(
                    children: [
                      IconButton(
                        iconSize: 42,
                        icon: Icon(
                          _isPlayingAudio ? Icons.pause_circle_filled : Icons.play_circle_fill,
                          color: StageTheme.flameOrange,
                        ),
                        onPressed: () {
                          if (_isPlayingAudio) {
                            _audioPlayer.pause();
                          } else {
                            _audioPlayer.play();
                          }
                        },
                      ),
                      Expanded(
                        child: Slider(
                          value: _audioPosition.inMilliseconds.toDouble().clamp(0.0, _audioDuration.inMilliseconds.toDouble()),
                          max: _audioDuration.inMilliseconds > 0 ? _audioDuration.inMilliseconds.toDouble() : 1.0,
                          activeColor: StageTheme.amberGold,
                          inactiveColor: StageTheme.border,
                          onChanged: (val) {
                            _audioPlayer.seek(Duration(milliseconds: val.toInt()));
                          },
                        ),
                      ),
                      Text(
                        "${_formatDuration(_audioPosition)} / ${_formatDuration(_audioDuration)}",
                        style: const TextStyle(fontSize: 12, color: StageTheme.textSecondary, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Línea temporal interactiva de acordes
            const Text(
              "Línea Temporal de Acordes (Toca uno para saltar)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            ...((_analysisResult!["timeline"] as List<dynamic>? ?? []).map((seg) {
              final start = (seg["start"] as num?)?.toDouble() ?? 0.0;
              final end = (seg["end"] as num?)?.toDouble() ?? 0.0;
              final chord = seg["chord"] ?? "N/A";
              final confidence = (((seg["confidence"] as num?)?.toDouble() ?? 0.0) * 100).toInt();

              final currentSec = _audioPosition.inMilliseconds / 1000.0;
              final isCurrent = currentSec >= start && currentSec < end;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isCurrent ? StageTheme.flameOrange : Colors.transparent,
                    width: isCurrent ? 2.0 : 1.0,
                  ),
                ),
                color: isCurrent ? StageTheme.flameOrange.withValues(alpha: 0.15) : StageTheme.surfaceElevated,
                child: ListTile(
                  leading: Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isCurrent ? StageTheme.flameOrange : StageTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isCurrent ? StageTheme.amberGold : StageTheme.border),
                    ),
                    child: Text(
                      chord,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isCurrent ? Colors.white : StageTheme.amberGold,
                      ),
                    ),
                  ),
                  title: Text(
                    "${start.toStringAsFixed(1)}s  -  ${end.toStringAsFixed(1)}s",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isCurrent ? StageTheme.flameOrange : Colors.white,
                    ),
                  ),
                  subtitle: Text("Confianza armónica: $confidence%", style: const TextStyle(color: StageTheme.textSecondary, fontSize: 12)),
                  trailing: const Icon(Icons.play_arrow, color: StageTheme.amberGold, size: 20),
                  onTap: () {
                    _audioPlayer.seek(Duration(milliseconds: (start * 1000).toInt()));
                    setState(() => _manuallySelectedChord = chord);
                  },
                ),
              );
            })),
            const SizedBox(height: 24),
          ],

          // SECCIÓN: Biblioteca de Canciones Analizadas (Persistencia)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Biblioteca de Canciones Analizadas",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: StageTheme.amberGold, size: 20),
                tooltip: "Refrescar biblioteca",
                onPressed: _loadChordHistory,
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_isLoadingHistory)
            const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: StageTheme.amberGold)))
          else if (_chordHistory.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: StageTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                "Aún no hay canciones guardadas en la biblioteca.\nSube un archivo de audio para analizar sus acordes.",
                textAlign: TextAlign.center,
                style: TextStyle(color: StageTheme.textMuted, fontSize: 13),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _chordHistory.length,
              itemBuilder: (ctx, index) {
                final item = _chordHistory[index];
                final filename = item["filename"] ?? "Audio";
                final key = item["estimated_key"] ?? "N/A";
                final durationSec = (item["duration"] as num?)?.toDouble() ?? 0.0;
                final durationStr = _formatDuration(Duration(seconds: durationSec.toInt()));
                final isCurrentlyLoaded = _analysisResult != null && _analysisResult!["id"] == item["id"];

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: isCurrentlyLoaded ? StageTheme.flameOrange.withValues(alpha: 0.12) : null,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: StageTheme.amberGold.withValues(alpha: 0.2),
                      child: Text(
                        key,
                        style: const TextStyle(color: StageTheme.amberGold, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    title: Text(filename, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text("Tonalidad: $key • Duración: $durationStr", style: const TextStyle(fontSize: 12, color: StageTheme.textSecondary)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: StageTheme.alertRed),
                          tooltip: "Eliminar de la biblioteca",
                          onPressed: () => _deleteHistoryItem(item["id"] ?? "", filename),
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isCurrentlyLoaded ? StageTheme.flameOrange : StageTheme.amberGold,
                            foregroundColor: isCurrentlyLoaded ? Colors.white : Colors.black,
                          ),
                          child: Text(isCurrentlyLoaded ? "Cargada" : "Cargar", style: const TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () => _loadAnalysisIntoPlayer(item),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
