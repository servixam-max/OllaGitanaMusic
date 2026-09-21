import 'package:flutter/material.dart';

class StageTheme {
  // Paleta Stage Dark — optimizada para escenarios y salas oscuras
  static const Color background    = Color(0xFF080810);
  static const Color surface       = Color(0xFF12121E);
  static const Color surfaceElevated = Color(0xFF1C1C2E);
  static const Color border        = Color(0xFF2A2A40);
  static const Color borderLight   = Color(0xFF3A3A55);

  // Acentos vivos
  static const Color flameOrange   = Color(0xFFFF5722);
  static const Color amberGold     = Color(0xFFFFB703);
  static const Color electricGreen = Color(0xFF06D6A0);
  static const Color neonBlue      = Color(0xFF3B9EFF);
  static const Color alertRed      = Color(0xFFEF476F);
  static const Color purple        = Color(0xFFAB47BC);

  // Texto
  static const Color textPrimary   = Color(0xFFF2F2FF);
  static const Color textSecondary = Color(0xFFB0B0C8);
  static const Color textMuted     = Color(0xFF606078);

  // ─── Gradientes ─────────────────────────────────────────────────────────────

  static const LinearGradient flameGradient = LinearGradient(
    colors: [Color(0xFFFF5722), Color(0xFFFF8C00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFB703), Color(0xFFFF8C00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient greenGradient = LinearGradient(
    colors: [Color(0xFF06D6A0), Color(0xFF0099CC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0E0E1A), Color(0xFF080810)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1C1C2E), Color(0xFF16162A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ─── Sombras y decoraciones reutilizables ────────────────────────────────────

  static List<BoxShadow> get glowOrange => [
    BoxShadow(color: flameOrange.withValues(alpha: 0.35), blurRadius: 20, spreadRadius: 0),
  ];

  static List<BoxShadow> get glowGold => [
    BoxShadow(color: amberGold.withValues(alpha: 0.30), blurRadius: 16, spreadRadius: 0),
  ];

  static BoxDecoration cardDecoration({Color? borderColor, bool glow = false}) =>
    BoxDecoration(
      gradient: cardGradient,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor ?? border, width: 1),
      boxShadow: glow ? glowOrange : [
        BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2)),
      ],
    );

  // ─── Tema global ─────────────────────────────────────────────────────────────

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: flameOrange,
      colorScheme: const ColorScheme.dark(
        primary: flameOrange,
        secondary: amberGold,
        tertiary: electricGreen,
        surface: surface,
        error: alertRed,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: textPrimary,
        surfaceContainerHighest: surfaceElevated,
      ),
      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: textSecondary, size: 24),
        actionsIconTheme: IconThemeData(color: textSecondary, size: 24),
      ),
      // Tarjetas
      cardTheme: CardThemeData(
        color: surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      // Botones primarios
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: flameOrange,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
      ),
      // Botones outlined
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: amberGold,
          side: const BorderSide(color: amberGold, width: 1.5),
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      // TextButton
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: amberGold,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: flameOrange, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        hintStyle: const TextStyle(color: textMuted, fontSize: 14),
      ),
      // Slider
      sliderTheme: const SliderThemeData(
        activeTrackColor: flameOrange,
        inactiveTrackColor: border,
        thumbColor: amberGold,
        trackHeight: 4,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
      ),
      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: const TextStyle(color: textPrimary, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
      ),
      // Dialogs
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
        titleTextStyle: const TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
        contentTextStyle: const TextStyle(color: textSecondary, fontSize: 14, height: 1.5),
      ),
      // Bottom navigation
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: flameOrange.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(color: flameOrange, fontSize: 11, fontWeight: FontWeight.w700);
          }
          return const TextStyle(color: textMuted, fontSize: 11);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: flameOrange, size: 22);
          }
          return const IconThemeData(color: textMuted, size: 22);
        }),
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: surfaceElevated,
        selectedColor: flameOrange.withValues(alpha: 0.2),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 13),
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      // PopupMenu
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: textPrimary, fontSize: 14),
        ),
      ),
      // Divider
      dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
      // FAB
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: flameOrange,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: StadiumBorder(),
      ),
      // Bottom Sheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: border,
      ),
    );
  }
}
