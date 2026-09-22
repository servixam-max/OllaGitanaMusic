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
  bool _isLoadingLyrics = false;
  bool _showCached = false;
  String? _searchError;
  Timer? _debounceTimer;

  // Controles de escenario
  double _fontSize = 20.0;
  bool _isAutoScrolling = false;
  double _scrollSpeed = 1.0; // Velocidad manual (fallback si no hay letra sincronizada)
  Timer? _scrollTimer;

  // Modo karaoke sincronizado (usa los tiempos LRC)
  Timer? _karaokeTimer;
  Stopwatch? _karaokeClock;
  int _activeLineIndex = -1;
  int _karaokeOffsetMs = 0; // Ajuste fino de sincronía (+ = la letra va más lenta)
  final Map<int, GlobalKey> _lineKeys = {};

  List<dynamic> get _syncedLines => (_currentLyrics?["lines"] as List<dynamic>?) ?? [];

  bool get _hasSyncedLyrics => _syncedLines.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadCached();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _stopAutoScroll();
    _stopKaraoke();
    super.dispose();
  }

  // Búsqueda en vivo con debounce: al escribir 3+ letras busca sola
  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _debounceTimer?.cancel();
    if (query.length < 3) {
      if (_searchResults.isNotEmpty || _searchError != null) {
        setState(() {
          _searchResults = [];
          _searchError = null;
        });
      }
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 500), () => _searchLyrics(silent: true));
  }

  Future<void> _loadCached() async {
    final cached = await _api.getCachedLyrics();
    if (mounted) setState(() => _cachedSongs = cached);
  }

  Future<void> _searchLyrics({bool silent = false}) async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    if (!silent) {
      setState(() {
        _isLoading = true;
        _showCached = false;
        _searchError = null;
      });
    } else {
      setState(() => _showCached = false);
    }

    final results = await _api.searchLyrics(query);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isLoading = false;
      _searchError = results.isEmpty
          ? "No se encontraron letras para \"$query\". Prueba con el nombre del artista o revisa la conexión."
          : null;
    });
  }

  /// Selecciona una canción y refuerza la letra con /lyrics/get para garantizar
  /// la versión sincronizada (karaoke) cuando exista.
  Future<void> _selectSong(Map<String, dynamic> song) async {
    _stopAutoScroll();
    _stopKaraoke();
    _debounceTimer?.cancel();

    final hasSynced = (song["lines"] as List<dynamic>?)?.isNotEmpty == true;
    final trackName = song["track_name"] as String? ?? "";
    final artistName = song["artist_name"] as String? ?? "";

    setState(() {
      _currentLyrics = song;
      _searchResults = [];
      _showCached = false;
      _searchError = null;
      _activeLineIndex = -1;
      _karaokeOffsetMs = 0;
      _lineKeys.clear();
      // Solo mostramos el spinner si la letra no trae sincronía todavía
      _isLoadingLyrics = !hasSynced && trackName.isNotEmpty;
    });

    Map<String, dynamic> finalSong = song;

    if (!hasSynced && trackName.isNotEmpty && artistName.isNotEmpty) {
      // Refuerzo: pedir la versión exacta sincronizada
      final better = await _api.getLyrics(trackName, artistName);
      if (better != null) {
        final betterLines = (better["lines"] as List<dynamic>?)?.isNotEmpty == true;
        final currentPlain = (song["plain_lyrics"] as String?)?.isNotEmpty == true;
        final betterPlain = (better["plain_lyrics"] as String?)?.isNotEmpty == true;
        if (betterLines || (!currentPlain && betterPlain)) {
          finalSong = better;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _currentLyrics = finalSong;
      _isLoadingLyrics = false;
    });

    _api.cacheLyrics(finalSong);
    _loadCached();
  }

  /// Vuelve atrás a la lista de búsqueda/guardadas
  void _goBack() {
    _stopAutoScroll();
    _stopKaraoke();
    setState(() {
      _currentLyrics = null;
      _activeLineIndex = -1;
      _karaokeOffsetMs = 0;
      _lineKeys.clear();
    });
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
      final elapsedMs = (_karaokeClock?.elapsedMilliseconds ?? 0) - _karaokeOffsetMs;
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
      // La canción sigue tras la última línea: solo detenemos si ya pasó de largo
      if (newIndex >= lines.length - 1) {
        final lastTime = (lines.last["time_ms"] as num?)?.toInt() ?? 0;
        if (elapsedMs > lastTime + 15000) {
          _stopKaraoke();
          if (mounted) setState(() {});
        }
      }
    });
  }

  void _stopKaraoke() {
    _karaokeTimer?.cancel();
    _karaokeTimer = null;
    _karaokeClock?.stop();
  }

  /// Reinicia el karaoke desde el principio
  void _restartKaraoke() {
    _stopKaraoke();
    setState(() => _activeLineIndex = -1);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    _startKaraoke();
    if (mounted) setState(() {});
  }

  /// Ajustar la sincronía si la letra va adelantada o atrasada
  void _adjustSync(int deltaMs) {
    setState(() => _karaokeOffsetMs += deltaMs);
    if (_karaokeTimer != null) {
      // Reiniciar el reloj manteniendo el ajuste
      _restartKaraoke();
    }
  }

  void _scrollToLine(int index) {
    if (index < 0) return;
    final key = _lineKeys[index];
    final ctx = key?.currentContext;
    if (ctx == null || !_scrollController.hasClients) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    try {
      final position = box.localToGlobal(Offset.zero, ancestor: ctx.findAncestorRenderObjectOfType<RenderBox>());
      final viewport = _scrollController.position.viewportDimension;
      final target = _scrollController.offset + position.dy - viewport * 0.35;
      _scrollController.animateTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    } catch (_) {}
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

  /// Confirmación antes de borrar una letra guardada (con opción de deshacer)
  Future<void> _confirmDeleteCached(Map<String, dynamic> item) async {
    final title = item["track_name"] ?? "esta letra";
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StageTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: StageTheme.border),
        ),
        title: const Text("Quitar letra guardada"),
        content: Text("¿Quieres quitar \"$title\" de tus letras guardadas?\n\nPodrás volver a buscarla y guardarla de nuevo cuando quieras."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar", style: TextStyle(color: StageTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: StageTheme.alertRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Quitar"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _api.removeCachedLyrics(item["id"]);
    await _loadCached();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("\"$title\" quitada de guardadas"),
        action: SnackBarAction(
          label: "Deshacer",
          textColor: StageTheme.amberGold,
          onPressed: () async {
            await _api.cacheLyrics(item);
            await _loadCached();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // El botón atrás de Android vuelve a la lista en lugar de cerrar la app
      canPop: _currentLyrics == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _currentLyrics != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: "Volver a la lista",
                  onPressed: _goBack,
                )
              : null,
          title: Text(_currentLyrics != null ? "Letra" : "Letras en Directo"),
          actions: [
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
              if (_hasSyncedLyrics) ...[
                IconButton(
                  icon: Icon(
                    Icons.mic,
                    color: _karaokeTimer != null ? StageTheme.electricGreen : StageTheme.textSecondary,
                  ),
                  tooltip: _karaokeTimer != null ? "Detener karaoke" : "Modo Karaoke sincronizado",
                  onPressed: _toggleKaraoke,
                ),
                IconButton(
                  icon: const Icon(Icons.restart_alt),
                  tooltip: "Reiniciar karaoke desde el principio",
                  onPressed: _restartKaraoke,
                ),
                PopupMenuButton<int>(
                  tooltip: "Ajustar sincronía de la letra",
                  icon: const Icon(Icons.tune, color: StageTheme.amberGold),
                  onSelected: _adjustSync,
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: -2000, child: Text("La letra va muy adelantada (-2 s)")),
                    const PopupMenuItem(value: -1000, child: Text("Adelantar 1 s")),
                    const PopupMenuItem(value: -500, child: Text("Adelantar 0,5 s")),
                    const PopupMenuItem(value: 0, child: Text("Sincronía original")),
                    const PopupMenuItem(value: 500, child: Text("Atrasar 0,5 s")),
                    const PopupMenuItem(value: 1000, child: Text("Atrasar 1 s")),
                    const PopupMenuItem(value: 2000, child: Text("La letra va muy atrasada (+2 s)")),
                  ],
                ),
              ] else
                IconButton(
                  icon: Icon(
                    _isAutoScrolling ? Icons.pause_circle_filled : Icons.play_circle_fill,
                    color: _isAutoScrolling ? StageTheme.electricGreen : StageTheme.amberGold,
                    size: 32,
                  ),
                  tooltip: _isAutoScrolling ? "Pausar Scroll" : "Iniciar Scroll Automático",
                  onPressed: _toggleAutoScroll,
                ),
            ],
            const ProfileAppBarButton(),
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
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18, color: StageTheme.textMuted),
                                tooltip: "Limpiar búsqueda",
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchResults = [];
                                    _searchError = null;
                                  });
                                },
                              )
                            : null,
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
                    onPressed: _isLoading ? null : () => _searchLyrics(),
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
            if (_cachedSongs.isNotEmpty && _currentLyrics == null)
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
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: StageTheme.electricGreen, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _karaokeOffsetMs == 0
                            ? "Karaoke sincronizado activo — la línea actual se resalta sola"
                            : "Karaoke activo · ajuste de sincronía: ${_karaokeOffsetMs > 0 ? '+' : ''}${_karaokeOffsetMs}ms",
                        style: const TextStyle(color: StageTheme.electricGreen, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
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
                        final hasSynced = (item["lines"] as List<dynamic>?)?.isNotEmpty == true ||
                            item["has_synced"] == true;
                        return ListTile(
                          leading: Icon(
                            hasSynced ? Icons.mic : Icons.music_note,
                            color: hasSynced ? StageTheme.electricGreen : StageTheme.flameOrange,
                          ),
                          title: Text(item["track_name"] ?? "Sin título",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Row(
                            children: [
                              Expanded(
                                child: Text(item["artist_name"] ?? "Artista desconocido",
                                    style: const TextStyle(color: StageTheme.textSecondary),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (hasSynced)
                                const Text("Karaoke",
                                    style: TextStyle(color: StageTheme.electricGreen, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: StageTheme.textMuted),
                          onTap: () => _selectSong(item),
                        );
                      },
                    )
                  : _showCached
                      ? ListView.builder(
                          itemCount: _cachedSongs.length,
                          itemBuilder: (context, index) {
                            final item = _cachedSongs[index];
                            final hasSynced = (item["lines"] as List<dynamic>?)?.isNotEmpty == true;
                            return ListTile(
                              leading: Icon(
                                hasSynced ? Icons.mic : Icons.download_done,
                                color: hasSynced ? StageTheme.electricGreen : StageTheme.textSecondary,
                              ),
                              title: Text(item["track_name"] ?? "Sin título",
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(item["artist_name"] ?? "",
                                  style: const TextStyle(color: StageTheme.textSecondary)),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: StageTheme.alertRed),
                                tooltip: "Quitar de guardadas",
                                onPressed: () => _confirmDeleteCached(item),
                              ),
                              onTap: () => _selectSong(item),
                            );
                          },
                        )
                      : _currentLyrics != null
                          ? _isLoadingLyrics
                              ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(color: StageTheme.flameOrange),
                                      SizedBox(height: 12),
                                      Text("Buscando la letra sincronizada...",
                                          style: TextStyle(color: StageTheme.textSecondary, fontSize: 13)),
                                    ],
                                  ),
                                )
                              : _buildLyricsView()
                          : _searchError != null
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.search_off, size: 48, color: StageTheme.textMuted),
                                        const SizedBox(height: 12),
                                        Text(
                                          _searchError!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: StageTheme.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(32),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.mic_none, size: 64, color: StageTheme.textMuted),
                                        SizedBox(height: 16),
                                        Text(
                                          "Busca una canción para ensayar la letra",
                                          style: TextStyle(color: StageTheme.textSecondary, fontSize: 16),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          "Las canciones con el icono 🎤 incluyen letra sincronizada (karaoke).",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: StageTheme.textMuted, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
            ),
          ],
        ),
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
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tarjeta Header de Canción con degradado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: StageTheme.cardGradient,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: StageTheme.border),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: StageTheme.flameGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mic_rounded, size: 16, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        trackName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  artistName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: StageTheme.textSecondary, fontWeight: FontWeight.w500),
                ),
                if (_hasSyncedLyrics) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: StageTheme.electricGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: StageTheme.electricGreen.withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      "KARAOKE SINCRONIZADO LRC",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: StageTheme.electricGreen, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Letra sincronizada o texto plano
          if (lines.isNotEmpty)
            ...lines.asMap().entries.map((entry) {
              final index = entry.key;
              final line = entry.value;
              final isActive = index == _activeLineIndex;
              _lineKeys.putIfAbsent(index, () => GlobalKey());

              return Padding(
                key: _lineKeys[index],
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: isActive ? 10 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? StageTheme.flameOrange.withValues(alpha: 0.20)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isActive ? StageTheme.flameOrange.withValues(alpha: 0.7) : Colors.transparent,
                      width: 1.2,
                    ),
                    boxShadow: isActive ? StageTheme.glowOrange : null,
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: _fontSize * (isActive ? 1.15 : 1.0),
                      height: 1.5,
                      color: _karaokeTimer != null
                          ? (isActive ? Colors.white : StageTheme.textMuted.withValues(alpha: 0.6))
                          : StageTheme.textPrimary,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                      letterSpacing: isActive ? 0.3 : 0,
                    ),
                    child: Text(
                      line["text"] ?? "",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            })
          else if (plainLyrics != null && plainLyrics.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: StageTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: StageTheme.border),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: StageTheme.amberGold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "LETRA SIN SINCRONIZAR — usa el auto-scroll manual",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: StageTheme.amberGold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    plainLyrics,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: _fontSize,
                      height: 1.7,
                      color: StageTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text(
                  "No hay letra disponible para esta canción.",
                  style: TextStyle(color: StageTheme.textMuted, fontSize: 16),
                ),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
