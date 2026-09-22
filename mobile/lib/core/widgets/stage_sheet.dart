import 'package:flutter/material.dart';
import '../theme/stage_theme.dart';

/// Muestra un panel inferior (bottom sheet) con SIEMPRE una forma clara de salir:
/// - Tirador de arrastre visible (showDragHandle)
/// - Botón X de cerrar
/// - Se puede cerrar tocando fuera
/// Los músicos nunca deben quedarse atrapados dentro de una opción.
Future<T?> showStageSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext ctx, ScrollController? scrollController) builder,
  bool isScrollControlled = true,
  bool expand = false,
  bool draggable = false,
  double initialChildSize = 0.6,
  double minChildSize = 0.35,
  double maxChildSize = 0.95,
  bool showCloseButton = true,
  String? title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: StageTheme.surface,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    isDismissible: true,
    enableDrag: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      Widget content;
      if (draggable) {
        content = DraggableScrollableSheet(
          initialChildSize: initialChildSize,
          minChildSize: minChildSize,
          maxChildSize: maxChildSize,
          expand: expand,
          builder: (_, scrollCtrl) => _SheetFrame(
            ctx: ctx,
            title: title,
            showCloseButton: showCloseButton,
            child: builder(ctx, scrollCtrl),
          ),
        );
      } else {
        content = _SheetFrame(
          ctx: ctx,
          title: title,
          showCloseButton: showCloseButton,
          child: builder(ctx, null),
        );
      }
      return content;
    },
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.ctx,
    required this.child,
    this.title,
    this.showCloseButton = true,
  });

  final BuildContext ctx;
  final Widget child;
  final String? title;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    // Sin título ni botón: el contenido se muestra tal cual (y se cierra con el tirador)
    if (title == null && !showCloseButton) return child;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title ?? "",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (showCloseButton)
                IconButton(
                  icon: const Icon(Icons.close, color: StageTheme.textSecondary),
                  tooltip: "Cerrar",
                  onPressed: () => Navigator.of(ctx).maybePop(),
                ),
            ],
          ),
        ),
        Flexible(child: child),
      ],
    );
  }
}
