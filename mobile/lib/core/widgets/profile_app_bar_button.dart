import 'package:flutter/material.dart';
import '../network/api_client.dart';
import '../theme/stage_theme.dart';
import '../../features/settings/settings_screen.dart';
import 'member_selector_dialog.dart';

class ProfileAppBarButton extends StatelessWidget {
  final VoidCallback? onProfileChanged;

  const ProfileAppBarButton({super.key, this.onProfileChanged});

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _showProfileMenu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: StageTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: StageTheme.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.switch_account, color: StageTheme.amberGold),
              title: const Text("Cambiar músico activo", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(ApiClient().userName, style: const TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(ctx, "switch"),
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: StageTheme.flameOrange),
              title: const Text("Ajustes y servidor", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("URL del backend, token, actualizaciones", style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(ctx, "settings"),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!context.mounted || action == null) return;
    if (action == "switch") {
      final selected = await showMemberSelectorDialog(context);
      if (selected != null) {
        onProfileChanged?.call();
      }
    } else if (action == "settings") {
      _openSettings(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiClient();

    return ValueListenableBuilder<String>(
      valueListenable: api.userNameNotifier,
      builder: (context, currentUserName, _) {
        final isIdentified = api.isUserIdentified;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _showProfileMenu(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isIdentified ? StageTheme.amberGold.withValues(alpha: 0.18) : StageTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isIdentified ? StageTheme.amberGold : StageTheme.border,
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person,
                    size: 16,
                    color: isIdentified ? StageTheme.amberGold : StageTheme.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isIdentified ? currentUserName : "Elegir Músico",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isIdentified ? StageTheme.amberGold : StageTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: isIdentified ? StageTheme.amberGold : StageTheme.textSecondary,
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
