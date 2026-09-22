import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/stage_theme.dart';
import '../../core/widgets/profile_app_bar_button.dart';
import '../../core/widgets/stage_sheet.dart';
import 'concert_mode_screen.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final ApiClient _api = ApiClient();
  List<dynamic> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  /// Resumen de cabecera: próximos bolos y finalizados por separado
  String _eventsSummary() {
    final now = DateTime.now();
    int upcoming = 0;
    int past = 0;
    for (final e in _events) {
      final dt = _parseEventDate(e["event_date"] as String?);
      if (dt == null) continue;
      if (dt.isAfter(now)) {
        upcoming++;
      } else {
        past++;
      }
    }
    final parts = <String>[];
    if (upcoming > 0) parts.add("$upcoming próximo${upcoming != 1 ? 's' : ''}");
    if (past > 0) parts.add("$past finalizado${past != 1 ? 's' : ''}");
    return parts.isEmpty ? "Sin eventos" : parts.join(" · ");
  }

  /// Abre el Modo Concierto a pantalla completa (para usar en el escenario)
  void _openConcertMode(Map<String, dynamic> event) {
    if (((event["setlist"] as List<dynamic>?) ?? []).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Añade canciones al setlist para usar el Modo Concierto"),
          backgroundColor: StageTheme.amberGold,
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ConcertModeScreen(event: event)),
    );
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    final events = await _api.getEvents();
    if (mounted) {
      setState(() {
        _events = events;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteEvent(String eventId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StageTheme.surface,
        title: const Text("Eliminar Evento"),
        content: const Text("¿Estás seguro de que deseas eliminar este evento y su setlist?"),
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
      await _api.deleteEvent(eventId);
      _loadEvents();
    }
  }

  /// Abre Google Calendar para agendar el evento
  Future<void> _exportToGoogleCalendar(Map<String, dynamic> event) async {
    final name = event["name"] ?? "Evento Olla Gitana";
    final location = event["location"] ?? "";
    final notes = event["notes"] ?? "";
    final dateStr = event["event_date"] ?? "";
    final setlist = (event["setlist"] as List<dynamic>? ?? []);

    DateTime eventDate;
    try {
      eventDate = DateTime.parse(dateStr);
    } catch (_) {
      eventDate = DateTime.now().add(const Duration(days: 7));
    }

    final endDate = eventDate.add(const Duration(hours: 3));

    // Formato Google Calendar: YYYYMMDDTHHmmSSZ
    final startFormatted = DateFormat("yyyyMMdd'T'HHmmss").format(eventDate.toUtc()) + "Z";
    final endFormatted = DateFormat("yyyyMMdd'T'HHmmss").format(endDate.toUtc()) + "Z";

    final StringBuffer detailsBuffer = StringBuffer();
    if (notes.isNotEmpty) {
      detailsBuffer.writeln("Notas: $notes\n");
    }
    if (setlist.isNotEmpty) {
      detailsBuffer.writeln("REPERTORIO / SETLIST:");
      for (int i = 0; i < setlist.length; i++) {
        final song = setlist[i];
        detailsBuffer.writeln("${i + 1}. ${song["title"]} - ${song["artist"]}");
      }
    }

    final calendarUrl = "https://calendar.google.com/calendar/render?action=TEMPLATE"
        "&text=${Uri.encodeComponent(name)}"
        "&dates=$startFormatted/$endFormatted"
        "&details=${Uri.encodeComponent(detailsBuffer.toString())}"
        "&location=${Uri.encodeComponent(location)}";

    try {
      await launchUrl(Uri.parse(calendarUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se pudo abrir Google Calendar")),
        );
      }
    }
  }

  /// Formatea fechas en español de forma natural y elegante para músicos (sin 'T' ni segundos)
  String _formatSpanishDate(String? dateStr, {bool full = false}) {
    if (dateStr == null || dateStr.trim().isEmpty) return "Fecha por confirmar";
    try {
      final dt = DateTime.parse(dateStr);
      const weekdays = [
        "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"
      ];
      const months = [
        "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
        "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"
      ];
      final dayName = weekdays[dt.weekday - 1];
      final monthName = months[dt.month - 1];
      final day = dt.day;
      final year = dt.year;
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');

      if (dt.hour == 0 && dt.minute == 0 && !dateStr.contains('T') && !dateStr.contains(':')) {
        return "$dayName, $day de $monthName de $year";
      }

      if (full) {
        return "$dayName, $day de $monthName de $year a las $hour:${minute}h";
      } else {
        return "$dayName, $day de $monthName - $hour:${minute}h";
      }
    } catch (_) {
      return dateStr.replaceAll('T', ' ').replaceAll(RegExp(r':\d{2}$'), '');
    }
  }

  DateTime? _parseEventDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      return null;
    }
  }

  String _getMonthAbbr(DateTime dt) {
    const months = ["ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"];
    return months[dt.month - 1];
  }

  String _getCountdownBadge(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(dt.year, dt.month, dt.day);
    final diff = eventDay.difference(today).inDays;

    if (diff < 0) return "Finalizado";
    if (diff == 0) return "¡HOY!";
    if (diff == 1) return "¡MAÑANA!";
    return "En $diff días";
  }

  Color _getCountdownColor(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(dt.year, dt.month, dt.day);
    final diff = eventDay.difference(today).inDays;

    if (diff < 0) return StageTheme.textMuted;
    if (diff == 0) return StageTheme.alertRed;
    if (diff <= 3) return StageTheme.flameOrange;
    return StageTheme.electricGreen;
  }

  /// Comparte el evento y setlist por WhatsApp con formato profesional
  Future<void> _shareOnWhatsApp(Map<String, dynamic> event) async {
    final name = event["name"] ?? "Bolo Olla Gitana";
    final location = event["location"] ?? "";
    final notes = event["notes"] ?? "";
    final dateStr = event["event_date"] ?? "";
    final setlist = (event["setlist"] as List<dynamic>? ?? []);

    final formattedDate = _formatSpanishDate(dateStr, full: true);

    final StringBuffer msg = StringBuffer();
    msg.writeln("🎸🔥 *OLLA GITANA - EVENTO EN DIRECTO* 🔥🎸\n");
    msg.writeln("📌 *Evento:* $name");
    msg.writeln("📅 *Fecha:* $formattedDate");
    if (location.isNotEmpty) {
      msg.writeln("📍 *Lugar:* $location");
    }
    if (notes.isNotEmpty) {
      msg.writeln("📝 *Observaciones:* $notes");
    }
    msg.writeln();

    if (setlist.isNotEmpty) {
      msg.writeln("🎶 *REPERTORIO / SETLIST DE TEMAS:*");
      for (int i = 0; i < setlist.length; i++) {
        final song = setlist[i];
        msg.writeln("${i + 1}. *${song["title"]}* - ${song["artist"]}");
      }
      msg.writeln();
    }

    msg.writeln("✨ _¡A darlo todo en el escenario con Olla Gitana!_ 💃🕺🍻");

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

  void _showEventDialog({Map<String, dynamic>? existingEvent}) async {
    final nameCtrl = TextEditingController(text: existingEvent?["name"] ?? "");
    final locationCtrl = TextEditingController(text: existingEvent?["location"] ?? "");
    final notesCtrl = TextEditingController(text: existingEvent?["notes"] ?? "");

    DateTime selectedDateTime;
    if (existingEvent != null && existingEvent["event_date"] != null) {
      try {
        selectedDateTime = DateTime.parse(existingEvent["event_date"]);
      } catch (_) {
        selectedDateTime = DateTime.now().add(const Duration(days: 7));
      }
    } else {
      selectedDateTime = DateTime.now().add(const Duration(days: 7));
    }

    // Cargar canciones del repertorio para seleccionar
    final repertoireSongs = await _api.getRepertoireSongs();
    List<Map<String, dynamic>> selectedSetlist = [];
    if (existingEvent != null && existingEvent["setlist"] != null) {
      selectedSetlist = List<Map<String, dynamic>>.from(existingEvent["setlist"]);
    }

    if (!mounted) return;

    bool saving = false;

    showStageSheet(
      context: context,
      title: existingEvent != null ? "Editar Evento" : "Nuevo Evento",
      builder: (ctx, _) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final dateDisplay = DateFormat("dd/MM/yyyy HH:mm").format(selectedDateTime);

            Future<void> pickDateTime() async {
              final pickedDate = await showDatePicker(
                context: ctx,
                initialDate: selectedDateTime,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (pickedDate == null) return;

              final pickedTime = await showTimePicker(
                context: ctx,
                initialTime: TimeOfDay.fromDateTime(selectedDateTime),
              );
              if (pickedTime == null) return;

              setModalState(() {
                selectedDateTime = DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  pickedTime.hour,
                  pickedTime.minute,
                );
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Expanded(
                      child: ListView(
                        children: [
                          TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              labelText: "Nombre del Evento *",
                              hintText: "Ej: Concierto Chiringuito El Sol",
                              filled: true,
                              fillColor: StageTheme.surfaceElevated,
                              prefixIcon: const Icon(Icons.celebration, color: StageTheme.flameOrange),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: pickDateTime,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: StageTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today, color: StageTheme.amberGold),
                                  const SizedBox(width: 12),
                                  Text("Fecha y Hora: $dateDisplay", style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  const Icon(Icons.arrow_drop_down, color: StageTheme.textMuted),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: locationCtrl,
                            decoration: InputDecoration(
                              labelText: "Lugar / Ubicación",
                              hintText: "Ej: Málaga, Paseo Marítimo",
                              filled: true,
                              fillColor: StageTheme.surfaceElevated,
                              prefixIcon: const Icon(Icons.place, color: StageTheme.flameOrange),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: notesCtrl,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: "Notas / Prueba de Sonido",
                              hintText: "Ej: Montaje a las 18:00h, llevar cables XLR",
                              filled: true,
                              fillColor: StageTheme.surfaceElevated,
                              prefixIcon: const Icon(Icons.note_alt, color: StageTheme.flameOrange),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Selector de Repertorio (Setlist)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Setlist (${selectedSetlist.length} temas seleccionados)",
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text("Añadir Canciones"),
                                style: TextButton.styleFrom(foregroundColor: StageTheme.amberGold),
                                onPressed: () {
                                  _showSetlistSelectorDialog(
                                    ctx,
                                    repertoireSongs,
                                    selectedSetlist,
                                    (updated) => setModalState(() => selectedSetlist = updated),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          if (selectedSetlist.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: StageTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                "No has añadido canciones al setlist todavía.\nToca en 'Añadir Canciones' para elegir del repertorio.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: StageTheme.textMuted, fontSize: 13),
                              ),
                            )
                          else
                            ...selectedSetlist.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final song = entry.value;
                              final isFirst = idx == 0;
                              final isLast = idx == selectedSetlist.length - 1;
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  leading: CircleAvatar(
                                    backgroundColor: StageTheme.amberGold,
                                    foregroundColor: Colors.black,
                                    radius: 14,
                                    child: Text("${idx + 1}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                  title: Text(song["title"] ?? "", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  subtitle: Text(song["artist"] ?? "", style: const TextStyle(fontSize: 11)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Reordenar: el orden del concierto lo decide la banda
                                      IconButton(
                                        icon: const Icon(Icons.keyboard_arrow_up, size: 20, color: StageTheme.amberGold),
                                        tooltip: "Subir en el setlist",
                                        visualDensity: VisualDensity.compact,
                                        onPressed: isFirst
                                            ? null
                                            : () {
                                                setModalState(() {
                                                  final item = selectedSetlist.removeAt(idx);
                                                  selectedSetlist.insert(idx - 1, item);
                                                });
                                              },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.keyboard_arrow_down, size: 20, color: StageTheme.amberGold),
                                        tooltip: "Bajar en el setlist",
                                        visualDensity: VisualDensity.compact,
                                        onPressed: isLast
                                            ? null
                                            : () {
                                                setModalState(() {
                                                  final item = selectedSetlist.removeAt(idx);
                                                  selectedSetlist.insert(idx + 1, item);
                                                });
                                              },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle, color: StageTheme.alertRed, size: 20),
                                        tooltip: "Quitar del setlist",
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          setModalState(() {
                                            selectedSetlist.removeAt(idx);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: StageTheme.flameOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text("El nombre del evento es obligatorio")),
                            );
                            return;
                          }

                          // Evitar doble pulsación mientras guarda
                          setModalState(() => saving = true);

                          Map<String, dynamic>? result;
                          if (existingEvent != null) {
                            result = await _api.updateEvent(
                              existingEvent["id"],
                              name: name,
                              eventDate: selectedDateTime.toIso8601String(),
                              location: locationCtrl.text.trim(),
                              notes: notesCtrl.text.trim(),
                              setlist: selectedSetlist,
                            );
                          } else {
                            result = await _api.createEvent(
                              name: name,
                              eventDate: selectedDateTime.toIso8601String(),
                              location: locationCtrl.text.trim(),
                              notes: notesCtrl.text.trim(),
                              setlist: selectedSetlist,
                            );
                          }

                          // Si falla, NO cerrar: el músico no pierde lo que escribió
                          if (result == null) {
                            setModalState(() => saving = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  backgroundColor: StageTheme.alertRed,
                                  content: Text("No se pudo guardar el evento. Revisa la conexión y vuelve a intentarlo."),
                                ),
                              );
                            }
                            return;
                          }

                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadEvents();
                        },
                        child: saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : Text(
                                existingEvent != null ? "Guardar Cambios" : "Crear Evento",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSetlistSelectorDialog(
    BuildContext parentCtx,
    List<dynamic> repertoireSongs,
    List<Map<String, dynamic>> currentSetlist,
    Function(List<Map<String, dynamic>>) onUpdate,
  ) {
    final List<Map<String, dynamic>> tempSetlist = List.from(currentSetlist);
    final TextEditingController filterCtrl = TextEditingController();

    showDialog(
      context: parentCtx,
      builder: (dlgCtx) {
        return StatefulBuilder(
          builder: (dlgCtx, setDlgState) {
            final query = filterCtrl.text.trim().toLowerCase();
            final filtered = query.isEmpty
                ? repertoireSongs
                : repertoireSongs.where((song) {
                    final title = (song["title"] ?? "").toString().toLowerCase();
                    final artist = (song["artist"] ?? "").toString().toLowerCase();
                    return title.contains(query) || artist.contains(query);
                  }).toList();

            return AlertDialog(
              backgroundColor: StageTheme.surface,
              title: Row(
                children: [
                  const Expanded(
                    child: Text("Añadir Temas al Setlist", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: StageTheme.textSecondary),
                    tooltip: "Cerrar",
                    onPressed: () => Navigator.pop(dlgCtx),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 440,
                child: Column(
                  children: [
                    // Buscador para encontrar un tema rápido entre todo el repertorio
                    TextField(
                      controller: filterCtrl,
                      decoration: InputDecoration(
                        hintText: "Buscar en el repertorio...",
                        isDense: true,
                        filled: true,
                        fillColor: StageTheme.surfaceElevated,
                        prefixIcon: const Icon(Icons.search, size: 20, color: StageTheme.amberGold),
                        suffixIcon: filterCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setDlgState(() => filterCtrl.clear()),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (_) => setDlgState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                "No hay canciones que coincidan con la búsqueda.",
                                style: TextStyle(color: StageTheme.textMuted),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final song = filtered[index];
                                final songId = song["id"];
                                final isSelected = tempSetlist.any((s) => s["id"] == songId);

                                return CheckboxListTile(
                                  activeColor: StageTheme.flameOrange,
                                  dense: true,
                                  title: Text(song["title"] ?? "", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  subtitle: Text(song["artist"] ?? "", style: const TextStyle(fontSize: 11)),
                                  value: isSelected,
                                  onChanged: (checked) {
                                    setDlgState(() {
                                      if (checked == true) {
                                        tempSetlist.add({
                                          "id": songId,
                                          "title": song["title"],
                                          "artist": song["artist"],
                                        });
                                      } else {
                                        tempSetlist.removeWhere((s) => s["id"] == songId);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dlgCtx),
                  child: const Text("Cancelar", style: TextStyle(color: StageTheme.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: StageTheme.flameOrange, foregroundColor: Colors.white),
                  onPressed: () {
                    onUpdate(tempSetlist);
                    Navigator.pop(dlgCtx);
                  },
                  child: const Text("Aplicar"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Eventos & Bolos",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
            Text(
              _eventsSummary(),
              style: const TextStyle(fontSize: 11, color: StageTheme.textSecondary, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          ProfileAppBarButton(onProfileChanged: () => setState(() {})),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: StageTheme.amberGold),
            tooltip: "Recargar eventos",
            onPressed: () => _loadEvents(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Banner de cabecera moderno con degradado
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: StageTheme.border),
                image: const DecorationImage(
                  image: AssetImage("assets/images/band_hero.jpg"),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                alignment: Alignment.bottomLeft,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: StageTheme.flameGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.celebration_rounded, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "CONCIERTOS & ENSAYOS",
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                        ),
                        Text(
                          "Setlists listos para el directo y WhatsApp",
                          style: TextStyle(color: StageTheme.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: StageTheme.flameOrange))
                : _events.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: StageTheme.surfaceElevated,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: StageTheme.border),
                                ),
                                child: const Icon(Icons.event_available_rounded, size: 36, color: StageTheme.amberGold),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "No hay eventos programados",
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Crea un nuevo bolo o ensayo con fecha, lugar y setlist para llevar a Google Calendar y compartir con el grupo.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: StageTheme.textSecondary, fontSize: 13),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text("Crear Primer Evento"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: StageTheme.flameOrange,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _showEventDialog(),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        itemCount: _events.length,
                        itemBuilder: (context, index) {
                          final event = _events[index];
                          final setlist = (event["setlist"] as List<dynamic>? ?? []);
                          final dateStr = event["event_date"] ?? "";
                          final dt = _parseEventDate(dateStr);

                          final displayDate = _formatSpanishDate(dateStr, full: false);
                          final countdown = dt != null ? _getCountdownBadge(dt) : null;
                          final countdownColor = dt != null ? _getCountdownColor(dt) : StageTheme.textMuted;

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              gradient: StageTheme.cardGradient,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: StageTheme.border),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Mini Calendario visual lateral estilo cartel
                                      if (dt != null)
                                        Container(
                                          width: 54,
                                          decoration: BoxDecoration(
                                            color: StageTheme.surfaceElevated,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: StageTheme.border),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.symmetric(vertical: 3),
                                                color: StageTheme.flameOrange,
                                                alignment: Alignment.center,
                                                child: Text(
                                                  _getMonthAbbr(dt),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w900,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 6),
                                                child: Text(
                                                  "${dt.day}",
                                                  style: const TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        Container(
                                          width: 54,
                                          height: 54,
                                          decoration: BoxDecoration(
                                            color: StageTheme.surfaceElevated,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.event_rounded, color: StageTheme.flameOrange, size: 26),
                                        ),
                                      const SizedBox(width: 12),
                                      // Nombre y detalles del evento
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    event["name"] ?? "Evento",
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, letterSpacing: -0.2),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (countdown != null)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: countdownColor.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(color: countdownColor.withValues(alpha: 0.4)),
                                                    ),
                                                    child: Text(
                                                      countdown,
                                                      style: TextStyle(
                                                        color: countdownColor,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(Icons.access_time_rounded, size: 13, color: StageTheme.amberGold),
                                                const SizedBox(width: 5),
                                                Expanded(
                                                  child: Text(
                                                    displayDate,
                                                    style: const TextStyle(color: StageTheme.amberGold, fontSize: 12, fontWeight: FontWeight.w600),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if ((event["location"] ?? "").isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  const Icon(Icons.place_outlined, size: 13, color: StageTheme.textSecondary),
                                                  const SizedBox(width: 5),
                                                  Expanded(
                                                    child: Text(
                                                      event["location"],
                                                      style: const TextStyle(color: StageTheme.textSecondary, fontSize: 12),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert_rounded, size: 20, color: StageTheme.textMuted),
                                        onSelected: (val) {
                                          if (val == "edit") {
                                            _showEventDialog(existingEvent: event);
                                          } else if (val == "delete") {
                                            _deleteEvent(event["id"]);
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(value: "edit", child: Text("Editar evento")),
                                          const PopupMenuItem(
                                            value: "delete",
                                            child: Text("Eliminar", style: TextStyle(color: StageTheme.alertRed)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // Resumen de Setlist con preview de temas
                                  GestureDetector(
                                    onTap: () => _showEventDialog(existingEvent: event),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: StageTheme.surfaceElevated,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: StageTheme.border),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.playlist_play_rounded, color: StageTheme.amberGold, size: 20),
                                              const SizedBox(width: 6),
                                              Text(
                                                "${setlist.length} canciones en el repertorio",
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                              ),
                                              const Spacer(),
                                              const Text("Editar >", style: TextStyle(fontSize: 11, color: StageTheme.amberGold, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          if (setlist.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 5,
                                              runSpacing: 4,
                                              children: setlist.take(3).map((s) {
                                                return Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: StageTheme.background,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    s["title"] ?? "",
                                                    style: const TextStyle(fontSize: 10, color: StageTheme.textSecondary),
                                                  ),
                                                );
                                              }).toList()
                                                ..addAll(setlist.length > 3
                                                    ? [
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: StageTheme.flameOrange.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            "+${setlist.length - 3} más",
                                                            style: const TextStyle(fontSize: 10, color: StageTheme.flameOrange, fontWeight: FontWeight.bold),
                                                          ),
                                                        )
                                                      ]
                                                    : []),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Modo Concierto: pantalla completa para el escenario
                                  if (setlist.isNotEmpty) ...[
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.stadium_rounded, size: 20),
                                        label: const Text(
                                          "MODO CONCIERTO",
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: StageTheme.flameOrange,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: () => _openConcertMode(event),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],

                                  // Botones de acción rápida: Google Calendar & WhatsApp
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          icon: const Icon(Icons.calendar_month_outlined, size: 16),
                                          label: const Text("Calendar", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: StageTheme.amberGold,
                                            side: const BorderSide(color: StageTheme.amberGold),
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          onPressed: () => _exportToGoogleCalendar(event),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.share_rounded, size: 16),
                                          label: const Text("WhatsApp", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: StageTheme.electricGreen,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            elevation: 0,
                                          ),
                                          onPressed: () => _shareOnWhatsApp(event),
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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: StageTheme.flameOrange,
        elevation: 6,
        icon: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
        label: const Text("Nuevo Evento", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        onPressed: () => _showEventDialog(),
      ),
    );
  }
}

