import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/stage_theme.dart';

/// Metrónomo de ensayo.
///
/// Pensado para practicar sin depender del móvil de otro: pulsación visual,
/// vibración y clic del sistema con acento en el primer tiempo del compás.
/// Mantiene la pantalla encendida mientras está abierto.
class MetronomeScreen extends StatefulWidget {
  /// BPM inicial (por ejemplo, el tempo detectado de una canción analizada).
  final int initialBpm;

  const MetronomeScreen({super.key, this.initialBpm = 100});

  @override
  State<MetronomeScreen> createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends State<MetronomeScreen> {
  late int _bpm;
  int _beatsPerBar = 4;
  bool _isRunning = false;
  int _currentBeat = 0;
  Timer? _timer;
  DateTime _lastTick = DateTime.now();

  static const int _minBpm = 40;
  static const int _maxBpm = 240;

  @override
  void initState() {
    super.initState();
    _bpm = widget.initialBpm.clamp(_minBpm, _maxBpm);
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  int get _intervalMs => (60000 / _bpm).round();

  void _toggle() {
    if (_isRunning) {
      _stop();
    } else {
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    _currentBeat = 0;
    _lastTick = DateTime.now();
    setState(() => _isRunning = true);
    _tick();
    _timer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) => _tick());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _isRunning = false;
      _currentBeat = 0;
    });
  }

  void _tick() {
    final isDownbeat = _currentBeat == 0;

    // Vibración: más fuerte en el primer tiempo del compás
    if (isDownbeat) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    // Clic audible del sistema (refuerzo sonoro)
    SystemSound.play(SystemSoundType.click);

    if (mounted) {
      setState(() {
        _currentBeat = (_currentBeat + 1) % _beatsPerBar;
      });
    }
  }

  void _changeBpm(int delta) {
    final newBpm = (_bpm + delta).clamp(_minBpm, _maxBpm);
    setState(() => _bpm = newBpm);
    if (_isRunning) {
      // Reiniciar el temporizador con el nuevo intervalo
      _timer?.cancel();
      _timer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) => _tick());
    }
  }

  void _tapTempo() {
    final now = DateTime.now();
    final diff = now.difference(_lastTick).inMilliseconds;
    _lastTick = now;
    // Solo calcular si han pasado entre 200 ms y 2 s (pulsaciones humanas normales)
    if (diff >= 200 && diff <= 2000) {
      setState(() {
        _bpm = (60000 / diff).round().clamp(_minBpm, _maxBpm);
      });
      if (_isRunning) {
        _timer?.cancel();
        _timer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) => _tick());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _currentBeat == 0 && _isRunning ? StageTheme.flameOrange : StageTheme.amberGold;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Metrónomo"),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: StageTheme.textSecondary),
            tooltip: "Cerrar",
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Indicador visual del tiempo
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_beatsPerBar, (i) {
                      final isActive = _isRunning && i == _currentBeat;
                      final isDownbeat = i == 0;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 90),
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: isActive ? 34 : 22,
                        height: isActive ? 34 : 22,
                        decoration: BoxDecoration(
                          color: isActive
                              ? (isDownbeat ? StageTheme.flameOrange : StageTheme.amberGold)
                              : StageTheme.surfaceElevated,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isActive ? Colors.white24 : StageTheme.border,
                            width: 1.5,
                          ),
                          boxShadow: isActive ? StageTheme.glowOrange : null,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 40),

                  // BPM grande
                  Text(
                    "$_bpm",
                    style: TextStyle(
                      fontSize: 96,
                      fontWeight: FontWeight.w900,
                      color: accent,
                      letterSpacing: -3,
                      height: 1,
                    ),
                  ),
                  const Text(
                    "BPM",
                    style: TextStyle(fontSize: 16, color: StageTheme.textSecondary, letterSpacing: 3),
                  ),
                  const SizedBox(height: 32),

                  // Botones grandes para tocar en directo
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _bigRoundButton(
                        icon: Icons.remove,
                        tooltip: "Bajar 5 BPM",
                        onPressed: () => _changeBpm(-5),
                      ),
                      const SizedBox(width: 20),
                      _bigRoundButton(
                        icon: _isRunning ? Icons.stop : Icons.play_arrow,
                        tooltip: _isRunning ? "Detener" : "Iniciar",
                        primary: true,
                        onPressed: _toggle,
                      ),
                      const SizedBox(width: 20),
                      _bigRoundButton(
                        icon: Icons.add,
                        tooltip: "Subir 5 BPM",
                        onPressed: () => _changeBpm(5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Tap tempo
                  OutlinedButton.icon(
                    icon: const Icon(Icons.touch_app, size: 18),
                    label: const Text("TAP TEMPO (toca al ritmo)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: StageTheme.electricGreen,
                      side: const BorderSide(color: StageTheme.electricGreen),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: _tapTempo,
                  ),
                ],
              ),
            ),
          ),

          // Ajustes del compás y BPM
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: const BoxDecoration(
              color: StageTheme.surface,
              border: Border(top: BorderSide(color: StageTheme.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Compás", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [2, 3, 4, 6].map((beats) {
                    final isSelected = _beatsPerBar == beats;
                    return ChoiceChip(
                      label: Text("$beats/4"),
                      selected: isSelected,
                      selectedColor: StageTheme.flameOrange,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : StageTheme.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) {
                        setState(() {
                          _beatsPerBar = beats;
                          _currentBeat = 0;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Slider(
                  value: _bpm.toDouble(),
                  min: _minBpm.toDouble(),
                  max: _maxBpm.toDouble(),
                  divisions: _maxBpm - _minBpm,
                  label: "$_bpm BPM",
                  onChanged: (val) {
                    setState(() => _bpm = val.round());
                    if (_isRunning) {
                      _timer?.cancel();
                      _timer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) => _tick());
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigRoundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    return SizedBox(
      width: primary ? 92 : 64,
      height: primary ? 92 : 64,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
          backgroundColor: primary ? StageTheme.flameOrange : StageTheme.surfaceElevated,
          foregroundColor: Colors.white,
        ),
        onPressed: onPressed,
        child: Icon(icon, size: primary ? 48 : 28),
      ),
    );
  }
}
