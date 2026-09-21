import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/stage_theme.dart';
import '../../core/widgets/profile_app_bar_button.dart';

enum _ViewMode { compact, cards }

class RepertoireScreen extends StatefulWidget {
  const RepertoireScreen({super.key});

  @override
  State<RepertoireScreen> createState() => _RepertoireScreenState();
}

class _RepertoireScreenState extends State<RepertoireScreen> {
  final ApiClient _api = ApiClient();
  final AudioPlayer _previewPlayer = AudioPlayer();

  List<dynamic> _songs = [];
  bool _isLoading = true;
  String _selectedFilter = "todas"; // todas, propuesta, para_ensayar, en_repertorio, descartada
  _ViewMode _viewMode = _ViewMode.compact;

  int? _playingPreviewSongId;
  WebSocketReconnect? _wsChannel;
  bool _wsConnected = true;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _isSearchExpanded = false;

  static const List<(String, String, IconData)> _filters = [
    ("todas", "Todas", Icons.all_inclusive_rounded),
    ("propuesta", "Propuestas", Icons.thumb_up_alt_rounded),
    ("para_ensayar", "Ensayar", Icons.queue_music_rounded),
    ("en_repertorio", "Repertorio", Icons.library_music_rounded),
    ("descartada", "Descartadas", Icons.thumb_down_alt_rounded),
  ];

  List<dynamic> get _filteredSongs {
    if (_searchQuery.trim().isEmpty) return _songs;
    final q = _searchQuery.toLowerCase();
    return _songs.where((song) {
      final title = (song["title"] ?? "").toString().toLowerCase();
      final artist = (song["artist"] ?? "").toString().toLowerCase();
      return title.contains(q) || artist.contains(q);
    }).toList();
  }

  Map<String, int> get _filterCounts {
    final counts = <String, int>{"todas": _songs.length};
    for (final f in _filters) {
      if (f.$1 != "todas") {
        counts[f.$1] = _songs.where((s) => s["status"] == f.$1).length;
      }
    }
    return counts;
  }

  dynamic get _currentlyPlayingSong {
    if (_playingPreviewSongId == null) return null;
    try {
      return _songs.firstWhere((s) => s["id"] == _playingPreviewSongId);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSongs();
    _initWebSocket();

    _previewPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        setState(() => _playingPreviewSongId = null);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _previewPlayer.dispose();
    _wsChannel?.dispose();
    super.dispose();
  }

  void _initWebSocket() {
    _wsChannel = _api.createReconnectingSocket(
      "/ws/repertoire",
      onStatusChange: (connected) {
        if (mounted) setState(() => _wsConnected = connected);
      },
      onMessage: (message) {
        try {
          final event = jsonDecode(message);
          final eventType = event["event"] as String?;
          if (eventType == "song_added" || eventType == "vote_updated" ||
              eventType == "status_changed" || eventType == "song_deleted") {
            _loadSongs(silent: true);
          }
        } catch (_) {}
      },
    );
  }

  Future<void> _loadSongs({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final statusFilter = _selectedFilter == "todas" ? null : _selectedFilter;
    final songs = await _api.getRepertoireSongs(status: statusFilter);
    if (mounted) {
      setState(() {
        _songs = songs;
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePreview(int songId, String? previewUrl) async {
    if (previewUrl == null || previewUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Esta canción no cuenta con snippet de 30s disponible")),
        );
      }
      return;
    }

    if (_playingPreviewSongId == songId) {
      await _previewPlayer.stop();
      if (mounted) setState(() => _playingPreviewSongId = null);
    } else {
      await _previewPlayer.stop();
      if (mounted) setState(() => _playingPreviewSongId = songId);
      try {
        final fullUrl = _api.getFullUrl(previewUrl);
        await _previewPlayer.setUrl(fullUrl);
        await _previewPlayer.play();
      } catch (e) {
        print("[Repertoire] Error reproduciendo preview $songId: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No se pudo reproducir el preview de audio")),
          );
          setState(() => _playingPreviewSongId = null);
        }
      }
    }
  }

  Future<void> _vote(int songId, int rating) async {
    final success = await _api.voteSong(songId, rating);
    if (success) _loadSongs(silent: true);
  }

  Future<void> _changeStatus(int songId, String newStatus) async {
    final success = await _api.updateSongStatus(songId, newStatus);
    if (success) _loadSongs(silent: true);
  }

  Future<void> _confirmDeleteSong(int songId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StageTheme.surface,
        title: const Text("Eliminar Canción"),
        content: Text("¿Deseas eliminar '$title' de la lista de propuestas?"),
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
      final success = await _api.deleteSong(songId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: success ? StageTheme.electricGreen : StageTheme.alertRed,
            content: Text(success ? "'$title' eliminada correctamente" : "No se pudo eliminar la canción"),
          ),
        );
        if (success) _loadSongs();
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "propuesta":
        return StageTheme.amberGold;
      case "para_ensayar":
        return StageTheme.neonBlue;
      case "en_repertorio":
        return StageTheme.electricGreen;
      case "descartada":
        return StageTheme.textMuted;
      default:
        return StageTheme.textSecondary;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case "propuesta":
        return "Propuesta";
      case "para_ensayar":
        return "Ensayar";
      case "en_repertorio":
        return "Repertorio";
      case "descartada":
        return "Descartada";
      default:
        return status;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case "propuesta": return Icons.thumb_up_outlined;
      case "para_ensayar": return Icons.queue_music;
      case "en_repertorio": return Icons.library_music;
      case "descartada": return Icons.thumb_down_outlined;
      default: return Icons.circle_outlined;
    }
  }

  /// Menú inline de cambio de estado al tocar el chip directamente en la lista compacta
  void _showInlineStatusMenu(BuildContext context, dynamic song) {
    final statusValues = ["propuesta", "para_ensayar", "en_repertorio", "descartada"];
    final currentStatus = song["status"] as String? ?? "";
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        offset.dy + size.height + 4,
      ),
      color: StageTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: StageTheme.border),
      ),
      items: statusValues.map((status) {
        final color = _getStatusColor(status);
        final isSelected = status == currentStatus;
        return PopupMenuItem<String>(
          value: status,
          child: Row(
            children: [
              Icon(_getStatusIcon(status), color: color, size: 18),
              const SizedBox(width: 10),
              Text(
                _getStatusLabel(status),
                style: TextStyle(
                  color: isSelected ? color : StageTheme.textPrimary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (isSelected) ...[ const Spacer(), Icon(Icons.check, color: color, size: 16) ],
            ],
          ),
        );
      }).toList(),
    ).then((newStatus) {
      if (newStatus != null && newStatus != currentStatus) {
        _changeStatus(song["id"] as int, newStatus);
      }
    });
  }

  Future<void> _shareRepertoireOnWhatsApp() async {
    List<dynamic> songsToShare = _songs;
    if (songsToShare.isEmpty) {
      songsToShare = await _api.getRepertoireSongs();
    }
    if (songsToShare.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No hay canciones en el repertorio para compartir")),
        );
      }
      return;
    }

    final activeSongs = songsToShare.where((s) => s["status"] != "descartada").toList();
    final list = activeSongs.isNotEmpty ? activeSongs : songsToShare;

    final StringBuffer msg = StringBuffer();
    msg.writeln("🎸🔥 *OLLA GITANA - CATÁLOGO DE REPERTORIO* 🔥🎸\n");
    msg.writeln("¡Hola! 👋 Aquí tienes nuestro repertorio musical disponible para que elijas las canciones que más te gusten para tu evento o celebración:\n");
    msg.writeln("🎶 *CANCIONES DISPONIBLES:*");

    for (int i = 0; i < list.length; i++) {
      final song = list[i];
      final title = song["title"] ?? "Sin título";
      final artist = song["artist"] ?? "Artista";
      msg.writeln("${i + 1}. *${title.trim()}* - ${artist.trim()}");
    }

    msg.writeln();
    msg.writeln("✨ _Dinos cuáles son tus favoritas y preparamos el repertorio perfecto a tu medida._ 💃🕺🍻");
    msg.writeln("📞 *Contacto / Reservas Olla Gitana*");

    final whatsappUrl = "https://api.whatsapp.com/send?text=${Uri.encodeComponent(msg.toString())}";
    try {
      await launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se pudo abrir WhatsApp")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final songsToShow = _filteredSongs;
    final currentlyPlaying = _currentlyPlayingSong;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: _isSearchExpanded
            ? Container(
                height: 42,
                decoration: BoxDecoration(
                  color: StageTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: StageTheme.borderLight),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Buscar por título o artista...",
                    hintStyle: const TextStyle(color: StageTheme.textMuted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: StageTheme.flameOrange),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18, color: StageTheme.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = "");
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Repertorio",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: _api.userNameNotifier,
                    builder: (_, name, __) => Text(
                      _api.isUserIdentified ? "Músico: $name" : "Selecciona tu perfil de músico",
                      style: const TextStyle(fontSize: 11, color: StageTheme.textSecondary, fontWeight: FontWeight.normal),
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearchExpanded ? Icons.close_rounded : Icons.search_rounded,
              color: _isSearchExpanded ? StageTheme.flameOrange : StageTheme.textSecondary,
              size: 22,
            ),
            tooltip: _isSearchExpanded ? "Cerrar búsqueda" : "Buscar canción",
            onPressed: () {
              setState(() {
                _isSearchExpanded = !_isSearchExpanded;
                if (!_isSearchExpanded) {
                  _searchController.clear();
                  _searchQuery = "";
                }
              });
            },
          ),
          IconButton(
            icon: Icon(
              _viewMode == _ViewMode.compact ? Icons.grid_view_rounded : Icons.view_list_rounded,
              color: StageTheme.amberGold,
              size: 22,
            ),
            tooltip: _viewMode == _ViewMode.compact ? "Vista tarjetas" : "Vista compacta",
            onPressed: () => setState(() {
              _viewMode = _viewMode == _ViewMode.compact ? _ViewMode.cards : _ViewMode.compact;
            }),
          ),
          ProfileAppBarButton(onProfileChanged: () => setState(() {})),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: StageTheme.amberGold, size: 21),
            tooltip: "Compartir catálogo en WhatsApp",
            onPressed: _shareRepertoireOnWhatsApp,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Aviso si se pierde la sincronización en vivo
              if (!_wsConnected)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  color: StageTheme.alertRed.withValues(alpha: 0.15),
                  child: const Row(
                    children: [
                      Icon(Icons.cloud_off_rounded, size: 16, color: StageTheme.alertRed),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Sin conexión en vivo — reintentando sincronizar con la sala...",
                          style: TextStyle(color: StageTheme.alertRed, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

              // Filtros tipo Pill con badges y animación
              _buildFilterBar(),

              // Sub-barra informativa con contador elegante y filtros activos
              if (!_isLoading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Row(
                    children: [
                      Text(
                        _searchQuery.isNotEmpty
                            ? "${songsToShow.length} de ${_songs.length} canciones encontradas"
                            : "${songsToShow.length} ${_selectedFilter == 'todas' ? 'temas en total' : _getStatusLabel(_selectedFilter).toLowerCase()}",
                        style: const TextStyle(color: StageTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _searchQuery = "");
                          },
                          child: const Text(
                            "Limpiar filtro",
                            style: TextStyle(color: StageTheme.flameOrange, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),

              // Lista principal de canciones
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: StageTheme.flameOrange))
                    : songsToShow.isEmpty
                        ? RefreshIndicator(
                            onRefresh: () => _loadSongs(),
                            color: StageTheme.flameOrange,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: Padding(
                                padding: const EdgeInsets.all(36.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(height: 32),
                                    Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        color: StageTheme.surfaceElevated,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: StageTheme.border),
                                      ),
                                      child: const Icon(Icons.music_off_rounded, size: 36, color: StageTheme.textMuted),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? "Sin resultados para '$_searchQuery'"
                                          : "No hay canciones en esta categoría",
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: StageTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? "Prueba buscando con otro término o borra la búsqueda"
                                          : "Propón un tema para ensayar o añadir al repertorio",
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: StageTheme.textSecondary, fontSize: 13),
                                    ),
                                    const SizedBox(height: 20),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.add_rounded, size: 18),
                                      label: const Text("Proponer tema"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: StageTheme.flameOrange,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                      ),
                                      onPressed: () => _showAddSongDialog(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _loadSongs(),
                            color: StageTheme.flameOrange,
                            child: _viewMode == _ViewMode.compact
                                ? _buildCompactList(songsToShow)
                                : _buildCardList(songsToShow),
                          ),
              ),

              // Espacio reservado para el mini player flotante inferior
              if (currentlyPlaying != null) const SizedBox(height: 74),
            ],
          ),

          // Mini Reproductor Flotante persistente estilo Spotify/Apple Music
          if (currentlyPlaying != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _buildBottomPreviewPlayer(currentlyPlaying),
            ),
        ],
      ),
      floatingActionButton: currentlyPlaying != null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: StageTheme.flameOrange,
              elevation: 6,
              icon: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
              label: const Text("Proponer", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              onPressed: () => _showAddSongDialog(),
            ),
    );
  }

  /// Barra de filtros estilo Pill con conteos en vivo y degradado vibrante
  Widget _buildFilterBar() {
    final counts = _filterCounts;

    return Container(
      color: StageTheme.background,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: _filters.map((filter) {
            final key = filter.$1;
            final label = filter.$2;
            final icon = filter.$3;
            final isSelected = _selectedFilter == key;
            final count = counts[key] ?? 0;

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () {
                  setState(() => _selectedFilter = key);
                  _loadSongs();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: isSelected ? StageTheme.flameGradient : null,
                    color: isSelected ? null : StageTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? Colors.transparent : StageTheme.border,
                      width: 1,
                    ),
                    boxShadow: isSelected ? StageTheme.glowOrange : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 14,
                        color: isSelected ? Colors.white : StageTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : StageTheme.textSecondary,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.black.withValues(alpha: 0.25)
                                : StageTheme.background,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "$count",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : StageTheme.amberGold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Vista compacta: muchas canciones por pantalla, estilo lista de Spotify
  Widget _buildCompactList(List<dynamic> songs) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final isPlayingThis = _playingPreviewSongId == song["id"] as int?;
        final statusColor = _getStatusColor(song["status"] as String? ?? "");

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: isPlayingThis
                ? StageTheme.flameOrange.withValues(alpha: 0.12)
                : StageTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPlayingThis
                  ? StageTheme.flameOrange.withValues(alpha: 0.6)
                  : StageTheme.border,
              width: isPlayingThis ? 1.2 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Indicador de color lateral del estado
                Container(width: 4.5, color: statusColor),
                Expanded(
                  child: InkWell(
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
                    onTap: () => _showSongDetailSheet(song),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      child: Row(
                        children: [
                          // Portada pequeña con esquinas redondeadas
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: song["cover_url"] != null
                                ? Image.network(
                                    song["cover_url"] as String,
                                    width: 46,
                                    height: 46,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _placeholderCover(46),
                                  )
                                : _placeholderCover(46),
                          ),
                          const SizedBox(width: 11),
                          // Título y artista
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  song["title"] as String? ?? "",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isPlayingThis ? StageTheme.flameOrange : StageTheme.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  song["artist"] as String? ?? "",
                                  style: const TextStyle(color: StageTheme.textSecondary, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Rating y chip de estado interactivo
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, size: 13, color: StageTheme.amberGold),
                                  const SizedBox(width: 2),
                                  Text(
                                    "${(song["average_rating"] as num?)?.toStringAsFixed(1) ?? "0.0"}",
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              // Chip de estado interactivo rápido
                              GestureDetector(
                                onTap: () => _showInlineStatusMenu(context, song),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: statusColor.withValues(alpha: 0.5), width: 1),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _getStatusLabel(song["status"] as String? ?? ""),
                                        style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(Icons.arrow_drop_down, size: 12, color: statusColor),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 4),
                          // Botón Play/Pause circular moderno
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                            icon: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                gradient: isPlayingThis ? StageTheme.flameGradient : null,
                                color: isPlayingThis ? null : StageTheme.surface,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isPlayingThis ? Colors.transparent : StageTheme.border,
                                ),
                              ),
                              child: Icon(
                                isPlayingThis ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: isPlayingThis
                                    ? Colors.white
                                    : (song["preview_url"] != null ? StageTheme.flameOrange : StageTheme.textMuted),
                                size: 20,
                              ),
                            ),
                            onPressed: () => _togglePreview(song["id"] as int, song["preview_url"] as String?),
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
      },
    );
  }

  /// Vista tarjetas: más detallada, estilo tarjeta de streaming moderna
  Widget _buildCardList(List<dynamic> songs) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final isPlayingThis = _playingPreviewSongId == song["id"] as int?;
        final statusColor = _getStatusColor(song["status"] as String? ?? "");

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            gradient: StageTheme.cardGradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPlayingThis ? StageTheme.flameOrange : StageTheme.border,
              width: isPlayingThis ? 1.5 : 1.0,
            ),
            boxShadow: isPlayingThis ? StageTheme.glowOrange : [
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Carátula grande con esquinas suaves
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: song["cover_url"] != null
                          ? Image.network(
                              song["cover_url"] as String,
                              width: 68,
                              height: 68,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholderCover(68),
                            )
                          : _placeholderCover(68),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song["title"] as String? ?? "",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, letterSpacing: -0.2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song["artist"] as String? ?? "",
                            style: const TextStyle(color: StageTheme.textSecondary, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              _getStatusLabel(song["status"] as String? ?? ""),
                              style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 44,
                      icon: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: isPlayingThis ? StageTheme.flameGradient : null,
                          color: isPlayingThis ? null : StageTheme.surfaceElevated,
                          shape: BoxShape.circle,
                          border: Border.all(color: isPlayingThis ? Colors.transparent : StageTheme.border),
                        ),
                        child: Icon(
                          isPlayingThis ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: isPlayingThis ? Colors.white : StageTheme.flameOrange,
                          size: 26,
                        ),
                      ),
                      onPressed: () => _togglePreview(song["id"] as int, song["preview_url"] as String?),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: StageTheme.border, height: 1),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RatingBar.builder(
                          initialRating: (song["average_rating"] as num?)?.toDouble() ?? 0.0,
                          minRating: 1,
                          direction: Axis.horizontal,
                          allowHalfRating: true,
                          itemCount: 5,
                          itemSize: 20,
                          itemPadding: const EdgeInsets.symmetric(horizontal: 1.0),
                          itemBuilder: (context, _) => const Icon(Icons.star_rounded, color: StageTheme.amberGold),
                          onRatingUpdate: (rating) => _vote(song["id"] as int, rating.toInt()),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Nota: ${song["average_rating"]} (${song["total_votes"]} votos)",
                          style: const TextStyle(color: StageTheme.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildStatusMenu(song),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: StageTheme.alertRed, size: 20),
                          tooltip: "Eliminar canción",
                          onPressed: () => _confirmDeleteSong(song["id"] as int, song["title"] as String? ?? "Canción"),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Mini Reproductor Persistente en la parte inferior cuando suena un snippet
  Widget _buildBottomPreviewPlayer(dynamic song) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: StageTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StageTheme.flameOrange, width: 1.5),
        boxShadow: StageTheme.glowOrange,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: song["cover_url"] != null
                ? Image.network(
                    song["cover_url"] as String,
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholderCover(42),
                  )
                : _placeholderCover(42),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.graphic_eq_rounded, size: 14, color: StageTheme.flameOrange),
                    const SizedBox(width: 4),
                    const Text(
                      "REPRODUCIENDO SNIPPET 30s",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: StageTheme.flameOrange, letterSpacing: 0.5),
                    ),
                  ],
                ),
                Text(
                  song["title"] ?? "",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  song["artist"] ?? "",
                  style: const TextStyle(fontSize: 11, color: StageTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.stop_circle_rounded, color: StageTheme.flameOrange, size: 36),
            tooltip: "Detener preview",
            onPressed: () => _togglePreview(song["id"] as int, song["preview_url"] as String?),
          ),
        ],
      ),
    );
  }

  Widget _placeholderCover(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: StageTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(size * 0.125),
      ),
      child: Icon(Icons.music_note, color: StageTheme.flameOrange, size: size * 0.5),
    );
  }

  Widget _buildStatusMenu(dynamic song) {
    final statusColor = _getStatusColor(song["status"] as String? ?? "");
    return PopupMenuButton<String>(
      onSelected: (newStatus) => _changeStatus(song["id"] as int, newStatus),
      itemBuilder: (ctx) => [
        const PopupMenuItem(value: "propuesta", child: Text("Propuesta")),
        const PopupMenuItem(value: "para_ensayar", child: Text("Para Ensayar")),
        const PopupMenuItem(value: "en_repertorio", child: Text("En Repertorio")),
        const PopupMenuItem(value: "descartada", child: Text("Descartada")),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _getStatusLabel(song["status"] as String? ?? ""),
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: statusColor, size: 16),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet con detalle completo de la canción (accesible desde la vista compacta)
  void _showSongDetailSheet(dynamic song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: StageTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pill handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: StageTheme.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Portada grande
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: song["cover_url"] != null
                            ? Image.network(
                                song["cover_url"] as String,
                                width: 90,
                                height: 90,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _placeholderCover(90),
                              )
                            : _placeholderCover(90),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song["title"] as String? ?? "",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song["artist"] as String? ?? "",
                              style: const TextStyle(color: StageTheme.textSecondary, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Propuesta por: ${song["proposed_by"]}",
                              style: const TextStyle(color: StageTheme.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Play preview
                  ElevatedButton.icon(
                    icon: Icon(
                      _playingPreviewSongId == song["id"] ? Icons.stop_circle : Icons.play_circle_fill,
                      size: 22,
                    ),
                    label: Text(
                      _playingPreviewSongId == song["id"] ? "Parar preview" : "Escuchar preview 30s",
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: song["preview_url"] != null ? StageTheme.flameOrange : StageTheme.surfaceElevated,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    onPressed: () {
                      _togglePreview(song["id"] as int, song["preview_url"] as String?);
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 12),

                  // Rating y estado
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RatingBar.builder(
                            initialRating: (song["average_rating"] as num?)?.toDouble() ?? 0.0,
                            minRating: 1,
                            direction: Axis.horizontal,
                            allowHalfRating: true,
                            itemCount: 5,
                            itemSize: 26,
                            itemPadding: const EdgeInsets.symmetric(horizontal: 1.0),
                            itemBuilder: (context, _) => const Icon(Icons.star, color: StageTheme.amberGold),
                            onRatingUpdate: (rating) {
                              _vote(song["id"] as int, rating.toInt());
                            },
                          ),
                          Text(
                            "Media: ${song["average_rating"]} (${song["total_votes"]} votos)",
                            style: const TextStyle(color: StageTheme.textSecondary, fontSize: 12),
                          ),
                          if ((song["votes"] as List<dynamic>?)?.isNotEmpty == true) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: (song["votes"] as List<dynamic>).map((v) {
                                final name = v["user_name"] ?? "";
                                final rating = v["rating"] ?? 0;
                                final isMe = name.toString().toLowerCase() == _api.userName.toLowerCase();
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? StageTheme.amberGold.withValues(alpha: 0.2)
                                        : StageTheme.surfaceElevated,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isMe ? StageTheme.amberGold : StageTheme.border,
                                    ),
                                  ),
                                  child: Text(
                                    "$name: $rating★",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                                      color: isMe ? StageTheme.amberGold : StageTheme.textSecondary,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                      _buildStatusMenu(song),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Botón eliminar
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, color: StageTheme.alertRed),
                    label: const Text("Eliminar de la lista", style: TextStyle(color: StageTheme.alertRed)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmDeleteSong(song["id"] as int, song["title"] as String? ?? "Canción");
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddSongDialog() {
    final TextEditingController searchCtrl = TextEditingController();
    final AudioPlayer dialogPlayer = AudioPlayer();
    List<dynamic> spotifyResults = [];
    bool searching = false;
    String? playingUrl;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: StageTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            dialogPlayer.playerStateStream.listen((state) {
              if (state.processingState == ProcessingState.completed) {
                setModalState(() => playingUrl = null);
              }
            });

            Future<void> doSearch() async {
              final q = searchCtrl.text.trim();
              if (q.isEmpty) return;
              setModalState(() => searching = true);
              final res = await _api.searchSpotify(q);
              setModalState(() {
                spotifyResults = res;
                searching = false;
              });
            }

            Future<void> toggleDialogPreview(String? url) async {
              if (url == null || url.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text("Esta canción no tiene preview de 30s disponible")),
                );
                return;
              }
              if (playingUrl == url) {
                await dialogPlayer.stop();
                setModalState(() => playingUrl = null);
              } else {
                await dialogPlayer.stop();
                setModalState(() => playingUrl = url);
                try {
                  final fullUrl = _api.getFullUrl(url);
                  await dialogPlayer.setUrl(fullUrl);
                  await dialogPlayer.play();
                } catch (_) {
                  setModalState(() => playingUrl = null);
                }
              }
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollCtrl) => Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pill handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: StageTheme.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const Text(
                      "Proponer Tema para Olla Gitana",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchCtrl,
                            decoration: InputDecoration(
                              hintText: "Buscar canción o artista...",
                              filled: true,
                              fillColor: StageTheme.surfaceElevated,
                              prefixIcon: const Icon(Icons.search, color: StageTheme.flameOrange),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onSubmitted: (_) => doSearch(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: searching ? null : doSearch,
                          child: searching
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text("Buscar"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: spotifyResults.isEmpty
                          ? const Center(
                              child: Text(
                                "Busca un tema para escuchar el preview de 30s y proponerlo",
                                style: TextStyle(color: StageTheme.textMuted),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              controller: scrollCtrl,
                              itemCount: spotifyResults.length,
                              itemBuilder: (ctx, index) {
                                final track = spotifyResults[index];
                                final isPlaying = playingUrl == track["preview_url"];

                                return ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: track["cover_url"] != null
                                        ? Image.network(track["cover_url"] as String, width: 48, height: 48, fit: BoxFit.cover)
                                        : Container(width: 48, height: 48, color: StageTheme.surfaceElevated),
                                  ),
                                  title: Text(track["title"] as String? ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(track["artist"] as String? ?? ""),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        iconSize: 36,
                                        icon: Icon(
                                          isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                          color: track["preview_url"] != null ? StageTheme.flameOrange : StageTheme.textMuted,
                                        ),
                                        tooltip: "Escuchar preview de 30s",
                                        onPressed: () => toggleDialogPreview(track["preview_url"] as String?),
                                      ),
                                      const SizedBox(width: 4),
                                      ElevatedButton(
                                        child: const Text("Añadir"),
                                        onPressed: () async {
                                          await dialogPlayer.stop();
                                          await _api.createSongProposal(
                                            title: track["title"],
                                            artist: track["artist"],
                                            album: track["album"],
                                            coverUrl: track["cover_url"],
                                            previewUrl: track["preview_url"],
                                            spotifyId: track["spotify_id"],
                                          );
                                          Navigator.pop(ctx);
                                          _loadSongs(silent: true);
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      dialogPlayer.dispose();
    });
  }
}
