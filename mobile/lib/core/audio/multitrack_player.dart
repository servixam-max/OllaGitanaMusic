import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class StemTrackState {
  final String name;
  final String url;
  final AudioPlayer player;
  double volume;
  bool isMuted;
  bool isSolo;

  StemTrackState({
    required this.name,
    required this.url,
    required this.player,
    this.volume = 1.0,
    this.isMuted = false,
    this.isSolo = false,
  });
}

class MultitrackPlayer extends ChangeNotifier {
  final Map<String, StemTrackState> _tracks = {};
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _syncTimer;

  // Controles maestros y herramientas de ensayo
  double _masterVolume = 1.0;
  bool _isMasterMuted = false;
  double _speed = 1.0;
  double _pitch = 1.0;

  // Bucle A-B (Loop de ensayo)
  bool _isLooping = false;
  Duration? _loopStart;
  Duration? _loopEnd;

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

  Future<void> loadStems(Map<String, String> stemUrls) async {
    _isLoading = true;
    notifyListeners();

    await _cleanupPlayers();

    try {
      final List<StemTrackState> loaded = [];

      // Carga en paralelo de todas las pistas simultáneamente
      await Future.wait(
        stemUrls.entries.map((entry) async {
          final stemName = entry.key;
          final url = entry.value;
          final player = AudioPlayer();

          try {
            await player.setUrl(url);
            await player.setSpeed(_speed);
            await player.setPitch(_pitch);

            final trackDur = player.duration ?? Duration.zero;
            if (trackDur > _duration) {
              _duration = trackDur;
            }

            loaded.add(StemTrackState(
              name: stemName,
              url: url,
              player: player,
            ));
          } catch (err) {
            print("[MultitrackPlayer] Error cargando stem $stemName: $err");
          }
        }),
      );

      for (final t in loaded) {
        _tracks[t.name] = t;
      }

      _applyAudioVolumes();

      // Escuchar la posición del primer track como reloj maestro
      if (_tracks.isNotEmpty) {
        _tracks.values.first.player.positionStream.listen((pos) {
          _position = pos;

          // Manejo del bucle A-B
          if (_isLooping && _loopStart != null && _loopEnd != null) {
            if (pos >= _loopEnd!) {
              seek(_loopStart!);
              return;
            }
          }

          notifyListeners();
        });

        // Escuchar fin de reproducción
        _tracks.values.first.player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            if (_isLooping && _loopStart != null) {
              seek(_loopStart!);
              play();
            } else {
              _isPlaying = false;
              _position = Duration.zero;
              seek(Duration.zero);
              notifyListeners();
            }
          }
        });
      }

      // Verificación suave de desincronización (solo si el desfase supera 350ms)
      _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) => _alignTracks());

    } catch (e) {
      print("[MultitrackPlayer] Error general cargando stems: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _alignTracks() {
    if (!_isPlaying || _tracks.length <= 1) return;

    final masterPos = _tracks.values.first.player.position;
    for (final track in _tracks.values.skip(1)) {
      final diff = (track.player.position - masterPos).inMilliseconds.abs();
      // Solo realinear si hay un retraso evidente (>350ms) para evitar chasquidos
      if (diff > 350) {
        track.player.seek(masterPos);
      }
    }
  }

  Future<void> play() async {
    if (_tracks.isEmpty) return;
    _isPlaying = true;
    notifyListeners();

    // Sincronizar todos los reproductores exactamente a la posición actual antes de arrancar
    final currentPos = _position;
    await Future.wait(_tracks.values.map((t) => t.player.seek(currentPos)));
    await Future.wait(_tracks.values.map((t) => t.player.play()));
  }

  Future<void> pause() async {
    if (_tracks.isEmpty) return;
    _isPlaying = false;
    notifyListeners();

    await Future.wait(_tracks.values.map((t) => t.player.pause()));
  }

  Future<void> seek(Duration newPosition) async {
    _position = newPosition;
    notifyListeners();

    await Future.wait(_tracks.values.map((t) => t.player.seek(newPosition)));
  }

  Future<void> seekRelative(Duration delta) async {
    final targetMs = (_position.inMilliseconds + delta.inMilliseconds)
        .clamp(0, _duration.inMilliseconds);
    await seek(Duration(milliseconds: targetMs));
  }

  Future<void> restart() async {
    await seek(Duration.zero);
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
    _loopStart = _position;
    if (_loopEnd != null && _loopEnd! <= _loopStart!) {
      _loopEnd = null;
    }
    _isLooping = _loopStart != null && _loopEnd != null;
    notifyListeners();
  }

  void setLoopPointB() {
    if (_loopStart != null && _position > _loopStart!) {
      _loopEnd = _position;
      _isLooping = true;
    } else {
      _loopEnd = _position;
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
    await _cleanupPlayers();
    super.dispose();
  }
}
