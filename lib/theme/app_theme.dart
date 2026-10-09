import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// HALO design tokens — dark UI, muted gold + purple accents.
// Established design language: no emojis anywhere in the UI, Lucide icons
// (lucide_icons_flutter) for every icon, Sora for headings/display, Inter
// for body text.

const Color bgPrimary = Color(0xFF0E0E18);
const Color bgSurface = Color(0xFF151522);
const Color bgSurface2 = Color(0xFF1C1C2E);
const Color bgSurface3 = Color(0xFF232336);
const Color accentGold = Color(0xFFD4A843);
const Color accentGoldDim = Color(0x1AD4A843);
const Color accentGoldBorder = Color(0x30D4A843);
const Color accentPurple = Color(0xFF7C5CBF);
const Color accentPurpleDim = Color(0x157C5CBF);
const Color textPrimary = Color(0xFFE8E8F0);
const Color textMuted = Color(0xFF72728A);
const Color textMuted2 = Color(0xFF44445A);
const Color colorRed = Color(0xFFD94F5C);
const Color colorRedDim = Color(0x15D94F5C);
const Color colorGreen = Color(0xFF3DBE7A);
const Color colorGreenDim = Color(0x153DBE7A);
const Color colorBlue = Color(0xFF3A7BD5);
const Color borderColor = Color(0xFF1E1E30);

const double cardRadius = 18;
const double buttonRadius = 14;
const double chipRadius = 50;

const double spacingPadding = 16;
const double spacingCardGap = 12;
const double spacingSmallGap = 8;

class AppTheme {
  static ThemeData get darkTheme {
    final textTheme = TextTheme(
      displayLarge:
          GoogleFonts.sora(color: textPrimary, fontWeight: FontWeight.w800),
      displayMedium:
          GoogleFonts.sora(color: textPrimary, fontWeight: FontWeight.w700),
      headlineLarge: GoogleFonts.sora(
          color: textPrimary, fontWeight: FontWeight.w700, fontSize: 26),
      headlineMedium: GoogleFonts.sora(
          color: textPrimary, fontWeight: FontWeight.w700, fontSize: 20),
      titleLarge: GoogleFonts.sora(
          color: textPrimary, fontWeight: FontWeight.w600, fontSize: 18),
      titleMedium: GoogleFonts.sora(
          color: textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
      bodyLarge: GoogleFonts.inter(color: textPrimary, fontSize: 15),
      bodyMedium: GoogleFonts.inter(color: textPrimary, fontSize: 14),
      bodySmall: GoogleFonts.inter(color: textMuted, fontSize: 12),
      labelLarge:
          GoogleFonts.inter(color: textPrimary, fontWeight: FontWeight.w600),
      labelSmall: GoogleFonts.inter(color: textMuted, fontSize: 12),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgPrimary,
      textTheme: textTheme,
      colorScheme: const ColorScheme.dark(
        primary: accentGold,
        secondary: accentPurple,
        surface: bgSurface,
        error: colorRed,
        onPrimary: bgPrimary,
        onSecondary: textPrimary,
        onSurface: textPrimary,
        onError: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgPrimary,
        elevation: 0,
        foregroundColor: textPrimary,
        titleTextStyle: GoogleFonts.sora(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: bgSurface2,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: borderColor),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentGold,
          foregroundColor: bgPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(buttonRadius)),
          textStyle:
              GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentGold,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSurface,
        labelStyle: GoogleFonts.inter(color: textMuted),
        hintStyle: GoogleFonts.inter(color: textMuted2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: accentGold, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bgSurface2,
        selectedColor: accentGoldDim,
        labelStyle: GoogleFonts.inter(color: textPrimary, fontSize: 13),
        side: const BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(chipRadius)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgSurface2,
        contentTextStyle: GoogleFonts.inter(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius)),
      ),
      dividerColor: borderColor,
      iconTheme: const IconThemeData(color: textPrimary),
    );
  }
}
