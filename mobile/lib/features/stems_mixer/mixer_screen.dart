import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/audio/multitrack_player.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/stage_theme.dart';

class MixerScreen extends StatefulWidget {
  const MixerScreen({super.key});

  @override
  State<MixerScreen> createState() => _MixerScreenState();
}

class _MixerScreenState extends State<MixerScreen> {
  final ApiClient _api = ApiClient();
  final MultitrackPlayer _player = MultitrackPlayer();

  bool _isUploading = false;
  int _uploadProgress = 0;
  String? _activeTaskId;
  int _separationProgress = 0;
  String _taskStatus = "";
  WebSocketChannel? _wsChannel;

  List<dynamic> _recentTasks = [];

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayerStateChanged);
    _loadRecentTasks();
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerStateChanged);
    _player.dispose();
    _wsChannel?.sink.close();
    super.dispose();
  }

  void _onPlayerStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadRecentTasks() async {
    final tasks = await _api.getRecentStemTasks();
    if (mounted) {
      setState(() => _recentTasks = tasks);
    }
  }

  Future<void> _pickAndUploadAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac', 'ogg', 'm4a'],
      withData: true,
    );

    if (result == null || (result.files.single.path == null && result.files.single.bytes == null)) return;
    final picked = result.files.single;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
      _separationProgress = 0;
      _taskStatus = "Subiendo archivo...";
    });

    final res = await _api.uploadAudioForStems(
      filePath: picked.path,
      fileBytes: picked.bytes,
      fileName: picked.name,
      onProgress: (sent, total) {
        if (total > 0 && mounted) {
          setState(() => _uploadProgress = ((sent / total) * 100).toInt());
        }
      },
    );

    setState(() => _isUploading = false);

    if (res != null && res["task_id"] != null) {
      final taskId = res["task_id"] as String;
      _listenToTaskProgress(taskId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error al subir el archivo de audio")),
      );
    }
  }

  void _listenToTaskProgress(String taskId) {
    setState(() {
      _activeTaskId = taskId;
      _taskStatus = "Iniciando separación con Demucs...";
      _separationProgress = 5;
    });

    _wsChannel?.sink.close();
    final wsUrl = _api.getWebSocketUrl("/ws/tasks/$taskId");

    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsChannel!.stream.listen(
        (data) {
          final payload = jsonDecode(data);
          final progress = payload["progress"] ?? 0;
          final status = payload["status"] ?? "";
          final stems = payload["stems"] as Map<String, dynamic>?;

          if (mounted) {
            setState(() {
              _separationProgress = progress;
              _taskStatus = "Separando pistas ($progress%)...";
            });

            if (status == "completed" && stems != null) {
              _onSeparationCompleted(stems);
            }
          }
        },
        onError: (err) {
          print("[MixerScreen] Error WebSocket: $err");
          _pollTaskStatus(taskId);
        },
      );
    } catch (_) {
      _pollTaskStatus(taskId);
    }
  }

  Future<void> _pollTaskStatus(String taskId) async {
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted || _activeTaskId != taskId) {
        timer.cancel();
        return;
      }
      final task = await _api.getStemTask(taskId);
      if (task != null) {
        final status = task["status"];
        final progress = task["progress"] ?? 0;
        final stems = task["stems"] as Map<String, dynamic>?;

        setState(() {
          _separationProgress = progress;
          _taskStatus = "Procesando ($progress%)...";
        });

        if (status == "completed" && stems != null) {
          timer.cancel();
          _onSeparationCompleted(stems);
        } else if (status == "failed") {
          timer.cancel();
          setState(() => _taskStatus = "Error en la separación.");
        }
      }
    });
  }

  void _onSeparationCompleted(Map<String, dynamic> stems) {
    setState(() {
      _taskStatus = "¡Separación completada!";
      _activeTaskId = null;
    });

    // Cargar stems en el reproductor multipista
    final Map<String, String> fullUrls = {};
    stems.forEach((stemName, relativeUrl) {
      fullUrls[stemName] = _api.getFullUrl(relativeUrl);
    });

    _player.loadStems(fullUrls);
    _loadRecentTasks();
  }

  String? _currentLoadedSongName;

  void _loadCompletedTaskStems(String songName, Map<String, dynamic> stems) {
    setState(() => _currentLoadedSongName = songName);
    final Map<String, String> fullUrls = {};
    stems.forEach((stemName, relativeUrl) {
      fullUrls[stemName] = _api.getFullUrl(relativeUrl);
    });
    _player.loadStems(fullUrls);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  IconData _getStemIcon(String stemName) {
    switch (stemName.toLowerCase()) {
      case 'vocals':
        return Icons.mic;
      case 'drums':
        return Icons.album;
      case 'bass':
        return Icons.music_note;
      case 'guitar':
        return Icons.graphic_eq;
      case 'piano':
        return Icons.piano;
      default:
        return Icons.audiotrack;
    }
  }

  String _getStemLabel(String stemName) {
    switch (stemName.toLowerCase()) {
      case 'vocals':
        return "Voz";
      case 'drums':
        return "Batería / Percusión";
      case 'bass':
        return "Bajo";
      case 'guitar':
        return "Guitarra";
      case 'piano':
        return "Piano / Teclados";
      case 'other':
        return "Guitarras / Otros";
      default:
        return stemName.toUpperCase();
    }
  }

  Future<void> _deleteTask(String taskId, String filename) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StageTheme.surface,
        title: const Text("Eliminar Canción"),
        content: Text("¿Deseas eliminar '$filename' y sus pistas separadas del servidor?"),
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
      if (_currentLoadedSongName == filename) {
        await _player.dispose();
        setState(() => _currentLoadedSongName = null);
      }
      await _api.deleteStemTask(taskId);
      _loadRecentTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mezclador de Ensayo"),
        actions: [
          IconButton(
            icon: const Icon(Icons.library_music),
            tooltip: "Seleccionar canción",
            onPressed: () => _showRecentTasksModal(),
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: "Subir audio para aislar pistas",
            onPressed: _isUploading || _activeTaskId != null ? null : _pickAndUploadAudio,
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de progreso si hay carga o separación en curso
          if (_isUploading || _activeTaskId != null) _buildProgressBanner(),

          // Si hay pistas cargadas en el reproductor multipista
          if (_player.tracks.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: StageTheme.surfaceElevated,
              child: Row(
                children: [
                  const Icon(Icons.music_note, color: StageTheme.flameOrange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentLoadedSongName ?? "Canción cargada",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text("Cambiar"),
                    style: TextButton.styleFrom(foregroundColor: StageTheme.amberGold),
                    onPressed: () => _showRecentTasksModal(),
                  ),
                ],
              ),
            ),
            _buildMasterControls(),
            Expanded(child: _buildChannelStrips()),
          ] else if (!_isUploading && _activeTaskId == null)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        "assets/images/band_hero.jpg",
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Mezclador Multipista de Ensayo",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Aísla pistas (Voz, Batería, Bajo, Guitarras/Otros) con IA para ensayar cualquier instrumento.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: StageTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.cloud_upload, size: 22),
                      label: const Text("Subir Nueva Canción"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StageTheme.flameOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      onPressed: _pickAndUploadAudio,
                    ),
                    const SizedBox(height: 24),

                    // Menú de canciones procesadas disponibles
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Canciones Listas para Mezclar",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20, color: StageTheme.amberGold),
                          tooltip: "Refrescar lista",
                          onPressed: _loadRecentTasks,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_recentTasks.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: StageTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          "Aún no hay canciones procesadas en el servidor.\nSube un archivo de audio para empezar.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: StageTheme.textMuted),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _recentTasks.length,
                        itemBuilder: (ctx, index) {
                          final t = _recentTasks[index];
                          final filename = t["filename"] ?? "Audio";
                          final status = t["status"] ?? "";
                          final stems = t["stems"] as Map<String, dynamic>? ?? {};
                          final isCompleted = status == "completed";

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isCompleted ? StageTheme.electricGreen.withOpacity(0.2) : StageTheme.amberGold.withOpacity(0.2),
                                child: Icon(
                                  isCompleted ? Icons.check : Icons.hourglass_top,
                                  color: isCompleted ? StageTheme.electricGreen : StageTheme.amberGold,
                                  size: 20,
                                ),
                              ),
                              title: Text(filename, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text(
                                isCompleted ? "4 pistas disponibles (Voz, Batería, Bajo, Otros)" : "Estado: $status",
                                style: const TextStyle(fontSize: 12, color: StageTheme.textSecondary),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: StageTheme.alertRed),
                                    tooltip: "Eliminar canción",
                                    onPressed: () => _deleteTask(t["id"] ?? "", filename),
                                  ),
                                  if (isCompleted) ...[
                                    const SizedBox(width: 4),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: StageTheme.amberGold,
                                        foregroundColor: Colors.black,
                                      ),
                                      child: const Text("Cargar", style: TextStyle(fontWeight: FontWeight.bold)),
                                      onPressed: () => _loadCompletedTaskStems(filename, stems),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressBanner() {
    final progress = _isUploading ? _uploadProgress : _separationProgress;
    return Container(
      padding: const EdgeInsets.all(16),
      color: StageTheme.surfaceElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_taskStatus, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text("$progress%", style: const TextStyle(color: StageTheme.amberGold, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress / 100.0,
            backgroundColor: StageTheme.border,
            color: StageTheme.flameOrange,
          ),
        ],
      ),
    );
  }

  Widget _buildMasterControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: StageTheme.surface,
        border: Border(bottom: BorderSide(color: StageTheme.border)),
      ),
      child: Column(
        children: [
          // Barra de progreso y tiempo
          Row(
            children: [
              Text(_formatDuration(_player.position), style: const TextStyle(color: StageTheme.textSecondary)),
              Expanded(
                child: Slider(
                  value: _player.position.inMilliseconds.toDouble().clamp(0.0, _player.duration.inMilliseconds.toDouble()),
                  max: _player.duration.inMilliseconds.toDouble() > 0 ? _player.duration.inMilliseconds.toDouble() : 1.0,
                  onChanged: (val) => _player.seek(Duration(milliseconds: val.toInt())),
                ),
              ),
              Text(_formatDuration(_player.duration), style: const TextStyle(color: StageTheme.textSecondary)),
            ],
          ),
          // Botón Play / Pause Maestro
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 52,
                icon: Icon(
                  _player.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: StageTheme.flameOrange,
                ),
                onPressed: () {
                  if (_player.isPlaying) {
                    _player.pause();
                  } else {
                    _player.play();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChannelStrips() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: _player.tracks.values.map((track) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Icono e instrumento
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: StageTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_getStemIcon(track.name), color: StageTheme.flameOrange, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getStemLabel(track.name),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        "${(track.volume * 100).toInt()}%",
                        style: const TextStyle(color: StageTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Slider de volumen
                Expanded(
                  flex: 3,
                  child: Slider(
                    value: track.volume,
                    onChanged: (val) => _player.setTrackVolume(track.name, val),
                  ),
                ),
                // Botón Mute (M)
                SizedBox(
                  width: 44,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: track.isMuted ? StageTheme.alertRed : StageTheme.surfaceElevated,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _player.toggleMute(track.name),
                    child: const Text("M", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 8),
                // Botón Solo (S)
                SizedBox(
                  width: 44,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: track.isSolo ? StageTheme.amberGold : StageTheme.surfaceElevated,
                      foregroundColor: track.isSolo ? Colors.black : Colors.white,
                    ),
                    onPressed: () => _player.toggleSolo(track.name),
                    child: const Text("S", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showRecentTasksModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: StageTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Canciones Procesadas Recientes", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Expanded(
                child: _recentTasks.isEmpty
                    ? const Center(child: Text("No hay canciones procesadas todavía", style: TextStyle(color: StageTheme.textMuted)))
                    : ListView.builder(
                        itemCount: _recentTasks.length,
                        itemBuilder: (ctx, index) {
                          final t = _recentTasks[index];
                          final stems = t["stems"] as Map<String, dynamic>? ?? {};
                          final isCompleted = t["status"] == "completed";

                          return ListTile(
                            leading: Icon(
                              isCompleted ? Icons.check_circle : Icons.hourglass_top,
                              color: isCompleted ? StageTheme.electricGreen : StageTheme.amberGold,
                            ),
                            title: Text(t["filename"] ?? "Audio", style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("Estado: ${t["status"]}"),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: StageTheme.alertRed),
                                  tooltip: "Eliminar",
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _deleteTask(t["id"] ?? "", t["filename"] ?? "Audio");
                                  },
                                ),
                                if (isCompleted) ...[
                                  const SizedBox(width: 4),
                                  ElevatedButton(
                                    child: const Text("Cargar"),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _loadCompletedTaskStems(t["filename"] ?? "Audio", stems);
                                    },
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
