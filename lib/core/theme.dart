import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PharmaColors {
  static const primary = Color(0xFF0E9F6E);
  static const teal = Color(0xFF1CB5A3);
  static const navy = Color(0xFF0F2A43);
  static const bg = Color(0xFFF4F9F7);

  static const gradientPrimary = LinearGradient(
    colors: [
      Color(0xFF0E9F6E),
      Color(0xFF1CB5A3),
      Color(0xFF0F2A43),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildPhamoryTheme() {
  final colorScheme = const ColorScheme(
    brightness: Brightness.light,
    primary: PharmaColors.primary,
    onPrimary: Colors.white,
    secondary: PharmaColors.navy,
    onSecondary: Colors.white,
    error: Color(0xFFE53935),
    onError: Colors.white,
    surface: Colors.white,
    onSurface: Color(0xFF1C1C1C),
    background: PharmaColors.bg,
    onBackground: Color(0xFF1C1C1C),
  );

  final textTheme = GoogleFonts.kanitTextTheme().copyWith(
    titleLarge: GoogleFonts.kanit(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: PharmaColors.navy,
    ),
    titleMedium: GoogleFonts.kanit(
      fontSize: 16,
      fontWeight: FontWeight.w500,
    ),
    bodyLarge: GoogleFonts.kanit(fontSize: 15),
    bodyMedium: GoogleFonts.kanit(fontSize: 14),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: PharmaColors.bg,
    textTheme: textTheme,

    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE5ECEF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE5ECEF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide:
            const BorderSide(color: PharmaColors.primary, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}