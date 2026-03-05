// lib/theme/phamory_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';


class PharmaColors {
  static const darkBlue   = Color(0xFF0D47A1);  // Deep Blue
  static const primary    = Color(0xFF1976D2);  // Main Blue
  static const lightBlue  = Color(0xFFBBDEFB);  // Soft Background
  static const purple     = Color(0xFF7B61FF);  // Accent
  static const bg         = Color(0xFFF5F8FF);
  static const green = Color(0xFF0E9F6E);
  static const teal = Color(0xFF1CB5A3);
  static const navy = Color(0xFF0F2A43);
  static const bg2 = Color(0xFFF4F9F7);


  static const danger = Color(0xFFEF4444);
}


ThemeData buildPhamoryTheme() {
  // ✅ ใช้ fromSeed เพื่อให้ได้ ColorScheme ครบทุก field (กัน error ข้ามเวอร์ชัน)
  final baseScheme = ColorScheme.fromSeed(
    seedColor: PharmaColors.primary,
    brightness: Brightness.light,
    background: PharmaColors.bg,
  );


  // ✅ ปรับโทนให้ตรงแบรนด์ของคุณ
  final colorScheme = baseScheme.copyWith(
    primary: PharmaColors.primary,
    secondary: const Color.fromARGB(255, 20, 73, 123),
    tertiary: PharmaColors.teal,
    error: PharmaColors.danger,
    background: PharmaColors.bg,
  );


  // ✅ ฟอนต์หลักทั้งแอป (ยังคง Kanit) แต่หัวข้อ AppBar จะใช้ Sarabun ใน appBarTheme
  final baseText = GoogleFonts.kanitTextTheme();
  final textTheme = baseText.copyWith(
    titleLarge: GoogleFonts.kanit(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: PharmaColors.navy,
    ),
    titleMedium: GoogleFonts.kanit(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF111827),
    ),
    bodyLarge: GoogleFonts.kanit(
      fontSize: 15,
      height: 1.25,
      color: const Color(0xFF111827),
    ),
    bodyMedium: GoogleFonts.kanit(
      fontSize: 14,
      height: 1.25,
      color: const Color(0xFF111827),
    ),
    labelLarge: GoogleFonts.kanit(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
  );


  const radius = 22.0;


  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: PharmaColors.bg,
    textTheme: textTheme,


    // ===== AppBar =====
    // ✅ สีเดียว + ฟอนต์เรียบร้อยสำหรับคำว่า PharmaStock
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: Colors.white,
      backgroundColor: PharmaColors.primary,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.sarabun(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
    ),


    // ===== Cards =====
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8),
    ),


    // ===== Dialog =====
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),


    // ===== Inputs =====
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surface,
      hintStyle: textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
      labelStyle: textTheme.bodyMedium?.copyWith(
        color: const Color(0xFF374151),
        fontWeight: FontWeight.w600,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: PharmaColors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: PharmaColors.danger, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: PharmaColors.danger, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),


    // ===== Buttons =====
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PharmaColors.primary,
        foregroundColor: Colors.white,
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color.fromARGB(255, 35, 103, 167),
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),


    // ===== FAB =====
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: PharmaColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ),


    // ===== SnackBar =====
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color.fromARGB(69, 48, 104, 157),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),


    // ===== NavigationBar =====
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      height: 72,
      labelTextStyle: WidgetStatePropertyAll(
        textTheme.labelLarge?.copyWith(fontSize: 12),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected ? const Color.fromARGB(255, 23, 127, 139) : const Color(0xFF6B7280),
        );
      }),
      indicatorColor: PharmaColors.primary.withOpacity(0.14),
    ),
  );
}

