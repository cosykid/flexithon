import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/report.dart';

/// Kerb design system, Google Maps edition — white surfaces, Google blue,
/// Roboto type, grey inks and hairlines straight from the Maps app. Tier
/// semantics (red/amber) stay, remapped to Google's red and amber so pins,
/// rings and badges keep their meaning. Purpose-built for one-handed
/// portrait use: generous touch targets, bottom-anchored actions,
/// sheet-first navigation.
abstract final class KerbColors {
  // Ink (text / dark chrome) — Google grey ramp
  static const ink900 = Color(0xFF202124);
  static const ink600 = Color(0xFF5F6368);
  static const ink300 = Color(0xFF9AA0A6);

  // Surfaces
  static const paper = Color(0xFFF8F9FA); // scaffold
  static const surface = Color(0xFFFFFFFF); // cards, sheets
  static const line = Color(0xFFDADCE0); // grey hairline

  // Brand (Google blue)
  static const brand700 = Color(0xFF1967D2);
  static const brand600 = Color(0xFF1A73E8);
  static const brand100 = Color(0xFFE8F0FE);

  // Tier semantics (Google red / amber)
  static const danger = Color(0xFFD93025); // substantiated
  static const dangerFill = Color(0xFFFCE8E6);
  static const warn = Color(0xFFB06000); // partial (text-safe amber)
  static const warnBright = Color(0xFFF9AB00); // partial (pins/rings)
  static const warnFill = Color(0xFFFEF7E0);

  // Status
  static const pending = Color(0xFF5F6368);
  static const pendingFill = Color(0xFFF1F3F4);

  static const frame = Color(0xFF202124); // desktop phone-frame backdrop
}

abstract final class KerbRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
}

abstract final class KerbShadows {
  static const soft = [
    BoxShadow(color: Color(0x2620212A), blurRadius: 10, offset: Offset(0, 2)),
  ];
  static const subtle = [
    BoxShadow(color: Color(0x1A202124), blurRadius: 6, offset: Offset(0, 1)),
  ];
}

/// Tier styling: colour is always paired with a distinct icon shape
/// (octagon vs triangle) so meaning never rides on colour alone.
abstract final class TierStyle {
  static Color color(ReportTier tier) => switch (tier) {
        ReportTier.substantiated => KerbColors.danger,
        ReportTier.partiallySubstantiated => KerbColors.warnBright,
        ReportTier.unsubstantiated => KerbColors.ink300,
      };

  static Color textColor(ReportTier tier) => switch (tier) {
        ReportTier.substantiated => KerbColors.danger,
        ReportTier.partiallySubstantiated => KerbColors.warn,
        ReportTier.unsubstantiated => KerbColors.ink600,
      };

  static Color fill(ReportTier tier) => switch (tier) {
        ReportTier.substantiated => KerbColors.dangerFill,
        ReportTier.partiallySubstantiated => KerbColors.warnFill,
        ReportTier.unsubstantiated => KerbColors.pendingFill,
      };

  static String label(ReportTier tier) => switch (tier) {
        ReportTier.substantiated => 'Substantiated',
        ReportTier.partiallySubstantiated => 'Partially substantiated',
        ReportTier.unsubstantiated => 'Unsubstantiated',
      };

  static String shortLabel(ReportTier tier) => switch (tier) {
        ReportTier.substantiated => 'Substantiated',
        ReportTier.partiallySubstantiated => 'Partial',
        ReportTier.unsubstantiated => 'Unverified',
      };

  static IconData icon(ReportTier tier) => switch (tier) {
        ReportTier.substantiated => Icons.report_rounded, // octagon
        ReportTier.partiallySubstantiated => Icons.warning_rounded, // triangle
        ReportTier.unsubstantiated => Icons.help_outline_rounded,
      };
}

TextStyle kerbDisplay({
  double size = 20,
  FontWeight weight = FontWeight.w600,
  Color color = KerbColors.ink900,
  double? height,
}) =>
    GoogleFonts.roboto(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: 0,
    );

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: KerbColors.brand600,
  ).copyWith(
    primary: KerbColors.brand600,
    onPrimary: Colors.white,
    primaryContainer: KerbColors.brand100,
    onPrimaryContainer: KerbColors.brand700,
    surface: KerbColors.surface,
    onSurface: KerbColors.ink900,
    onSurfaceVariant: KerbColors.ink600,
    outline: KerbColors.line,
    error: KerbColors.danger,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = GoogleFonts.robotoTextTheme(base.textTheme)
      .apply(bodyColor: KerbColors.ink900, displayColor: KerbColors.ink900)
      .copyWith(
        headlineSmall: kerbDisplay(size: 24),
        titleLarge: kerbDisplay(size: 20),
        titleMedium: kerbDisplay(size: 16),
        titleSmall: kerbDisplay(size: 14),
        bodyMedium: GoogleFonts.roboto(
          fontSize: 14.5,
          height: 1.45,
          color: KerbColors.ink900,
        ),
        bodySmall: GoogleFonts.roboto(
          fontSize: 12.5,
          height: 1.4,
          color: KerbColors.ink600,
        ),
        labelLarge: GoogleFonts.roboto(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      );

  // Google buttons are full pills.
  const buttonShape = StadiumBorder();

  return base.copyWith(
    scaffoldBackgroundColor: KerbColors.paper,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: KerbColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: KerbColors.ink900,
      titleTextStyle: kerbDisplay(size: 20, weight: FontWeight.w500),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: KerbColors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KerbRadius.md),
        side: const BorderSide(color: KerbColors.line),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: buttonShape,
        backgroundColor: KerbColors.brand600,
        foregroundColor: Colors.white,
        textStyle:
            GoogleFonts.roboto(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: buttonShape,
        side: const BorderSide(color: KerbColors.line),
        foregroundColor: KerbColors.brand600,
        backgroundColor: KerbColors.surface,
        textStyle:
            GoogleFonts.roboto(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KerbColors.pendingFill,
      hintStyle: GoogleFonts.roboto(fontSize: 14, color: KerbColors.ink600),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KerbRadius.lg),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KerbRadius.lg),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KerbRadius.lg),
        borderSide: const BorderSide(color: KerbColors.brand600, width: 2),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: KerbColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KerbRadius.lg)),
      ),
      showDragHandle: false,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: KerbColors.ink900,
      contentTextStyle: GoogleFonts.roboto(fontSize: 14, color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KerbRadius.sm),
      ),
    ),
    dividerTheme: const DividerThemeData(color: KerbColors.line, thickness: 1),
    popupMenuTheme: PopupMenuThemeData(
      color: KerbColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: const Color(0x33202124),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KerbRadius.md),
      ),
      textStyle: GoogleFonts.roboto(fontSize: 14, color: KerbColors.ink900),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: KerbColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: KerbColors.brand100,
      height: 64,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.roboto(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? KerbColors.brand700
              : KerbColors.ink600,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? KerbColors.brand700
              : KerbColors.ink600,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: KerbColors.brand600,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: const StadiumBorder(),
      extendedTextStyle:
          GoogleFonts.roboto(fontSize: 14, fontWeight: FontWeight.w500),
    ),
  );
}
