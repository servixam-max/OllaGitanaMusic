import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/audio/multitrack_player.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/stage_theme.dart';
import '../../core/widgets/profile_app_bar_button.dart';

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
  String? _currentLoadedSongName;

  // Estado para la barra de progreso sin tirones
  double? _draggingPositionMs;

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

    if (!mounted) return;

    // Diálogo de selección de modelo de separación
    final chosenModel = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: StageTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: StageTheme.amberGold, width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(Icons.auto_awesome, color: StageTheme.amberGold, size: 24),
            SizedBox(width: 8),
            Text("Separación con IA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Canción: ${picked.name}",
              style: const TextStyle(fontWeight: FontWeight.bold, color: StageTheme.amberGold, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            const Text(
              "Elige cómo deseas separar las pistas:",
              style: TextStyle(color: StageTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            // Opción 1: 4 Pistas Estudio Fine-Tuned (Recomendado)
            Material(
              color: StageTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(ctx, "htdemucs_ft"),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: StageTheme.amberGold,
                        foregroundColor: Colors.black,
                        child: Icon(Icons.album),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Text("4 Pistas Estudio", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                SizedBox(width: 6),
                                Text("(Recomendado)", style: TextStyle(color: StageTheme.amberGold, fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            const Text("Máxima pegada y fidelidad en Batería, Voz, Bajo y Otros sin cortes ni artefactos.", style: TextStyle(color: StageTheme.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: StageTheme.amberGold),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Opción 2: 6 Pistas
            Material(
              color: StageTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(ctx, "htdemucs_6s"),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: StageTheme.flameOrange,
                        foregroundColor: Colors.white,
                        child: Icon(Icons.piano),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("6 Pistas Pro", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            SizedBox(height: 2),
                            Text("Voz, Batería, Bajo, Guitarra acústica/eléctrica, Piano, Otros.", style: TextStyle(color: StageTheme.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: StageTheme.flameOrange),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Opción 3: 4 Pistas Rápido
            Material(
              color: StageTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(ctx, "htdemucs"),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: StageTheme.electricGreen,
                        foregroundColor: Colors.black,
                        child: Icon(Icons.bolt),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("4 Pistas Estándar (Rápido)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            SizedBox(height: 2),
                            Text("Separación más ligera para pruebas rápidas.", style: TextStyle(color: StageTheme.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: StageTheme.electricGreen),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (chosenModel == null) return;

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
      model: chosenModel,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error al subir el archivo de audio")),
        );
      }
    }
  }

  void _listenToTaskProgress(String taskId) {
    setState(() {
      _activeTaskId = taskId;
      _taskStatus = "Iniciando separación por IA con Demucs...";
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

            if (status == "completed" && stems != null && stems.isNotEmpty) {
              _onSeparationCompleted(stems);
            } else if (status == "failed") {
              setState(() => _taskStatus = "Error en la separación.");
            }
          }
        },
        onError: (err) {
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

        if (status == "completed" && stems != null && stems.isNotEmpty) {
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

    final Map<String, String> fullUrls = {};
    stems.forEach((stemName, relativeUrl) {
      fullUrls[stemName] = _api.getFullUrl(relativeUrl);
    });

    _player.loadStems(fullUrls);
    _loadRecentTasks();
  }

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
        return Icons.tune;
    }
  }

  Color _getStemColor(String stemName) {
    switch (stemName.toLowerCase()) {
      case 'vocals':
        return StageTheme.amberGold;
      case 'drums':
        return StageTheme.flameOrange;
      case 'bass':
        return StageTheme.electricGreen;
      case 'guitar':
        return const Color(0xFF00B0FF);
      case 'piano':
        return const Color(0xFFE040FB);
      default:
        return StageTheme.textSecondary;
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
        return "Otros / Arreglos";
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
        title: const Text("Mezclador"),
        actions: [
          const ProfileAppBarButton(),
          IconButton(
            icon: const Icon(Icons.library_music),
            tooltip: "Seleccionar canción",
            onPressed: _showRecentTasksModal,
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
          // Banner de progreso si hay subida o separación en curso
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
                    onPressed: _showRecentTasksModal,
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
                      "Aísla pistas (Voz, Batería, Bajo, Guitarra, Piano, Otros) con IA para ensayar cualquier instrumento.",
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
                          final stemCount = stems.length;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isCompleted
                                    ? StageTheme.electricGreen.withOpacity(0.2)
                                    : StageTheme.amberGold.withOpacity(0.2),
                                child: Icon(
                                  isCompleted ? Icons.check : Icons.hourglass_top,
                                  color: isCompleted ? StageTheme.electricGreen : StageTheme.amberGold,
                                  size: 20,
                                ),
                              ),
                              title: Text(filename, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text(
                                isCompleted
                                    ? "$stemCount pistas disponibles (${stems.keys.map(_getStemLabel).join(', ')})"
                                    : "Estado: $status",
                                style: const TextStyle(fontSize: 12, color: StageTheme.textSecondary),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: StageTheme.alertRed),
                                    tooltip: "Eliminar canción",
                                    onPressed: () => _deleteTask(t["task_id"] ?? t["id"] ?? "", filename),
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
    final durationMs = _player.duration.inMilliseconds.toDouble();
    final currentPosMs = _draggingPositionMs ?? _player.position.inMilliseconds.toDouble();
    final clampedPosMs = currentPosMs.clamp(0.0, durationMs > 0 ? durationMs : 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: StageTheme.surface,
        border: Border(bottom: BorderSide(color: StageTheme.border)),
      ),
      child: Column(
        children: [
          // Barra de tiempo y progreso con búsqueda suave
          Row(
            children: [
              Text(
                _formatDuration(Duration(milliseconds: clampedPosMs.toInt())),
                style: const TextStyle(color: StageTheme.textSecondary, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: clampedPosMs,
                  max: durationMs > 0 ? durationMs : 1.0,
                  onChanged: (val) {
                    setState(() => _draggingPositionMs = val);
                  },
                  onChangeEnd: (val) {
                    _player.seek(Duration(milliseconds: val.toInt()));
                    setState(() => _draggingPositionMs = null);
                  },
                ),
              ),
              Text(
                _formatDuration(_player.duration),
                style: const TextStyle(color: StageTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),

          // Botonera de transporte principal
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Rebobinar al inicio
              IconButton(
                icon: const Icon(Icons.skip_previous),
                tooltip: "Inicio",
                iconSize: 28,
                onPressed: _player.restart,
              ),
              const SizedBox(width: 8),
              // Saltar -10s
              IconButton(
                icon: const Icon(Icons.replay_10),
                tooltip: "Retroceder 10s",
                iconSize: 32,
                onPressed: () => _player.seekRelative(const Duration(seconds: -10)),
              ),
              const SizedBox(width: 12),
              // Botón Play / Pause Maestro
              IconButton(
                iconSize: 56,
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
              const SizedBox(width: 12),
              // Saltar +10s
              IconButton(
                icon: const Icon(Icons.forward_10),
                tooltip: "Avanzar 10s",
                iconSize: 32,
                onPressed: () => _player.seekRelative(const Duration(seconds: 10)),
              ),
              const SizedBox(width: 8),
              // Bucle A-B Toggle
              IconButton(
                icon: Icon(
                  Icons.repeat,
                  color: _player.isLooping ? StageTheme.amberGold : StageTheme.textSecondary,
                ),
                tooltip: _player.isLooping ? "Desactivar bucle" : "Activar bucle A-B",
                iconSize: 28,
                onPressed: _player.toggleLoop,
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Herramientas de ensayo: Velocidad, Tono, Bucle A-B y Reset Mezcla
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Selector de Velocidad (Tempo)
                PopupMenuButton<double>(
                  tooltip: "Velocidad de reproducción",
                  onSelected: _player.setSpeed,
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 0.75, child: Text("0.75x (Muy Lento)")),
                    const PopupMenuItem(value: 0.85, child: Text("0.85x (Lento)")),
                    const PopupMenuItem(value: 1.0, child: Text("1.0x (Normal)")),
                    const PopupMenuItem(value: 1.15, child: Text("1.15x (Rápido)")),
                    const PopupMenuItem(value: 1.25, child: Text("1.25x (Muy Rápido)")),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.speed, size: 16, color: StageTheme.amberGold),
                    label: Text(
                      "${_player.speed}x",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    backgroundColor: _player.speed != 1.0
                        ? StageTheme.amberGold.withOpacity(0.2)
                        : StageTheme.surfaceElevated,
                    side: BorderSide(
                      color: _player.speed != 1.0 ? StageTheme.amberGold : StageTheme.border,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Selector de Bucle A-B
                ActionChip(
                  avatar: Icon(
                    Icons.bookmark_border,
                    size: 16,
                    color: _player.loopStart != null ? StageTheme.flameOrange : StageTheme.textSecondary,
                  ),
                  label: Text(
                    _player.loopStart == null
                        ? "Fijar [A]"
                        : "A: ${_formatDuration(_player.loopStart!)}",
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: StageTheme.surfaceElevated,
                  onPressed: _player.setLoopPointA,
                ),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: Icon(
                    Icons.bookmark,
                    size: 16,
                    color: _player.loopEnd != null ? StageTheme.flameOrange : StageTheme.textSecondary,
                  ),
                  label: Text(
                    _player.loopEnd == null
                        ? "Fijar [B]"
                        : "B: ${_formatDuration(_player.loopEnd!)}",
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: StageTheme.surfaceElevated,
                  onPressed: _player.setLoopPointB,
                ),
                if (_player.loopStart != null || _player.loopEnd != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: StageTheme.alertRed),
                    tooltip: "Limpiar bucle A-B",
                    onPressed: _player.clearLoop,
                  ),
                ],
                const SizedBox(width: 8),

                // Botón Restablecer Mezcla
                ActionChip(
                  avatar: const Icon(Icons.restart_alt, size: 16, color: StageTheme.textSecondary),
                  label: const Text("Reset Mezcla", style: TextStyle(fontSize: 12)),
                  backgroundColor: StageTheme.surfaceElevated,
                  onPressed: _player.resetMix,
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Control de Volumen Maestro
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _player.isMasterMuted ? Icons.volume_off : Icons.volume_up,
                  color: _player.isMasterMuted ? StageTheme.alertRed : StageTheme.amberGold,
                  size: 22,
                ),
                tooltip: _player.isMasterMuted ? "Activar sonido" : "Silenciar todo",
                onPressed: _player.toggleMasterMute,
              ),
              const Text("Master:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Expanded(
                child: Slider(
                  value: _player.masterVolume,
                  onChanged: _player.setMasterVolume,
                ),
              ),
              Text(
                "${(_player.masterVolume * 100).toInt()}%",
                style: const TextStyle(fontSize: 12, color: StageTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChannelStrips() {
    final soloActive = _player.hasAnySolo;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: _player.tracks.values.map((track) {
        final isSilencedBySolo = soloActive && !track.isSolo;
        final accentColor = _getStemColor(track.name);

        return Opacity(
          opacity: isSilencedBySolo ? 0.45 : 1.0,
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: track.isSolo
                    ? StageTheme.amberGold
                    : track.isMuted
                        ? StageTheme.alertRed.withOpacity(0.5)
                        : StageTheme.border,
                width: track.isSolo ? 1.5 : 1.0,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Icono del instrumento
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_getStemIcon(track.name), color: accentColor, size: 26),
                  ),
                  const SizedBox(width: 12),

                  // Nombre de la pista y porcentaje
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getStemLabel(track.name),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          isSilencedBySolo
                              ? "Silenciado por Solo"
                              : "${(track.volume * 100).toInt()}%",
                          style: TextStyle(
                            color: isSilencedBySolo ? StageTheme.alertRed : StageTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Slider de volumen individual
                  Expanded(
                    flex: 3,
                    child: Slider(
                      value: track.volume,
                      activeColor: accentColor,
                      onChanged: (val) => _player.setTrackVolume(track.name, val),
                    ),
                  ),

                  // Botón Mute (M)
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: track.isMuted ? StageTheme.alertRed : StageTheme.surfaceElevated,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _player.toggleMute(track.name),
                      child: const Text("M", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Botón Solo (S)
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: track.isSolo ? StageTheme.amberGold : StageTheme.surfaceElevated,
                        foregroundColor: track.isSolo ? Colors.black : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _player.toggleSolo(track.name),
                      child: const Text("S", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Canciones Procesadas", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: StageTheme.amberGold),
                    onPressed: () async {
                      await _loadRecentTasks();
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showRecentTasksModal();
                    },
                  ),
                ],
              ),
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
                          final stemCount = stems.length;

                          return ListTile(
                            leading: Icon(
                              isCompleted ? Icons.check_circle : Icons.hourglass_top,
                              color: isCompleted ? StageTheme.electricGreen : StageTheme.amberGold,
                            ),
                            title: Text(t["filename"] ?? "Audio", style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              isCompleted
                                  ? "$stemCount pistas: ${stems.keys.map(_getStemLabel).join(', ')}"
                                  : "Estado: ${t["status"]}",
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: StageTheme.alertRed),
                                  tooltip: "Eliminar",
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _deleteTask(t["task_id"] ?? t["id"] ?? "", t["filename"] ?? "Audio");
                                  },
                                ),
                                if (isCompleted) ...[
                                  const SizedBox(width: 4),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: StageTheme.amberGold,
                                      foregroundColor: Colors.black,
                                    ),
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
