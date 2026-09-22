import 'package:flutter/material.dart';
import '../network/api_client.dart';
import '../theme/stage_theme.dart';

Future<String?> showMemberSelectorDialog(
  BuildContext context, {
  bool barrierDismissible = true,
}) async {
  return showDialog<String>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => const _MemberSelectorDialog(),
  );
}

class _MemberSelectorDialog extends StatefulWidget {
  const _MemberSelectorDialog();

  @override
  State<_MemberSelectorDialog> createState() => _MemberSelectorDialogState();
}

class _MemberSelectorDialogState extends State<_MemberSelectorDialog> {
  final ApiClient _api = ApiClient();
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;
  final TextEditingController _customNameController = TextEditingController();
  bool _isAddingCustom = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _customNameController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    final members = await _api.getBandMembers();
    if (mounted) {
      setState(() {
        _members = members;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectMember(String name) async {
    await _api.setUserName(name);
    if (mounted) {
      Navigator.pop(context, name);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: StageTheme.electricGreen,
          content: Text("¡Hola, $name! Perfil activo en Olla Gitana"),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _addAndSelectCustom() async {
    final name = _customNameController.text.trim();
    if (name.isEmpty) return;

    await _api.addBandMember(name);
    await _selectMember(name);
  }

  IconData _getRoleIcon(String role) {
    final r = role.toLowerCase();
    if (r.contains("voz") || r.contains("canto")) return Icons.mic;
    if (r.contains("guitar") || r.contains("bajo")) return Icons.graphic_eq;
    if (r.contains("bater") || r.contains("percu")) return Icons.album;
    if (r.contains("piano") || r.contains("tecla")) return Icons.piano;
    return Icons.person;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _api.userNameNotifier,
      builder: (context, current, _) {
        return AlertDialog(
          backgroundColor: StageTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: StageTheme.amberGold, width: 1.5),
          ),
          title: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.local_fire_department, color: StageTheme.flameOrange, size: 28),
                      SizedBox(width: 8),
                      Text(
                        "Olla Gitana",
                        style: TextStyle(
                          color: StageTheme.amberGold,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  // Siempre se puede salir del selector (importante: nadie debe quedar atrapado)
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: StageTheme.textSecondary, size: 20),
                      tooltip: "Cerrar",
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                "¿Quién eres en la banda?",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                "Tus votos, canciones y eventos se guardarán con tu nombre:",
                textAlign: TextAlign.center,
                style: TextStyle(color: StageTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(color: StageTheme.amberGold),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ..._members.map((m) {
                          final name = m["name"] as String? ?? "";
                          final role = m["role"] as String? ?? "Músico";
                          final isSelected = current == name;

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        child: Material(
                          color: isSelected ? StageTheme.amberGold.withValues(alpha: 0.18) : StageTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _selectMember(name),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? StageTheme.amberGold : StageTheme.border,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isSelected ? StageTheme.amberGold : StageTheme.surface,
                                    foregroundColor: isSelected ? Colors.black : StageTheme.amberGold,
                                    child: Icon(_getRoleIcon(role), size: 20),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: isSelected ? StageTheme.amberGold : Colors.white,
                                          ),
                                        ),
                                        Text(
                                          role,
                                          style: const TextStyle(
                                            color: StageTheme.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle, color: StageTheme.amberGold, size: 22),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 10),
                    if (!_isAddingCustom)
                      TextButton.icon(
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text("Otro músico / Añadir nombre"),
                        style: TextButton.styleFrom(foregroundColor: StageTheme.textSecondary),
                        onPressed: () => setState(() => _isAddingCustom = true),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _customNameController,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: "Tu nombre...",
                                  filled: true,
                                  fillColor: StageTheme.surfaceElevated,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                ),
                                onSubmitted: (_) => _addAndSelectCustom(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: StageTheme.flameOrange,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              onPressed: _addAndSelectCustom,
                              child: const Text("Listo"),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                ),
          ),
        );
      },
    );
  }
}
