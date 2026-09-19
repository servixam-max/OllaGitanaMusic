import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/stage_theme.dart';

class LyricsScreen extends StatefulWidget {
  const LyricsScreen({super.key});

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiClient _api = ApiClient();

  List<dynamic> _searchResults = [];
  Map<String, dynamic>? _currentLyrics;
  bool _isLoading = false;

  // Controles de escenario
  double _fontSize = 20.0;
  bool _isAutoScrolling = false;
  double _scrollSpeed = 1.0; // Velocidad de desplazamiento
  Timer? _scrollTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _stopAutoScroll();
    super.dispose();
  }

  Future<void> _searchLyrics() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isLoading = true);
    final results = await _api.searchLyrics(query);
    setState(() {
      _searchResults = results;
      _isLoading = false;
    });
  }

  void _selectSong(Map<String, dynamic> song) {
    setState(() {
      _currentLyrics = song;
      _searchResults = [];
    });
  }

  void _toggleAutoScroll() {
    setState(() {
      _isAutoScrolling = !_isAutoScrolling;
    });

    if (_isAutoScrolling) {
      _startAutoScroll();
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      final delta = _scrollSpeed * 1.5;

      if (currentScroll + delta >= maxScroll) {
        _stopAutoScroll();
        setState(() => _isAutoScrolling = false);
      } else {
        _scrollController.jumpTo(currentScroll + delta);
      }
    });
  }

  void _stopAutoScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Letras en Directo"),
        actions: [
          if (_currentLyrics != null) ...[
            // Controles de tamaño de fuente
            IconButton(
              icon: const Icon(Icons.text_decrease),
              tooltip: "Reducir letra",
              onPressed: () {
                if (_fontSize > 14) setState(() => _fontSize -= 2);
              },
            ),
            IconButton(
              icon: const Icon(Icons.text_increase),
              tooltip: "Aumentar letra",
              onPressed: () {
                if (_fontSize < 36) setState(() => _fontSize += 2);
              },
            ),
            // Auto-scroll toggle
            IconButton(
              icon: Icon(
                _isAutoScrolling ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: _isAutoScrolling ? StageTheme.electricGreen : StageTheme.amberGold,
                size: 32,
              ),
              tooltip: _isAutoScrolling ? "Pausar Scroll" : "Iniciar Scroll Automático",
              onPressed: _toggleAutoScroll,
            ),
          ]
        ],
      ),
      body: Column(
        children: [
          // Barra de búsqueda
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Buscar canción o artista...",
                      filled: true,
                      fillColor: StageTheme.surfaceElevated,
                      prefixIcon: const Icon(Icons.search, color: StageTheme.flameOrange),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _searchLyrics(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _searchLyrics,
                  child: _isLoading
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

          // Control de velocidad de scroll si está activo
          if (_currentLyrics != null && _isAutoScrolling)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: StageTheme.surfaceElevated,
              child: Row(
                children: [
                  const Icon(Icons.speed, color: StageTheme.amberGold, size: 20),
                  const SizedBox(width: 8),
                  const Text("Velocidad Scroll:", style: TextStyle(color: StageTheme.textSecondary)),
                  Expanded(
                    child: Slider(
                      value: _scrollSpeed,
                      min: 0.5,
                      max: 4.0,
                      divisions: 7,
                      label: "${_scrollSpeed}x",
                      onChanged: (val) {
                        setState(() => _scrollSpeed = val);
                        if (_isAutoScrolling) _startAutoScroll();
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Resultados de búsqueda o vista de la letra
          Expanded(
            child: _searchResults.isNotEmpty
                ? ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final item = _searchResults[index];
                      return ListTile(
                        leading: const Icon(Icons.music_note, color: StageTheme.flameOrange),
                        title: Text(item["track_name"] ?? "Sin título",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Text(item["artist_name"] ?? "Artista desconocido",
                            style: const TextStyle(color: StageTheme.textSecondary)),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: StageTheme.textMuted),
                        onTap: () => _selectSong(item),
                      );
                    },
                  )
                : _currentLyrics != null
                    ? _buildLyricsView()
                    : const Center(
                        child: Text(
                          "Busca una canción para ensayar la letra",
                          style: TextStyle(color: StageTheme.textSecondary, fontSize: 16),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsView() {
    final trackName = _currentLyrics!["track_name"] ?? "";
    final artistName = _currentLyrics!["artist_name"] ?? "";
    final plainLyrics = _currentLyrics!["plain_lyrics"] as String?;
    final lines = _currentLyrics!["lines"] as List<dynamic>?;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: StageTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  trackName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: StageTheme.amberGold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  artistName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: StageTheme.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (lines != null && lines.isNotEmpty)
            ...lines.map((line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    line["text"] ?? "",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: _fontSize,
                      height: 1.6,
                      color: StageTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ))
          else if (plainLyrics != null && plainLyrics.isNotEmpty)
            Text(
              plainLyrics,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _fontSize,
                height: 1.6,
                color: StageTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            const Center(
              child: Text(
                "No hay letra disponible para esta canción.",
                style: TextStyle(color: StageTheme.textMuted, fontSize: 16),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
