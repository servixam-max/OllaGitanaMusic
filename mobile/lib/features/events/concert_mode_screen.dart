import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/stage_theme.dart';

/// Vista a pantalla completa para usar EN EL ESCENARIO durante un bolo.
///
/// - Muestra el setlist completo en orden, con la canción actual destacada.
/// - Marca las canciones ya tocadas con un toque (para no perderse en directo).
/// - Mantiene la pantalla siempre encendida mientras esté abierta.
/// - Muestra las notas del evento, el lugar y la hora de forma legible.
class ConcertModeScreen extends StatefulWidget {
  final Map<String, dynamic> event;

  const ConcertModeScreen({super.key, required this.event});

  @override
  State<ConcertModeScreen> createState() => _ConcertModeScreenState();
}

class _ConcertModeScreenState extends State<ConcertModeScreen> {
  int _currentIndex = 0;
  final Set<int> _played = {};
  bool _fontBig = true;

  List<dynamic> get _setlist => (widget.event["setlist"] as List<dynamic>?) ?? [];

  @override
  void initState() {
    super.initState();
    // Pantalla siempre encendida durante todo el concierto
    WakelockPlus.enable();
    // Mantener la pantalla en horizontal-bloqueado no; solo permitir vertical y ocultar barras
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _next() {
    if (_setlist.isEmpty) return;
    setState(() {
      _played.add(_currentIndex);
      if (_currentIndex < _setlist.length - 1) {
        _currentIndex++;
      }
    });
  }

  void _previous() {
    if (_setlist.isEmpty) return;
    setState(() {
      if (_currentIndex > 0) {
        _currentIndex--;
        _played.remove(_currentIndex);
      }
    });
  }

  void _jumpTo(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return "";
    try {
      final dt = DateTime.parse(raw);
      const months = [
        "enero", "febrero", "marzo", "abril", "mayo", "junio",
        "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"
      ];
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return "${dt.day} de ${months[dt.month - 1]} · ${h}:${m}h";
    } catch (_) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.event["name"] ?? "Bolo";
    final location = widget.event["location"] ?? "";
    final notes = widget.event["notes"] ?? "";
    final dateStr = _formatDate(widget.event["event_date"]);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Cabecera del bolo
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: const BoxDecoration(
                color: StageTheme.surface,
                border: Border(bottom: BorderSide(color: StageTheme.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: StageTheme.amberGold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (dateStr.isNotEmpty || location.isNotEmpty)
                          Text(
                            [dateStr, location].where((s) => s.isNotEmpty).join(" · "),
                            style: const TextStyle(fontSize: 12, color: StageTheme.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            notes,
                            style: const TextStyle(fontSize: 12, color: StageTheme.electricGreen),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: StageTheme.textSecondary),
                    tooltip: "Salir del modo concierto",
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),

            // Progreso del bolo
            if (_setlist.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: StageTheme.background,
                child: Row(
                  children: [
                    Text(
                      "${_played.length} de ${_setlist.length} tocadas",
                      style: const TextStyle(fontSize: 12, color: StageTheme.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _setlist.isEmpty ? 0 : _played.length / _setlist.length,
                          minHeight: 6,
                          backgroundColor: StageTheme.border,
                          color: StageTheme.electricGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Setlist grande
            Expanded(
              child: _setlist.isEmpty
                  ? const Center(
                      child: Text(
                        "Este evento no tiene setlist.\nAñade canciones desde la pantalla de Eventos.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: StageTheme.textMuted, fontSize: 15),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _setlist.length,
                      itemBuilder: (context, index) {
                        final song = _setlist[index];
                        final isCurrent = index == _currentIndex;
                        final isPlayed = _played.contains(index);
                        final title = song["title"] ?? "";
                        final artist = song["artist"] ?? "";
                        final songNotes = song["notes"] ?? "";

                        return GestureDetector(
                          onTap: () => _jumpTo(index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: isCurrent ? 14 : 10,
                            ),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? StageTheme.flameOrange.withValues(alpha: 0.18)
                                  : (isPlayed ? StageTheme.surface.withValues(alpha: 0.5) : StageTheme.surface),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isCurrent
                                    ? StageTheme.flameOrange
                                    : (isPlayed ? StageTheme.electricGreen.withValues(alpha: 0.4) : StageTheme.border),
                                width: isCurrent ? 2 : 1,
                              ),
                              boxShadow: isCurrent ? StageTheme.glowOrange : null,
                            ),
                            child: Row(
                              children: [
                                // Número de canción
                                Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isPlayed
                                        ? StageTheme.electricGreen
                                        : (isCurrent ? StageTheme.flameOrange : StageTheme.surfaceElevated),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: isPlayed
                                      ? const Icon(Icons.check, color: Colors.black, size: 22)
                                      : Text(
                                          "${index + 1}",
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: isCurrent ? Colors.white : StageTheme.textSecondary,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: TextStyle(
                                          fontSize: _fontBig ? (isCurrent ? 20 : 17) : 15,
                                          fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                                          color: isPlayed ? StageTheme.textMuted : Colors.white,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (artist.isNotEmpty)
                                        Text(
                                          artist,
                                          style: const TextStyle(fontSize: 12, color: StageTheme.textSecondary),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      if (songNotes.isNotEmpty)
                                        Text(
                                          songNotes,
                                          style: const TextStyle(fontSize: 11, color: StageTheme.amberGold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                // Marcar tocada
                                IconButton(
                                  icon: Icon(
                                    isPlayed ? Icons.undo : Icons.check_circle_outline,
                                    color: isPlayed ? StageTheme.electricGreen : StageTheme.textMuted,
                                  ),
                                  tooltip: isPlayed ? "Marcar como no tocada" : "Marcar como tocada",
                                  onPressed: () {
                                    setState(() {
                                      if (isPlayed) {
                                        _played.remove(index);
                                      } else {
                                        _played.add(index);
                                        if (index == _currentIndex && index < _setlist.length - 1) {
                                          _currentIndex++;
                                        }
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Controles grandes para el escenario
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: StageTheme.surface,
                border: Border(top: BorderSide(color: StageTheme.border)),
              ),
              child: Row(
                children: [
                  IconButton(
                    iconSize: 34,
                    icon: const Icon(Icons.skip_previous_rounded, color: StageTheme.textSecondary),
                    tooltip: "Canción anterior",
                    onPressed: _previous,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.skip_next_rounded, size: 26),
                      label: const Text("SIGUIENTE", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StageTheme.flameOrange,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 56),
                      ),
                      onPressed: _next,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    iconSize: 30,
                    icon: Icon(
                      _fontBig ? Icons.text_fields : Icons.text_decrease,
                      color: StageTheme.amberGold,
                    ),
                    tooltip: _fontBig ? "Letra más pequeña" : "Letra más grande",
                    onPressed: () => setState(() => _fontBig = !_fontBig),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
