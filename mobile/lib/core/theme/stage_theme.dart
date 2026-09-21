import 'package:flutter/material.dart';

class StageTheme {
  // Paleta de colores optimizada para escenarios y salas oscuras (Stage Dark)
  static const Color background = Color(0xFF0C0C10);
  static const Color surface = Color(0xFF161622);
  static const Color surfaceElevated = Color(0xFF222234);
  static const Color border = Color(0xFF2D2D44);
  
  // Colores de acento vivos y de alto contraste
  static const Color flameOrange = Color(0xFFFF5722);
  static const Color amberGold = Color(0xFFFFB703);
  static const Color electricGreen = Color(0xFF06D6A0);
  static const Color neonBlue = Color(0xFF2196F3);
  static const Color alertRed = Color(0xFFEF476F);

  static const Color textPrimary = Color(0xFFF8F9FA);
  static const Color textSecondary = Color(0xFFB8B8CC);
  static const Color textMuted = Color(0xFF8A8AA3);

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: flameOrange,
      colorScheme: const ColorScheme.dark(
        primary: flameOrange,
        secondary: amberGold,
        surface: surface,
        error: alertRed,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: flameOrange, size: 28),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 4,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: flameOrange,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52), // Botones grandes y accesibles
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: flameOrange,
        inactiveTrackColor: border,
        thumbColor: amberGold,
        trackHeight: 6,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: flameOrange,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 12,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        unselectedLabelStyle: TextStyle(fontSize: 12),
      ),
    );
  }
}
