import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/stage_theme.dart';
import '../../core/widgets/profile_app_bar_button.dart';

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

  int? _playingPreviewSongId;
  WebSocketChannel? _wsChannel;

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
    _wsChannel?.sink.close();
    super.dispose();
  }

  void _initWebSocket() {
    final wsUrl = _api.getWebSocketUrl("/ws/repertoire");
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsChannel!.stream.listen((message) {
        final event = jsonDecode(message);
        final eventType = event["event"];
        if (eventType == "song_added" || eventType == "vote_updated" || eventType == "status_changed" || eventType == "song_deleted") {
          _loadSongs(silent: true);
        }
      }, onError: (_) {});
    } catch (_) {}
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Esta canción no cuenta con snippet de 30s disponible")),
      );
      return;
    }

    if (_playingPreviewSongId == songId) {
      await _previewPlayer.stop();
      setState(() => _playingPreviewSongId = null);
    } else {
      await _previewPlayer.stop();
      setState(() => _playingPreviewSongId = songId);
      try {
        await _previewPlayer.setUrl(previewUrl);
        await _previewPlayer.play();
      } catch (e) {
        setState(() => _playingPreviewSongId = null);
      }
    }
  }

  Future<void> _vote(int songId, int rating) async {
    final success = await _api.voteSong(songId, rating);
    if (success) {
      _loadSongs(silent: true);
    }
  }

  Future<void> _changeStatus(int songId, String newStatus) async {
    final success = await _api.updateSongStatus(songId, newStatus);
    if (success) {
      _loadSongs(silent: true);
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
        return "Para Ensayar";
      case "en_repertorio":
        return "En Repertorio";
      case "descartada":
        return "Descartada";
      default:
        return status;
    }
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

    // Filtrar para no incluir las descartadas si hay canciones activas
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
          ProfileAppBarButton(onProfileChanged: () => setState(() {})),
          IconButton(
            icon: const Icon(Icons.share, color: StageTheme.amberGold),
            tooltip: "Compartir repertorio por WhatsApp",
            onPressed: _shareRepertoireOnWhatsApp,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: StageTheme.amberGold),
            tooltip: "Recargar repertorio",
            onPressed: () => _loadSongs(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de la Banda "Olla Gitana"
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Image.asset(
                    "assets/images/band_hero.jpg",
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.85),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    bottom: 10,
                    left: 14,
                    child: Text(
                      "OLLA GITANA",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Filtros por estado
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip("todas", "Todas"),
                _buildFilterChip("propuesta", "Propuestas"),
                _buildFilterChip("para_ensayar", "Para Ensayar"),
                _buildFilterChip("en_repertorio", "En Repertorio"),
                _buildFilterChip("descartada", "Descartadas"),
              ],
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
                                  "No hay canciones en esta sección.\n¡Propón una nueva con el botón inferior o desliza para actualizar!",
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
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          itemCount: _songs.length,
                          itemBuilder: (context, index) {
                          final song = _songs[index];
                          final isPlayingThis = _playingPreviewSongId == song["id"];

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
                                      // Carátula del disco
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: song["cover_url"] != null
                                            ? Image.network(
                                                song["cover_url"],
                                                width: 64,
                                                height: 64,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Container(
                                                  width: 64,
                                                  height: 64,
                                                  color: StageTheme.surfaceElevated,
                                                  child: const Icon(Icons.music_note, color: StageTheme.flameOrange),
                                                ),
                                              )
                                            : Container(
                                                width: 64,
                                                height: 64,
                                                color: StageTheme.surfaceElevated,
                                                child: const Icon(Icons.music_note, color: StageTheme.flameOrange),
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Título y artista
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              song["title"] ?? "",
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              song["artist"] ?? "",
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
                                      // Botón de reproducción de snippet de 30s
                                      IconButton(
                                        iconSize: 40,
                                        icon: Icon(
                                          isPlayingThis ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                          color: song["preview_url"] != null
                                              ? StageTheme.flameOrange
                                              : StageTheme.textMuted,
                                        ),
                                        onPressed: () => _togglePreview(song["id"], song["preview_url"]),
                                      ),
                                    ],
                                  ),
                                  const Divider(color: StageTheme.border, height: 24),
                                  // Votación y Estado
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Rating Stars
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
                                            itemBuilder: (context, _) => const Icon(
                                              Icons.star,
                                              color: StageTheme.amberGold,
                                            ),
                                            onRatingUpdate: (rating) => _vote(song["id"], rating.toInt()),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "Nota: ${song["average_rating"]} (${song["total_votes"]} votos)",
                                            style: const TextStyle(color: StageTheme.textSecondary, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                      // Selector de estado
                                      PopupMenuButton<String>(
                                        onSelected: (newStatus) => _changeStatus(song["id"], newStatus),
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(value: "propuesta", child: Text("Propuesta")),
                                          const PopupMenuItem(value: "para_ensayar", child: Text("Para Ensayar")),
                                          const PopupMenuItem(value: "en_repertorio", child: Text("En Repertorio")),
                                          const PopupMenuItem(value: "descartada", child: Text("Descartada")),
                                        ],
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(song["status"]).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: _getStatusColor(song["status"])),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                _getStatusLabel(song["status"]),
                                                style: TextStyle(
                                                  color: _getStatusColor(song["status"]),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(Icons.arrow_drop_down, color: _getStatusColor(song["status"]), size: 16),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: StageTheme.flameOrange,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Proponer Canción", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () => _showAddSongDialog(),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: StageTheme.flameOrange,
        backgroundColor: StageTheme.surfaceElevated,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : StageTheme.textSecondary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (_) {
          setState(() => _selectedFilter = key);
          _loadSongs();
        },
      ),
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
                  await dialogPlayer.setUrl(url);
                  await dialogPlayer.play();
                } catch (_) {
                  setModalState(() => playingUrl = null);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SizedBox(
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                          ? const Center(child: Text("Busca un tema para escuchar el preview de 30s y proponerlo", style: TextStyle(color: StageTheme.textMuted)))
                          : ListView.builder(
                              itemCount: spotifyResults.length,
                              itemBuilder: (ctx, index) {
                                final track = spotifyResults[index];
                                final isPlaying = playingUrl == track["preview_url"];

                                return ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: track["cover_url"] != null
                                        ? Image.network(track["cover_url"], width: 48, height: 48, fit: BoxFit.cover)
                                        : Container(width: 48, height: 48, color: StageTheme.surfaceElevated),
                                  ),
                                  title: Text(track["title"] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(track["artist"] ?? ""),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        iconSize: 36,
                                        icon: Icon(
                                          isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                          color: track["preview_url"] != null
                                              ? StageTheme.flameOrange
                                              : StageTheme.textMuted,
                                        ),
                                        tooltip: "Escuchar preview de 30s",
                                        onPressed: () => toggleDialogPreview(track["preview_url"]),
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
