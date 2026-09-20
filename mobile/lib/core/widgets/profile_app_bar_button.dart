import 'package:flutter/material.dart';
import '../network/api_client.dart';
import '../theme/stage_theme.dart';
import 'member_selector_dialog.dart';

class ProfileAppBarButton extends StatefulWidget {
  final VoidCallback? onProfileChanged;

  const ProfileAppBarButton({super.key, this.onProfileChanged});

  @override
  State<ProfileAppBarButton> createState() => _ProfileAppBarButtonState();
}

class _ProfileAppBarButtonState extends State<ProfileAppBarButton> {
  final ApiClient _api = ApiClient();

  @override
  Widget build(BuildContext context) {
    final userName = _api.userName;
    final isIdentified = _api.isUserIdentified;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          final selected = await showMemberSelectorDialog(context);
          if (selected != null && mounted) {
            setState(() {});
            widget.onProfileChanged?.call();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isIdentified ? StageTheme.amberGold.withOpacity(0.18) : StageTheme.surfaceElevated,
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
                isIdentified ? userName : "Elegir Músico",
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
  }
}
