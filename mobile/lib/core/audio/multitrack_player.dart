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

  Map<String, StemTrackState> get tracks => _tracks;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  Duration get position => _position;
  Duration get duration => _duration;

  Future<void> loadStems(Map<String, String> stemUrls) async {
    _isLoading = true;
    notifyListeners();

    await dispose();

    try {
      for (final entry in stemUrls.entries) {
        final stemName = entry.key;
        final url = entry.value;
        final player = AudioPlayer();

        await player.setUrl(url);
        final trackDuration = player.duration ?? Duration.zero;
        if (trackDuration > _duration) {
          _duration = trackDuration;
        }

        _tracks[stemName] = StemTrackState(
          name: stemName,
          url: url,
          player: player,
        );
      }

      // Escuchar la posición del primer track como reloj maestro
      if (_tracks.isNotEmpty) {
        _tracks.values.first.player.positionStream.listen((pos) {
          _position = pos;
          notifyListeners();
        });
      }

      // Iniciar temporizador de sincronización para evitar desfases (>40ms)
      _syncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _alignTracks());

    } catch (e) {
      print("[MultitrackPlayer] Error cargando stems: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _alignTracks() {
    if (!_isPlaying || _tracks.isEmpty) return;

    final masterPos = _tracks.values.first.player.position;
    for (final track in _tracks.values.skip(1)) {
      final diff = (track.player.position - masterPos).inMilliseconds.abs();
      if (diff > 40) {
        track.player.seek(masterPos);
      }
    }
  }

  Future<void> play() async {
    if (_tracks.isEmpty) return;
    _isPlaying = true;
    notifyListeners();

    final futures = _tracks.values.map((t) => t.player.play());
    await Future.wait(futures);
  }

  Future<void> pause() async {
    if (_tracks.isEmpty) return;
    _isPlaying = false;
    notifyListeners();

    final futures = _tracks.values.map((t) => t.player.pause());
    await Future.wait(futures);
  }

  Future<void> seek(Duration newPosition) async {
    _position = newPosition;
    notifyListeners();

    final futures = _tracks.values.map((t) => t.player.seek(newPosition));
    await Future.wait(futures);
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

  void _applyAudioVolumes() {
    final hasAnySolo = _tracks.values.any((t) => t.isSolo);

    for (final track in _tracks.values) {
      if (hasAnySolo) {
        // Si hay algún canal en Solo, solo suenan los que tengan Solo activo y no estén en Mute
        final active = track.isSolo && !track.isMuted;
        track.player.setVolume(active ? track.volume : 0.0);
      } else {
        // Sin Solo: suena según su volumen si no está muteado
        track.player.setVolume(track.isMuted ? 0.0 : track.volume);
      }
    }
  }

  @override
  Future<void> dispose() async {
    _syncTimer?.cancel();
    _isPlaying = false;
    for (final track in _tracks.values) {
      await track.player.dispose();
    }
    _tracks.clear();
    _position = Duration.zero;
    _duration = Duration.zero;
    super.dispose();
  }
}
