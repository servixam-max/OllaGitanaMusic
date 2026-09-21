import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/multitrack_player.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/stage_theme.dart';
import '../../core/widgets/profile_app_bar_button.dart';

class MixerScreen extends StatefulWidget {
  const MixerScreen({super.key});

  @override
  State<MixerScreen> createState() => _MixerScreenState();
}

class _MixerScreenState extends State<MixerScreen> with WidgetsBindingObserver {
  final ApiClient _api = ApiClient();
  final MultitrackPlayer _player = MultitrackPlayer();

  // Estados de subida
  bool _isUploading = false;
  int _uploadProgress = 0;

  // Estado de la tarea activa de separación
  String? _activeTaskId;
  int _separationProgress = 0;
  String _taskStatus = "";
  WebSocketChannel? _wsChannel;
  Timer? _pollTimer;
  bool _isRecoveringTask = false; // Indica que se encontró tarea en progreso al entrar

  // Lista de canciones procesadas
  List<dynamic> _recentTasks = [];
  String? _currentLoadedSongName;
  Map<String, bool> _collectionExpanded = {};

  // Barra de progreso sin tirones
  double? _draggingPositionMs;

  static const String _prefActiveTaskKey = "mixer_active_task_id";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player.addListener(_onPlayerStateChanged);
    _initMixer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.removeListener(_onPlayerStateChanged);
    _player.dispose();
    _wsChannel?.sink.close();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Se llama cuando el app vuelve al primer plano (desde background o lockscreen)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncActiveTask();
    }
  }

  void _onPlayerStateChanged() {
    if (mounted) setState(() {});
  }

  /// Inicialización: carga tareas y re-engancha si hay una tarea en progreso
  Future<void> _initMixer() async {
    await _loadRecentTasks();
    await _syncActiveTask();
  }

  /// Comprueba si hay una tarea en progreso (guardada en prefs o en la BD del servidor)
  /// y se re-suscribe automáticamente al progreso sin intervención del usuario.
  Future<void> _syncActiveTask() async {
    if (!mounted) return;

    // Si ya hay una tarea activa monitoreada, no hacer nada
    if (_activeTaskId != null) return;

    // 1. Intentar recuperar el task_id guardado localmente
    final prefs = await SharedPreferences.getInstance();
    String? savedTaskId = prefs.getString(_prefActiveTaskKey);

    // 2. Si no hay guardado, buscar en la lista del servidor si hay alguna "processing"
    if (savedTaskId == null) {
      final tasks = await _api.getRecentStemTasks();
      final processing = tasks.where((t) => t["status"] == "processing" || t["status"] == "pending").toList();
      if (processing.isNotEmpty) {
        savedTaskId = processing.first["task_id"] as String?;
      }
    }

    if (savedTaskId == null || !mounted) return;

    // 3. Verificar que la tarea realmente sigue en progreso en el servidor
    final task = await _api.getStemTask(savedTaskId);
    if (task == null || !mounted) return;

    final status = task["status"] as String? ?? "";
    if (status == "completed") {
      // Ya terminó mientras estábamos fuera — limpiar y refrescar
      await prefs.remove(_prefActiveTaskKey);
      await _loadRecentTasks();
      return;
    }
    if (status == "failed") {
      await prefs.remove(_prefActiveTaskKey);
      setState(() => _taskStatus = "La separación anterior falló.");
      await _loadRecentTasks();
      return;
    }

    // 4. La tarea sigue en progreso — reconectar
    if (status == "processing" || status == "pending") {
      setState(() => _isRecoveringTask = true);
      _listenToTaskProgress(savedTaskId, recovered: true);
    }
  }

  Future<void> _loadRecentTasks() async {
    final tasks = await _api.getRecentStemTasks();
    if (mounted) {
      setState(() => _recentTasks = tasks);
    }
  }

  /// Muestra un diálogo para pedir el nombre de la colección (opcional) antes de subir
  Future<String?> _askCollectionName() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StageTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: StageTheme.amberGold, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.cloud_upload, color: StageTheme.flameOrange, size: 24),
            SizedBox(width: 8),
            Text("Subir Canción", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "La IA separará la canción en 6 pistas independientes:\nVoz, Batería, Bajo, Guitarra, Piano y Otros.",
              style: TextStyle(color: StageTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: "Colección (opcional)",
                hintText: "Ej: Ensayo Sep 2026, Boda Verano...",
                prefixIcon: Icon(Icons.folder_outlined),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar", style: TextStyle(color: StageTheme.textSecondary)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text("Elegir Archivo"),
            style: ElevatedButton.styleFrom(
              backgroundColor: StageTheme.flameOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadAudio() async {
    // Pedir colección antes de elegir archivo
    final collectionResult = await _askCollectionName();
    if (collectionResult == null) return; // cancelado

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac', 'ogg', 'm4a'],
      withData: true,
    );

    if (result == null || (result.files.single.path == null && result.files.single.bytes == null)) return;
    final picked = result.files.single;

    if (!mounted) return;

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
      collectionName: collectionResult.isNotEmpty ? collectionResult : null,
      onProgress: (sent, total) {
        if (total > 0 && mounted) {
          setState(() => _uploadProgress = ((sent / total) * 100).toInt());
        }
      },
    );

    setState(() => _isUploading = false);

    if (res != null && res["task_id"] != null) {
      final taskId = res["task_id"] as String;
      // Guardar en prefs para recuperar si el usuario sale y vuelve
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefActiveTaskKey, taskId);
      _listenToTaskProgress(taskId);
      await _loadRecentTasks();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error al subir el archivo de audio")),
        );
      }
    }
  }

  void _listenToTaskProgress(String taskId, {bool recovered = false}) {
    setState(() {
      _activeTaskId = taskId;
      _isRecoveringTask = recovered;
      _taskStatus = recovered
          ? "Retomando separación en curso..."
          : "Iniciando separación con IA (6 pistas Demucs)...";
      _separationProgress = recovered ? _separationProgress : 5;
    });

    _wsChannel?.sink.close();
    _pollTimer?.cancel();

    final wsUrl = _api.getWebSocketUrl("/ws/tasks/$taskId");

    bool wsWorking = false;

    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsChannel!.stream.listen(
        (data) {
          wsWorking = true;
          final payload = jsonDecode(data as String);
          final progress = (payload["progress"] as num?)?.toInt() ?? 0;
          final status = payload["status"] as String? ?? "";
          final stems = payload["stems"] as Map<String, dynamic>?;

          if (mounted) {
            setState(() {
              _separationProgress = progress;
              _taskStatus = "Separando pistas ($progress%)...";
            });

            if (status == "completed" && stems != null && stems.isNotEmpty) {
              _onSeparationCompleted(stems);
            } else if (status == "failed") {
              _clearActiveTask();
              setState(() => _taskStatus = "Error en la separación.");
            }
          }
        },
        onError: (_) => _startPollingFallback(taskId),
        onDone: () {
          // WS cerrado — si no completó, hacer polling
          if (_activeTaskId == taskId && mounted && !wsWorking) {
            _startPollingFallback(taskId);
          }
        },
        cancelOnError: false,
      );

      // Si en 8s el WS no ha recibido nada, activar polling de respaldo
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted && _activeTaskId == taskId && !wsWorking) {
          _startPollingFallback(taskId);
        }
      });
    } catch (_) {
      _startPollingFallback(taskId);
    }
  }

  void _startPollingFallback(String taskId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (!mounted || _activeTaskId != taskId) {
        timer.cancel();
        return;
      }
      final task = await _api.getStemTask(taskId);
      if (task == null) return;

      final status = task["status"] as String? ?? "";
      final progress = (task["progress"] as num?)?.toInt() ?? 0;
      final stems = task["stems"] as Map<String, dynamic>?;

      if (mounted) {
        setState(() {
          _separationProgress = progress;
          _taskStatus = "Procesando ($progress%)...";
        });

        if (status == "completed" && stems != null && stems.isNotEmpty) {
          timer.cancel();
          _onSeparationCompleted(stems);
        } else if (status == "failed") {
          timer.cancel();
          _clearActiveTask();
          setState(() => _taskStatus = "Error en la separación.");
        }
      }
    });
  }

  Future<void> _clearActiveTask() async {
    setState(() {
      _activeTaskId = null;
      _isRecoveringTask = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefActiveTaskKey);
  }

  void _onSeparationCompleted(Map<String, dynamic> stems) {
    setState(() {
      _taskStatus = "¡Separación completada!";
    });
    _clearActiveTask();
    _pollTimer?.cancel();

    final Map<String, String> fullUrls = {};
    stems.forEach((stemName, relativeUrl) {
      fullUrls[stemName] = _api.getFullUrl(relativeUrl as String);
    });

    _player.loadStems(fullUrls);
    _loadRecentTasks();
  }

  void _loadCompletedTaskStems(String songName, Map<String, dynamic> stems) {
    setState(() => _currentLoadedSongName = songName);
    final Map<String, String> fullUrls = {};
    stems.forEach((stemName, relativeUrl) {
      fullUrls[stemName] = _api.getFullUrl(relativeUrl as String);
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

  Future<void> _renameTaskCollection(String taskId, String? currentCollection) async {
    final controller = TextEditingController(text: currentCollection ?? "");
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StageTheme.surface,
        title: const Text("Mover a Colección"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Nombre de la colección",
            hintText: "Ej: Ensayo Sep 2026, Boda Verano...",
            prefixIcon: Icon(Icons.folder_outlined),
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar", style: TextStyle(color: StageTheme.textSecondary)),
          ),
          if (currentCollection != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, "__NONE__"),
              child: const Text("Sin Colección", style: TextStyle(color: StageTheme.alertRed)),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: StageTheme.amberGold, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("Guardar"),
          ),
        ],
      ),
    );

    if (result != null) {
      final newCollection = result == "__NONE__" ? null : (result.isEmpty ? null : result);
      await _api.setTaskCollection(taskId, newCollection);
      _loadRecentTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveTask = _activeTaskId != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mezclador"),
        actions: [
          const ProfileAppBarButton(),
          IconButton(
            icon: const Icon(Icons.library_music),
            tooltip: "Canciones procesadas",
            onPressed: _showRecentTasksModal,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: "Subir audio para aislar pistas",
            // Permitir subir incluso si hay tarea en curso (corre en servidor)
            onPressed: _isUploading ? null : _pickAndUploadAudio,
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de progreso si hay subida o separación en curso
          if (_isUploading || hasActiveTask) _buildProgressBanner(),

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
          ] else if (!_isUploading && !hasActiveTask)
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

                    // Lista de canciones procesadas agrupadas por colección
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Canciones Procesadas",
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
                    _buildGroupedTaskList(),
                  ],
                ),
              ),
            )
          else if (hasActiveTask)
            // Si hay tarea activa pero no hay pistas cargadas, expandir el banner
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          color: StageTheme.flameOrange,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _taskStatus,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      if (_isRecoveringTask) ...[
                        const SizedBox(height: 8),
                        const Text(
                          "La separación continúa en el servidor aunque salgas de la app.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: StageTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 24),
                      TextButton.icon(
                        icon: const Icon(Icons.library_music, size: 18),
                        label: const Text("Ver canciones anteriores"),
                        onPressed: _showRecentTasksModal,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupedTaskList() {
    if (_recentTasks.isEmpty) {
      return Container(
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
      );
    }

    // Agrupar por collection_name (null → "Sin grupo")
    final Map<String, List<dynamic>> grouped = {};
    for (final t in _recentTasks) {
      final collection = (t["collection_name"] as String?) ?? "";
      final key = collection.isEmpty ? "__none__" : collection;
      grouped.putIfAbsent(key, () => []).add(t);
    }

    // Ordenar: colecciones con nombre primero, "Sin grupo" al final
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == "__none__") return 1;
        if (b == "__none__") return -1;
        return a.compareTo(b);
      });

    return Column(
      children: sortedKeys.map((key) {
        final tasks = grouped[key]!;
        final label = key == "__none__" ? "Sin Colección" : key;
        _collectionExpanded.putIfAbsent(key, () => true);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              // Encabezado de colección
              InkWell(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                onTap: () => setState(() => _collectionExpanded[key] = !_collectionExpanded[key]!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        key == "__none__" ? Icons.music_note : Icons.folder,
                        color: key == "__none__" ? StageTheme.textSecondary : StageTheme.amberGold,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      Text(
                        "${tasks.length} canción${tasks.length != 1 ? 'es' : ''}",
                        style: const TextStyle(color: StageTheme.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _collectionExpanded[key]! ? Icons.expand_less : Icons.expand_more,
                        color: StageTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),

              // Canciones de la colección
              if (_collectionExpanded[key]!)
                ...tasks.map((t) => _buildTaskTile(t)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTaskTile(dynamic t) {
    final taskId = t["task_id"] as String? ?? t["id"] as String? ?? "";
    final filename = t["filename"] as String? ?? "Audio";
    final status = t["status"] as String? ?? "";
    final stems = t["stems"] as Map<String, dynamic>? ?? {};
    final collection = t["collection_name"] as String?;
    final isCompleted = status == "completed";
    final isProcessing = status == "processing" || status == "pending";
    final stemCount = stems.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: isCompleted
              ? StageTheme.electricGreen.withOpacity(0.2)
              : isProcessing
                  ? StageTheme.amberGold.withOpacity(0.2)
                  : StageTheme.alertRed.withOpacity(0.2),
          child: Icon(
            isCompleted
                ? Icons.check
                : isProcessing
                    ? Icons.hourglass_top
                    : Icons.error_outline,
            color: isCompleted
                ? StageTheme.electricGreen
                : isProcessing
                    ? StageTheme.amberGold
                    : StageTheme.alertRed,
            size: 20,
          ),
        ),
        title: Text(filename, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(
          isCompleted
              ? "$stemCount pistas: ${stems.keys.map(_getStemLabel).join(', ')}"
              : isProcessing
                  ? "Procesando..."
                  : "Estado: $status",
          style: const TextStyle(fontSize: 11, color: StageTheme.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mover a colección
            IconButton(
              icon: const Icon(Icons.folder_outlined, size: 20, color: StageTheme.textSecondary),
              tooltip: "Colección",
              onPressed: () => _renameTaskCollection(taskId, collection),
            ),
            // Eliminar
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: StageTheme.alertRed),
              tooltip: "Eliminar",
              onPressed: () => _deleteTask(taskId, filename),
            ),
            // Cargar si está completa
            if (isCompleted) ...[
              const SizedBox(width: 2),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: StageTheme.amberGold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  minimumSize: const Size(56, 34),
                ),
                child: const Text("Cargar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _loadCompletedTaskStems(filename, stems),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBanner() {
    final progress = _isUploading ? _uploadProgress : _separationProgress;
    final isIndeterminate = _activeTaskId != null && _separationProgress <= 5;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: StageTheme.surfaceElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _taskStatus.isEmpty ? "Procesando..." : _taskStatus,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isIndeterminate)
                Text(
                  "$progress%",
                  style: const TextStyle(color: StageTheme.amberGold, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 8),
          isIndeterminate
              ? const LinearProgressIndicator(
                  backgroundColor: StageTheme.border,
                  color: StageTheme.flameOrange,
                )
              : LinearProgressIndicator(
                  value: progress / 100.0,
                  backgroundColor: StageTheme.border,
                  color: StageTheme.flameOrange,
                ),
          if (_activeTaskId != null && !_isUploading) ...[
            const SizedBox(height: 4),
            const Text(
              "Puedes salir de esta pantalla — la separación continúa en el servidor.",
              style: TextStyle(fontSize: 10, color: StageTheme.textSecondary),
            ),
          ],
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
              IconButton(
                icon: const Icon(Icons.skip_previous),
                tooltip: "Inicio",
                iconSize: 28,
                onPressed: _player.restart,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.replay_10),
                tooltip: "Retroceder 10s",
                iconSize: 32,
                onPressed: () => _player.seekRelative(const Duration(seconds: -10)),
              ),
              const SizedBox(width: 12),
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
              IconButton(
                icon: const Icon(Icons.forward_10),
                tooltip: "Avanzar 10s",
                iconSize: 32,
                onPressed: () => _player.seekRelative(const Duration(seconds: 10)),
              ),
              const SizedBox(width: 8),
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

          // Herramientas de ensayo: Velocidad, Bucle A-B y Reset Mezcla
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_getStemIcon(track.name), color: accentColor, size: 26),
                  ),
                  const SizedBox(width: 12),

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

                  Expanded(
                    flex: 3,
                    child: Slider(
                      value: track.volume,
                      activeColor: accentColor,
                      onChanged: (val) => _player.setTrackVolume(track.name, val),
                    ),
                  ),

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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) => Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 8),
                Expanded(
                  child: _recentTasks.isEmpty
                      ? const Center(
                          child: Text(
                            "No hay canciones procesadas todavía",
                            style: TextStyle(color: StageTheme.textMuted),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollCtrl,
                          itemCount: _recentTasks.length,
                          itemBuilder: (ctx, index) {
                            final t = _recentTasks[index];
                            final taskId = t["task_id"] as String? ?? t["id"] as String? ?? "";
                            final stems = t["stems"] as Map<String, dynamic>? ?? {};
                            final collection = t["collection_name"] as String?;
                            final isCompleted = t["status"] == "completed";
                            final stemCount = stems.length;

                            return ListTile(
                              leading: Icon(
                                isCompleted ? Icons.check_circle : Icons.hourglass_top,
                                color: isCompleted ? StageTheme.electricGreen : StageTheme.amberGold,
                              ),
                              title: Text(t["filename"] ?? "Audio", style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                [
                                  if (collection != null && collection.isNotEmpty) "📁 $collection",
                                  if (isCompleted) "$stemCount pistas",
                                  if (!isCompleted) "Estado: ${t["status"]}",
                                ].join(" · "),
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
                                      _deleteTask(taskId, t["filename"] ?? "Audio");
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
          ),
        );
      },
    );
  }
}
