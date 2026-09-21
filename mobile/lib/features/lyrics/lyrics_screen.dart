import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/stage_theme.dart';
import '../../core/widgets/profile_app_bar_button.dart';

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
  List<Map<String, dynamic>> _cachedSongs = [];
  Map<String, dynamic>? _currentLyrics;
  bool _isLoading = false;
  bool _showCached = false;

  // Controles de escenario
  double _fontSize = 20.0;
  bool _isAutoScrolling = false;
  double _scrollSpeed = 1.0; // Velocidad manual (fallback si no hay letra sincronizada)
  Timer? _scrollTimer;

  // Modo karaoke sincronizado (usa los tiempos LRC)
  Timer? _karaokeTimer;
  Stopwatch? _karaokeClock;
  int _activeLineIndex = -1;
  final Map<int, GlobalKey> _lineKeys = {};

  List<dynamic> get _syncedLines => (_currentLyrics?["lines"] as List<dynamic>?) ?? [];

  bool get _hasSyncedLyrics => _syncedLines.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadCached();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _stopAutoScroll();
    _stopKaraoke();
    super.dispose();
  }

  Future<void> _loadCached() async {
    final cached = await _api.getCachedLyrics();
    if (mounted) setState(() => _cachedSongs = cached);
  }

  Future<void> _searchLyrics() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _showCached = false;
    });
    final results = await _api.searchLyrics(query);
    setState(() {
      _searchResults = results;
      _isLoading = false;
    });
  }

  void _selectSong(Map<String, dynamic> song) {
    _api.cacheLyrics(song);
    _stopAutoScroll();
    _stopKaraoke();
    setState(() {
      _currentLyrics = song;
      _searchResults = [];
      _showCached = false;
      _activeLineIndex = -1;
      _lineKeys.clear();
    });
    _loadCached();
  }

  // --- Modo Karaoke: resalta la línea actual y hace scroll automático por timestamps ---
  void _toggleKaraoke() {
    if (_isAutoScrolling) _stopAutoScroll();
    setState(() {
      _isAutoScrolling = false;
      if (_karaokeTimer != null) {
        _stopKaraoke();
      } else {
        _startKaraoke();
      }
    });
  }

  void _startKaraoke() {
    if (!_hasSyncedLyrics) return;
    _karaokeClock = Stopwatch()..start();
    _karaokeTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final elapsedMs = _karaokeClock?.elapsedMilliseconds ?? 0;
      int newIndex = -1;
      final lines = _syncedLines;
      for (int i = 0; i < lines.length; i++) {
        final t = (lines[i]["time_ms"] as num?)?.toInt() ?? 0;
        if (elapsedMs >= t) {
          newIndex = i;
        } else {
          break;
        }
      }
      if (newIndex != _activeLineIndex && mounted) {
        setState(() => _activeLineIndex = newIndex);
        _scrollToLine(newIndex);
      }
      // Fin de letra
      if (newIndex == lines.length - 1) {
        _stopKaraoke();
        if (mounted) setState(() {});
      }
    });
  }

  void _stopKaraoke() {
    _karaokeTimer?.cancel();
    _karaokeTimer = null;
    _karaokeClock?.stop();
  }

  void _scrollToLine(int index) {
    if (index < 0) return;
    final key = _lineKeys[index];
    final context = key?.currentContext;
    if (context == null || !_scrollController.hasClients) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final position = box.localToGlobal(Offset.zero, ancestor: context.findAncestorRenderObjectOfType<RenderBox>());
    final viewport = _scrollController.position.viewportDimension;
    final target = _scrollController.offset + position.dy - viewport * 0.35;
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  // --- Auto-scroll manual por velocidad (para letras sin sincronizar) ---
  void _toggleAutoScroll() {
    if (_karaokeTimer != null) {
      _stopKaraoke();
    }
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
          const ProfileAppBarButton(),
          if (_currentLyrics != null) ...[
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
            if (_hasSyncedLyrics)
              IconButton(
                icon: Icon(
                  Icons.mic,
                  color: _karaokeTimer != null ? StageTheme.electricGreen : StageTheme.textSecondary,
                ),
                tooltip: _karaokeTimer != null ? "Detener karaoke" : "Modo Karaoke sincronizado",
                onPressed: _toggleKaraoke,
              ),
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

          // Acceso a letras guardadas offline
          if (_cachedSongs.isNotEmpty && _currentLyrics == null && _searchResults.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: Icon(_showCached ? Icons.expand_less : Icons.download_done, size: 18),
                    label: Text(
                      _showCached ? "Ocultar guardadas" : "Letras guardadas (${_cachedSongs.length})",
                    ),
                    style: TextButton.styleFrom(foregroundColor: StageTheme.amberGold),
                    onPressed: () => setState(() => _showCached = !_showCached),
                  ),
                ],
              ),
            ),

          // Control de velocidad de scroll si está activo (manual)
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

          // Aviso de modo karaoke activo
          if (_currentLyrics != null && _karaokeTimer != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: StageTheme.electricGreen.withValues(alpha: 0.12),
              child: const Row(
                children: [
                  Icon(Icons.mic, color: StageTheme.electricGreen, size: 18),
                  SizedBox(width: 8),
                  Text(
                    "Karaoke sincronizado activo — la línea actual se resalta sola",
                    style: TextStyle(color: StageTheme.electricGreen, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

          // Resultados de búsqueda, caché o vista de la letra
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((item["lines"] as List<dynamic>?)?.isNotEmpty == true)
                              const Icon(Icons.mic, size: 16, color: StageTheme.electricGreen),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward_ios, size: 16, color: StageTheme.textMuted),
                          ],
                        ),
                        onTap: () => _selectSong(item),
                      );
                    },
                  )
                : _showCached
                    ? ListView.builder(
                        itemCount: _cachedSongs.length,
                        itemBuilder: (context, index) {
                          final item = _cachedSongs[index];
                          return ListTile(
                            leading: const Icon(Icons.download_done, color: StageTheme.electricGreen),
                            title: Text(item["track_name"] ?? "Sin título",
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(item["artist_name"] ?? "",
                                style: const TextStyle(color: StageTheme.textSecondary)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: StageTheme.alertRed),
                              onPressed: () async {
                                await _api.removeCachedLyrics(item["id"]);
                                _loadCached();
                              },
                            ),
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
    final lines = _syncedLines;

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
          if (lines.isNotEmpty)
            ...lines.asMap().entries.map((entry) {
              final index = entry.key;
              final line = entry.value;
              final isActive = index == _activeLineIndex;
              _lineKeys.putIfAbsent(index, () => GlobalKey());
              return Padding(
                key: _lineKeys[index],
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: _fontSize * (isActive ? 1.12 : 1.0),
                    height: 1.6,
                    color: _karaokeTimer != null
                        ? (isActive ? StageTheme.amberGold : StageTheme.textMuted)
                        : StageTheme.textPrimary,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  ),
                  child: Text(
                    line["text"] ?? "",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            })
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
