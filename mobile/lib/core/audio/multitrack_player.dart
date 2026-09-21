import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'stem_cache.dart';

class StemTrackState {
  final String name;
  final String url;
  final AudioPlayer player;
  double volume;
  bool isMuted;
  bool isSolo;
  /// Ajuste fino de sincronía por pista (positivo = retrasa esa pista).
  Duration nudge;

  StemTrackState({
    required this.name,
    required this.url,
    required this.player,
    this.volume = 1.0,
    this.isMuted = false,
    this.isSolo = false,
    this.nudge = Duration.zero,
  });
}

class MultitrackPlayer extends ChangeNotifier {
  final Map<String, StemTrackState> _tracks = {};
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _syncTimer;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  // Controles maestros y herramientas de ensayo
  double _masterVolume = 1.0;
  bool _isMasterMuted = false;
  double _speed = 1.0;
  double _pitch = 1.0;

  // Bucle A-B (Loop de ensayo)
  bool _isLooping = false;
  Duration? _loopStart;
  Duration? _loopEnd;
  bool _sessionConfigured = false;
  double _loadingProgress = 0.0;
  bool _disposed = false;

  bool get mountedForNotify => !_disposed;
  double get loadingProgress => _loadingProgress;

  Map<String, StemTrackState> get tracks => _tracks;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  Duration get position => _position;
  Duration get duration => _duration;
  double get masterVolume => _masterVolume;
  bool get isMasterMuted => _isMasterMuted;
  double get speed => _speed;
  double get pitch => _pitch;
  bool get isLooping => _isLooping;
  Duration? get loopStart => _loopStart;
  Duration? get loopEnd => _loopEnd;

  bool get hasAnySolo => _tracks.values.any((t) => t.isSolo);
  bool get hasAnyNudge => _tracks.values.any((t) => t.nudge != Duration.zero);

  void setLoadingProgress(double value) {
    if (_disposed) return;
    _loadingProgress = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Configura la sesión de audio para reproducción musical en primer plano
  /// (evita que otras apps pausen la mezcla y mejora el rendimiento en ensayo).
  Future<void> _configureAudioSession() async {
    if (_sessionConfigured || kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _sessionConfigured = true;
    } catch (e) {
      print("[MultitrackPlayer] No se pudo configurar la sesión de audio: $e");
    }
  }

  Future<void> loadStems(Map<String, String> stemUrls, {bool useCache = true}) async {
    _isLoading = true;
    _loadingProgress = 0.0;
    notifyListeners();

    await _cleanupPlayers();
    await _configureAudioSession();

    try {
      final List<StemTrackState> loaded = [];
      final entries = stemUrls.entries.toList();
      int completed = 0;

      // Resolver rutas: descarga a caché local (evita cortes en el bucle A-B)
      Future<String> resolveUrl(String url) async {
        if (!useCache) return url;
        final local = await StemCache.instance.localPathFor(url, onProgress: (received, total) {
          if (total > 0 && mountedForNotify) {
            final perFile = received / total;
            setLoadingProgress((completed + perFile) / entries.length);
          }
        });
        return local ?? url;
      }

      // Carga en paralelo de todas las pistas simultáneamente
      await Future.wait(
        entries.map((entry) async {
          final stemName = entry.key;
          final remoteUrl = entry.value;
          final player = AudioPlayer();

          try {
            final playableUrl = await resolveUrl(remoteUrl);
            await player.setUrl(playableUrl);
            await player.setSpeed(_speed);
            await player.setPitch(_pitch);

            final trackDur = player.duration ?? Duration.zero;
            if (trackDur > _duration) {
              _duration = trackDur;
            }

            loaded.add(StemTrackState(
              name: stemName,
              url: remoteUrl,
              player: player,
            ));
          } catch (err) {
            print("[MultitrackPlayer] Error cargando stem $stemName: $err");
          } finally {
            completed++;
            if (mountedForNotify) {
              setLoadingProgress(completed / entries.length);
            }
          }
        }),
      );

      // Orden estándar de estudio/mesa de mezclas
      const preferredOrder = ['vocals', 'instrumental', 'drums', 'bass', 'guitar', 'piano', 'other'];
      loaded.sort((a, b) {
        final idxA = preferredOrder.indexOf(a.name.toLowerCase());
        final idxB = preferredOrder.indexOf(b.name.toLowerCase());
        final orderA = idxA == -1 ? 99 : idxA;
        final orderB = idxB == -1 ? 99 : idxB;
        return orderA.compareTo(orderB);
      });

      for (final t in loaded) {
        _tracks[t.name] = t;
      }

      _applyAudioVolumes();

      // Escuchar la posición del primer track como reloj maestro
      if (_tracks.isNotEmpty) {
        await _positionSub?.cancel();
        await _stateSub?.cancel();

        _positionSub = _tracks.values.first.player.positionStream.listen((pos) {
          _position = pos;

          // Manejo del bucle A-B
          if (_isLooping && _loopStart != null && _loopEnd != null) {
            if (pos >= _loopEnd!) {
              _seekAll(_loopStart!);
              return;
            }
          }

          notifyListeners();
        });

        // Al terminar, reiniciar en bucle o detener limpiamente
        _stateSub = _tracks.values.first.player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            if (_isLooping && _loopStart != null) {
              _seekAll(_loopStart!);
              play();
            } else {
              _isPlaying = false;
              _position = Duration.zero;
              _seekAll(Duration.zero);
              notifyListeners();
            }
          }
        });
      }

      // Verificación suave de desincronización (solo si el desfase supera 120ms)
      _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) => _alignTracks());

    } catch (e) {
      print("[MultitrackPlayer] Error general cargando stems: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Posición de referencia del reloj maestro (la primera pista).
  Duration get _masterPosition => _tracks.isEmpty ? _position : _tracks.values.first.player.position;

  void _alignTracks() {
    if (!_isPlaying || _tracks.length <= 1) return;

    final masterPos = _masterPosition;
    for (final track in _tracks.values.skip(1)) {
      final expected = masterPos + track.nudge;
      final diff = (track.player.position - expected).inMilliseconds.abs();
      // Solo realinear si hay un desfase evidente (>120ms) para evitar chasquidos
      if (diff > 120) {
        track.player.seek(expected);
      }
    }
  }

  /// Busca en todas las pistas aplicando el nudge individual de cada una.
  Future<void> _seekAll(Duration target) async {
    _position = target;
    await Future.wait(_tracks.values.map((t) {
      final adjusted = target + t.nudge;
      final clamped = Duration(
        milliseconds: adjusted.inMilliseconds.clamp(0, _duration.inMilliseconds > 0 ? _duration.inMilliseconds : adjusted.inMilliseconds),
      );
      return t.player.seek(clamped);
    }));
  }

  Future<void> play() async {
    if (_tracks.isEmpty) return;
    _isPlaying = true;
    notifyListeners();

    // Sincronizar todos los reproductores exactamente a la posición actual antes de arrancar
    final currentPos = _position;
    await Future.wait(_tracks.values.map((t) => t.player.seek(currentPos + t.nudge)));
    await Future.wait(_tracks.values.map((t) => t.player.play()));
  }

  Future<void> pause() async {
    if (_tracks.isEmpty) return;
    _isPlaying = false;
    notifyListeners();

    await Future.wait(_tracks.values.map((t) => t.player.pause()));
  }

  Future<void> seek(Duration newPosition) async {
    await _seekAll(newPosition);
    notifyListeners();
  }

  Future<void> seekRelative(Duration delta) async {
    final targetMs = (_masterPosition.inMilliseconds + delta.inMilliseconds)
        .clamp(0, _duration.inMilliseconds);
    await seek(Duration(milliseconds: targetMs));
  }

  Future<void> restart() async {
    await seek(Duration.zero);
  }

  // --- Ajuste fino de sincronía entre pistas (nudge) ---
  void setTrackNudge(String stemName, Duration nudge) {
    final track = _tracks[stemName];
    if (track == null) return;
    track.nudge = Duration(milliseconds: nudge.inMilliseconds.clamp(-500, 500));
    if (_isPlaying) {
      track.player.seek(_masterPosition + track.nudge);
    }
    notifyListeners();
  }

  void clearNudges() {
    for (final track in _tracks.values) {
      track.nudge = Duration.zero;
    }
    notifyListeners();
  }

  // --- Velocidad de reproducción (preservando tono) ---
  Future<void> setSpeed(double newSpeed) async {
    _speed = newSpeed.clamp(0.5, 1.5);
    notifyListeners();

    await Future.wait(_tracks.values.map((t) => t.player.setSpeed(_speed)));
  }

  // --- Tono / Transposición ---
  Future<void> setPitch(double newPitch) async {
    _pitch = newPitch.clamp(0.5, 1.5);
    notifyListeners();

    await Future.wait(_tracks.values.map((t) => t.player.setPitch(_pitch)));
  }

  // --- Bucle A-B ---
  void setLoopPointA() {
    _loopStart = _masterPosition;
    if (_loopEnd != null && _loopEnd! <= _loopStart!) {
      _loopEnd = null;
    }
    _isLooping = _loopStart != null && _loopEnd != null;
    notifyListeners();
  }

  void setLoopPointB() {
    final pos = _masterPosition;
    if (_loopStart != null && pos > _loopStart!) {
      _loopEnd = pos;
      _isLooping = true;
    } else {
      _loopEnd = pos;
      _isLooping = false;
    }
    notifyListeners();
  }

  void toggleLoop() {
    if (_loopStart != null && _loopEnd != null) {
      _isLooping = !_isLooping;
      notifyListeners();
    }
  }

  void clearLoop() {
    _isLooping = false;
    _loopStart = null;
    _loopEnd = null;
    notifyListeners();
  }

  // --- Volumen y Mezcla ---
  void setMasterVolume(double newVolume) {
    _masterVolume = newVolume.clamp(0.0, 1.0);
    _applyAudioVolumes();
    notifyListeners();
  }

  void toggleMasterMute() {
    _isMasterMuted = !_isMasterMuted;
    _applyAudioVolumes();
    notifyListeners();
  }

  void setTrackVolume(String stemName, double newVolume) {
    final track = _tracks[stemName];
    if (track == null) return;

    track.volume = newVolume.clamp(0.0, 1.0);
    _applyAudioVolumes();
    notifyListeners();
  }

  void toggleMute(String stemName) {
    final track = _tracks[stemName];
    if (track == null) return;

    track.isMuted = !track.isMuted;
    _applyAudioVolumes();
    notifyListeners();
  }

  void toggleSolo(String stemName) {
    final track = _tracks[stemName];
    if (track == null) return;

    track.isSolo = !track.isSolo;
    _applyAudioVolumes();
    notifyListeners();
  }

  void resetMix() {
    _masterVolume = 1.0;
    _isMasterMuted = false;
    for (final track in _tracks.values) {
      track.volume = 1.0;
      track.isMuted = false;
      track.isSolo = false;
      track.nudge = Duration.zero;
    }
    _applyAudioVolumes();
    notifyListeners();
  }

  void _applyAudioVolumes() {
    final soloActive = hasAnySolo;
    final masterFactor = _isMasterMuted ? 0.0 : _masterVolume;

    for (final track in _tracks.values) {
      double effectiveVol;
      if (soloActive) {
        final active = track.isSolo && !track.isMuted;
        effectiveVol = active ? (track.volume * masterFactor) : 0.0;
      } else {
        effectiveVol = track.isMuted ? 0.0 : (track.volume * masterFactor);
      }
      track.player.setVolume(effectiveVol.clamp(0.0, 1.0));
    }
  }

  Future<void> _cleanupPlayers() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    await _positionSub?.cancel();
    _positionSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    _isPlaying = false;
    for (final track in _tracks.values) {
      await track.player.dispose();
    }
    _tracks.clear();
    _position = Duration.zero;
    _duration = Duration.zero;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _cleanupPlayers();
    super.dispose();
  }
}
