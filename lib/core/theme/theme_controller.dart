import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

final ValueNotifier<ThemeMode> themeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.light);

/// Pembantu tipografi terpusat RestoKasir:
/// - Display (Bricolage Grotesque 600-800): judul, nama brand, nomor meja, dan nominal besar.
/// - Body (Figtree 400-800): teks biasa, tombol, dan form.
class AppFonts {
  static FontWeight _clampDisplayWeight(FontWeight weight) {
    if (weight.value < 600) return FontWeight.w600;
    if (weight.value > 800) return FontWeight.w800;
    return weight;
  }

  static FontWeight _clampBodyWeight(FontWeight weight) {
    if (weight.value < 400) return FontWeight.w400;
    if (weight.value > 800) return FontWeight.w800;
    return weight;
  }

  static TextStyle display({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.bricolageGrotesque(
      fontSize: fontSize,
      fontWeight: _clampDisplayWeight(fontWeight),
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle body({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.figtree(
      fontSize: fontSize,
      fontWeight: _clampBodyWeight(fontWeight),
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}

class AppColors {
  // Brand Palette Permanen RestoKasir: Oranye, Putih, Off-White, Abu Lembut, dan Dark Charcoal
  static const Color primary = Color(0xFFEA580C); // Oranye Utama RestoKasir
  static const Color primaryDark = Color(0xFFC2410C); // Oranye Gelap (Hover/Pressed)
  static const Color primaryLight = Color(0xFFF97316);
  static const Color primaryTint = Color(0xFFFFF7ED); // Tint Oranye Lembut
  static const Color primaryTintDark = Color(0xFFFFF7ED);

  // Aksen Pendukung Hangat & Netral
  static const Color yellow = Color(0xFFF59E0B);
  static const Color amber = Color(0xFFD97706);
  static const Color yellowText = Color(0xFF9A3412);
  static const Color yellowSoft = Color(0xFFFFF7ED);
  static const Color yellowSoftDark = Color(0xFFFFF7ED);

  // Semantic Status Colors
  static const Color statusPending = Color(0xFFD97706);
  static const Color statusCompleted = Color(0xFF15803D);
  static const Color statusCancelled = Color(0xFFDC2626);
  static const Color statusBlue = Color(0xFFD97706);

  // Permukaan Permanen Putih & Off-White + Aksen Gelap Elegan
  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFF8F7F4);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE6E2DC);
  static const Color lightText = Color(0xFF171614);
  static const Color lightMuted = Color(0xFF6B6862);

  // Alias kompatibilitas yang tetap mengarah ke tema terang permanen
  static const Color darkBg = lightBg;
  static const Color darkSurface = lightSurface;
  static const Color darkCard = lightCard;
  static const Color darkBorder = lightBorder;
  static const Color darkText = lightText;
  static const Color darkMuted = lightMuted;

  static Color bg(BuildContext context) => lightBg;
  static Color surface(BuildContext context) => lightSurface;
  static Color card(BuildContext context) => lightCard;
  static Color border(BuildContext context) => lightBorder;
  static Color text(BuildContext context) => lightText;
  static Color muted(BuildContext context) => lightMuted;
}

class ThemeController {
  /// Tema permanen: selalu terang (tidak bergantung preferensi sistem perangkat).
  static bool isDark(BuildContext context) => false;

  static ThemeData get lightTheme {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.amber,
      onSecondary: AppColors.lightText,
      surface: AppColors.lightCard,
      onSurface: AppColors.lightText,
      surfaceContainerHighest: AppColors.lightSurface,
      outline: AppColors.lightBorder,
    );

    final baseFigtree = GoogleFonts.figtreeTextTheme(
      ThemeData.light().textTheme,
    ).apply(
      bodyColor: AppColors.lightText,
      displayColor: AppColors.lightText,
    );

    final textTheme = baseFigtree.copyWith(
      displayLarge: AppFonts.display(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: AppColors.lightText,
        letterSpacing: -0.5,
      ),
      displayMedium: AppFonts.display(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: AppColors.lightText,
        letterSpacing: -0.4,
      ),
      displaySmall: AppFonts.display(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.lightText,
        letterSpacing: -0.3,
      ),
      headlineLarge: AppFonts.display(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: AppColors.lightText,
        letterSpacing: -0.3,
      ),
      headlineMedium: AppFonts.display(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.lightText,
        letterSpacing: -0.2,
      ),
      headlineSmall: AppFonts.display(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.lightText,
      ),
      titleLarge: AppFonts.display(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.lightText,
      ),
      titleMedium: AppFonts.body(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.lightText,
      ),
      titleSmall: AppFonts.body(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.lightText,
      ),
      bodyLarge: AppFonts.body(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.lightText,
      ),
      bodyMedium: AppFonts.body(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.lightText,
      ),
      bodySmall: AppFonts.body(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.lightMuted,
      ),
      labelLarge: AppFonts.body(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.lightText,
      ),
      labelMedium: AppFonts.body(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.lightText,
      ),
      labelSmall: AppFonts.body(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.lightMuted,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightSurface,
      colorScheme: baseScheme,
      dividerColor: AppColors.lightBorder,
      fontFamily: GoogleFonts.figtree().fontFamily,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: AppColors.lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.lightBorder, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.lightCard,
        foregroundColor: AppColors.lightText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppFonts.display(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.lightText,
        ),
        shape: const Border(
          bottom: BorderSide(color: AppColors.lightBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        titleTextStyle: AppFonts.display(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.lightText,
        ),
        contentTextStyle: AppFonts.body(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.lightText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: AppFonts.body(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: AppFonts.body(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.lightText,
          side: const BorderSide(color: AppColors.lightBorder),
          textStyle: AppFonts.body(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: AppFonts.body(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: AppFonts.body(
          color: AppColors.lightMuted,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: AppFonts.body(
          color: AppColors.lightMuted,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: AppFonts.body(
          color: AppColors.primary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        errorStyle: AppFonts.body(
          color: AppColors.statusCancelled,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
    );
  }
}
