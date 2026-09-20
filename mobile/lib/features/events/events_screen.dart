import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/stage_theme.dart';
import '../../core/widgets/profile_app_bar_button.dart';

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

  /// Comparte el evento y setlist por WhatsApp con formato profesional
  Future<void> _shareOnWhatsApp(Map<String, dynamic> event) async {
    final name = event["name"] ?? "Bolo Olla Gitana";
    final location = event["location"] ?? "";
    final notes = event["notes"] ?? "";
    final dateStr = event["event_date"] ?? "";
    final setlist = (event["setlist"] as List<dynamic>? ?? []);

    String formattedDate = dateStr;
    try {
      final dt = DateTime.parse(dateStr);
      formattedDate = DateFormat("EEEE, d 'de' MMMM 'de' yyyy - HH:mm'h'", "es_ES").format(dt);
    } catch (_) {}

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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: StageTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
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
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SizedBox(
                height: 600,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          existingEvent != null ? "Editar Evento" : "Nuevo Evento / Bolo",
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: StageTheme.amberGold,
                                    foregroundColor: Colors.black,
                                    radius: 14,
                                    child: Text("${idx + 1}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                  title: Text(song["title"] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(song["artist"] ?? ""),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.remove_circle, color: StageTheme.alertRed, size: 20),
                                    onPressed: () {
                                      setModalState(() {
                                        selectedSetlist.removeAt(idx);
                                      });
                                    },
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
                        child: Text(
                          existingEvent != null ? "Guardar Cambios" : "Crear Evento",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text("El nombre del evento es obligatorio")),
                            );
                            return;
                          }

                          if (existingEvent != null) {
                            await _api.updateEvent(
                              existingEvent["id"],
                              name: name,
                              eventDate: selectedDateTime.toIso8601String(),
                              location: locationCtrl.text.trim(),
                              notes: notesCtrl.text.trim(),
                              setlist: selectedSetlist,
                            );
                          } else {
                            await _api.createEvent(
                              name: name,
                              eventDate: selectedDateTime.toIso8601String(),
                              location: locationCtrl.text.trim(),
                              notes: notesCtrl.text.trim(),
                              setlist: selectedSetlist,
                            );
                          }

                          Navigator.pop(ctx);
                          _loadEvents();
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
    );
  }

  void _showSetlistSelectorDialog(
    BuildContext parentCtx,
    List<dynamic> repertoireSongs,
    List<Map<String, dynamic>> currentSetlist,
    Function(List<Map<String, dynamic>>) onUpdate,
  ) {
    final List<Map<String, dynamic>> tempSetlist = List.from(currentSetlist);

    showDialog(
      context: parentCtx,
      builder: (dlgCtx) {
        return StatefulBuilder(
          builder: (dlgCtx, setDlgState) {
            return AlertDialog(
              backgroundColor: StageTheme.surface,
              title: const Text("Añadir Temas al Setlist", style: TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: repertoireSongs.isEmpty
                    ? const Center(child: Text("No hay canciones disponibles en el repertorio todavía."))
                    : ListView.builder(
                        itemCount: repertoireSongs.length,
                        itemBuilder: (context, index) {
                          final song = repertoireSongs[index];
                          final songId = song["id"];
                          final isSelected = tempSetlist.any((s) => s["id"] == songId);

                          return CheckboxListTile(
                            activeColor: StageTheme.flameOrange,
                            title: Text(song["title"] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(song["artist"] ?? ""),
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
        title: const Text("Eventos & Bolos"),
        actions: [
          ProfileAppBarButton(onProfileChanged: () => setState(() {})),
          IconButton(
            icon: const Icon(Icons.refresh, color: StageTheme.amberGold),
            tooltip: "Recargar eventos",
            onPressed: () => _loadEvents(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de Olla Gitana
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Image.asset(
                    "assets/images/band_hero.jpg",
                    height: 110,
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
                      "PRÓXIMOS EVENTOS & SETLISTS",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: StageTheme.flameOrange))
                : _events.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.event_available, size: 64, color: StageTheme.amberGold),
                              const SizedBox(height: 16),
                              const Text(
                                "No hay eventos programados",
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                "Crea un nuevo bolo o ensayo con fecha, lugar y setlist para llevar a Google Calendar y compartir por WhatsApp.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: StageTheme.textSecondary),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.add),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        itemCount: _events.length,
                        itemBuilder: (context, index) {
                          final event = _events[index];
                          final setlist = (event["setlist"] as List<dynamic>? ?? []);
                          final dateStr = event["event_date"] ?? "";

                          String displayDate = dateStr;
                          try {
                            final dt = DateTime.parse(dateStr);
                            displayDate = DateFormat("EEE, d MMM yyyy - HH:mm'h'", "es_ES").format(dt);
                          } catch (_) {}

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: StageTheme.surfaceElevated,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(Icons.celebration, color: StageTheme.flameOrange, size: 28),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              event["name"] ?? "Evento",
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                const Icon(Icons.calendar_today, size: 14, color: StageTheme.amberGold),
                                                const SizedBox(width: 6),
                                                Text(displayDate, style: const TextStyle(color: StageTheme.amberGold, fontSize: 13, fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                            if ((event["location"] ?? "").isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  const Icon(Icons.place, size: 14, color: StageTheme.textSecondary),
                                                  const SizedBox(width: 6),
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
                                        onSelected: (val) {
                                          if (val == "edit") {
                                            _showEventDialog(existingEvent: event);
                                          } else if (val == "delete") {
                                            _deleteEvent(event["id"]);
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(value: "edit", child: Text("Editar")),
                                          const PopupMenuItem(value: "delete", child: Text("Eliminar", style: TextStyle(color: StageTheme.alertRed))),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // Resumen de Setlist
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: StageTheme.surfaceElevated,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.playlist_play, color: StageTheme.amberGold, size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          "${setlist.length} canciones en el setlist",
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        const Spacer(),
                                        TextButton(
                                          onPressed: () => _showEventDialog(existingEvent: event),
                                          child: const Text("Ver temas", style: TextStyle(fontSize: 12, color: StageTheme.amberGold)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Botones de acción rápida: Google Calendar & WhatsApp
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.calendar_month, size: 18),
                                          label: const Text("Google Calendar", style: TextStyle(fontSize: 12)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: StageTheme.surfaceElevated,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              side: const BorderSide(color: StageTheme.amberGold),
                                            ),
                                          ),
                                          onPressed: () => _exportToGoogleCalendar(event),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.share, size: 18),
                                          label: const Text("WhatsApp", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: StageTheme.electricGreen,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Nuevo Evento", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () => _showEventDialog(),
      ),
    );
  }
}
