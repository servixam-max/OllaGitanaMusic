import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/stage_theme.dart';

class ChordsScreen extends StatefulWidget {
  const ChordsScreen({super.key});

  @override
  State<ChordsScreen> createState() => _ChordsScreenState();
}

class _ChordsScreenState extends State<ChordsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ApiClient _api = ApiClient();

  // Estado pestaña búsqueda
  List<dynamic> _searchResults = [];
  bool _isSearching = false;

  // Estado pestaña detector por audio
  bool _isAnalyzing = false;
  Map<String, dynamic>? _analysisResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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
    );

    if (result == null || result.files.single.path == null) return;

    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
    });

    final analysis = await _api.extractChords(filePath: result.files.single.path!);

    setState(() {
      _isAnalyzing = false;
      _analysisResult = analysis;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Acordes & Tonalidad"),
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
                        trailing: const Chip(
                          label: Text("Songsterr", style: TextStyle(fontSize: 11, color: Colors.white)),
                          backgroundColor: StageTheme.surfaceElevated,
                        ),
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

  Widget _buildAudioAnalysisTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: StageTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: StageTheme.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.graphic_eq, size: 56, color: StageTheme.amberGold),
                const SizedBox(height: 12),
                const Text(
                  "Detección Armónica de Audio",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Sube una grabación de un ensayo o una pista de audio para analizar sus cromagramas y predecir los acordes y la tonalidad dominante.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: StageTheme.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text("Seleccionar Audio para Analizar"),
                  onPressed: _isAnalyzing ? null : _analyzeAudioFile,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_isAnalyzing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: StageTheme.flameOrange),
                    SizedBox(height: 16),
                    Text("Analizando cromas y frecuencias armónicas con librosa..."),
                  ],
                ),
              ),
            ),

          if (_analysisResult != null) ...[
            // Tonalidad estimada
            Card(
              color: StageTheme.surfaceElevated,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Tonalidad Estimada:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: StageTheme.flameOrange,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _analysisResult!["estimated_key"] ?? "N/A",
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Línea temporal de acordes
            const Text(
              "Línea Temporal de Acordes",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            ...((_analysisResult!["timeline"] as List<dynamic>? ?? []).map((seg) {
              final start = seg["start"];
              final end = seg["end"];
              final chord = seg["chord"];
              final confidence = ((seg["confidence"] ?? 0.0) * 100).toInt();

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: StageTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: StageTheme.amberGold),
                    ),
                    child: Text(
                      chord,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: StageTheme.amberGold),
                    ),
                  ),
                  title: Text("$start s  -  $end s", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Confianza: $confidence%", style: const TextStyle(color: StageTheme.textSecondary)),
                ),
              );
            })),
          ],
        ],
      ),
    );
  }
}
