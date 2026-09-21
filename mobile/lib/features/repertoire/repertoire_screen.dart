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

  static const List<(String, String, IconData)> _filters = [
    ("todas", "Todas", Icons.list_alt),
    ("propuesta", "Propuestas", Icons.thumb_up_outlined),
    ("para_ensayar", "Ensayar", Icons.queue_music),
    ("en_repertorio", "Repertorio", Icons.library_music),
    ("descartada", "Descartadas", Icons.thumb_down_outlined),
  ];

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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Repertorio"),
        actions: [
          // Selector de modo de vista
          IconButton(
            icon: Icon(
              _viewMode == _ViewMode.compact ? Icons.grid_view : Icons.view_list,
              color: StageTheme.amberGold,
            ),
            tooltip: _viewMode == _ViewMode.compact ? "Vista tarjetas" : "Vista compacta",
            onPressed: () => setState(() {
              _viewMode = _viewMode == _ViewMode.compact ? _ViewMode.cards : _ViewMode.compact;
            }),
          ),
          ProfileAppBarButton(onProfileChanged: () => setState(() {})),
          IconButton(
            icon: const Icon(Icons.share, color: StageTheme.amberGold),
            tooltip: "Compartir repertorio por WhatsApp",
            onPressed: _shareRepertoireOnWhatsApp,
          ),
        ],
      ),
      body: Column(
        children: [
          // Aviso si se pierde la sincronización en vivo
          if (!_wsConnected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: StageTheme.alertRed.withValues(alpha: 0.15),
              child: const Row(
                children: [
                  Icon(Icons.cloud_off, size: 16, color: StageTheme.alertRed),
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

          // Filtros compactos tipo NavigationBar
          _buildFilterBar(),

          // Contador de resultados
          if (!_isLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              alignment: Alignment.centerLeft,
              child: Text(
                "${_songs.length} canción${_songs.length != 1 ? 'es' : ''}${_selectedFilter != 'todas' ? ' · ${_filters.firstWhere((f) => f.$1 == _selectedFilter).$2}' : ''}",
                style: const TextStyle(color: StageTheme.textSecondary, fontSize: 12),
              ),
            ),

          // Lista de canciones
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: StageTheme.flameOrange))
                : _songs.isEmpty
                    ? RefreshIndicator(
                        onRefresh: () => _loadSongs(),
                        color: StageTheme.flameOrange,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.music_note, size: 56, color: StageTheme.textMuted),
                                const SizedBox(height: 12),
                                const Text(
                                  "No hay canciones en esta sección.\n¡Propón una nueva con el botón inferior!",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: StageTheme.textSecondary, fontSize: 15),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.refresh),
                                  label: const Text("Actualizar lista"),
                                  style: ElevatedButton.styleFrom(backgroundColor: StageTheme.surfaceElevated),
                                  onPressed: () => _loadSongs(),
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
                            ? _buildCompactList()
                            : _buildCardList(),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: StageTheme.flameOrange,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Proponer", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () => _showAddSongDialog(),
      ),
    );
  }

  /// Barra de filtros compacta — ocupa una sola fila sin scroll horizontal
  Widget _buildFilterBar() {
    return Container(
      color: StageTheme.surface,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filters.map((filter) {
            final key = filter.$1;
            final label = filter.$2;
            final icon = filter.$3;
            final isSelected = _selectedFilter == key;
            // Contar canciones por categoría para mostrar badge
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () {
                  setState(() => _selectedFilter = key);
                  _loadSongs();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected ? StageTheme.flameOrange : StageTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? StageTheme.flameOrange : StageTheme.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 14,
                        color: isSelected ? Colors.white : StageTheme.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : StageTheme.textSecondary,
                        ),
                      ),
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

  /// Vista compacta: muchas canciones por pantalla
  Widget _buildCompactList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _songs.length,
      itemBuilder: (context, index) {
        final song = _songs[index];
        final isPlayingThis = _playingPreviewSongId == song["id"] as int?;
        final statusColor = _getStatusColor(song["status"] as String? ?? "");

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Borde de color según estado
                Container(width: 4, color: statusColor),
                Expanded(
                  child: InkWell(
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                    onTap: () => _showSongDetailSheet(song),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          // Portada pequeña
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: song["cover_url"] != null
                                ? Image.network(
                                    song["cover_url"] as String,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _placeholderCover(44),
                                  )
                                : _placeholderCover(44),
                          ),
                          const SizedBox(width: 10),
                          // Título y artista
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  song["title"] as String? ?? "",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  song["artist"] as String? ?? "",
                                  style: const TextStyle(color: StageTheme.textSecondary, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Columna derecha: rating + estado tocable
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star, size: 12, color: StageTheme.amberGold),
                                  const SizedBox(width: 2),
                                  Text(
                                    "${(song["average_rating"] as num?)?.toStringAsFixed(1) ?? "0.0"}",
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              // Chip de estado TOCABLE directamente sin abrir el detail sheet
                              GestureDetector(
                                onTap: () => _showInlineStatusMenu(context, song),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: statusColor.withValues(alpha: 0.6), width: 1),
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
                          const SizedBox(width: 2),
                          // Play button
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            icon: Icon(
                              isPlayingThis ? Icons.pause_circle_filled : Icons.play_circle_fill,
                              color: song["preview_url"] != null ? StageTheme.flameOrange : StageTheme.textMuted,
                              size: 32,
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


  /// Vista tarjetas: la vista original, más detallada
  Widget _buildCardList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: _songs.length,
      itemBuilder: (context, index) {
        final song = _songs[index];
        final isPlayingThis = _playingPreviewSongId == song["id"] as int?;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Carátula
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: song["cover_url"] != null
                          ? Image.network(
                              song["cover_url"] as String,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholderCover(64),
                            )
                          : _placeholderCover(64),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song["title"] as String? ?? "",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            song["artist"] as String? ?? "",
                            style: const TextStyle(color: StageTheme.textSecondary, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Propuesta por: ${song["proposed_by"]}",
                            style: const TextStyle(color: StageTheme.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 40,
                      icon: Icon(
                        isPlayingThis ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        color: song["preview_url"] != null ? StageTheme.flameOrange : StageTheme.textMuted,
                      ),
                      onPressed: () => _togglePreview(song["id"] as int, song["preview_url"] as String?),
                    ),
                  ],
                ),
                const Divider(color: StageTheme.border, height: 24),
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
                          itemSize: 22,
                          itemPadding: const EdgeInsets.symmetric(horizontal: 1.0),
                          itemBuilder: (context, _) => const Icon(Icons.star, color: StageTheme.amberGold),
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
                        const SizedBox(width: 2),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: StageTheme.alertRed, size: 20),
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
