import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/report.dart';

/// Kerb design system — named for the kerb cut, the quiet piece of design
/// that makes a street usable. Warm paper surfaces, deep petrol ink, a teal
/// brand, and tier semantics (red/amber) that carry through pins, rings and
/// badges. Purpose-built for one-handed portrait use: 56dp touch targets,
/// bottom-anchored actions, sheet-first navigation.
abstract final class KerbColors {
  // Ink (text / dark chrome)
  static const ink900 = Color(0xFF10222A);
  static const ink600 = Color(0xFF43606C);
  static const ink300 = Color(0xFF9BB0B8);

  // Surfaces
  static const paper = Color(0xFFF6F4EF); // scaffold
  static const surface = Color(0xFFFFFFFF); // cards, sheets
  static const line = Color(0xFFE8E3D8); // warm hairline

  // Brand (teal)
  static const brand700 = Color(0xFF0A5A4A);
  static const brand600 = Color(0xFF0C6B58);
  static const brand100 = Color(0xFFDCEFE9);

  // Tier semantics
  static const danger = Color(0xFFC6423F); // substantiated
  static const dangerFill = Color(0xFFFAE7E6);
  static const warn = Color(0xFFB97710); // partial (text-safe amber)
  static const warnBright = Color(0xFFE9A23B); // partial (pins/rings)
  static const warnFill = Color(0xFFFBEED7);

  // Status
  static const pending = Color(0xFF5B7C8A);
  static const pendingFill = Color(0xFFE4ECEF);

  static const frame = Color(0xFF0B1215); // desktop phone-frame backdrop
}

abstract final class KerbRadius {
  static const sm = 12.0;
  static const md = 18.0;
  static const lg = 28.0;
}

abstract final class KerbShadows {
  static const soft = [
    BoxShadow(color: Color(0x1410222A), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const subtle = [
    BoxShadow(color: Color(0x0F10222A), blurRadius: 12, offset: Offset(0, 4)),
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
  FontWeight weight = FontWeight.w700,
  Color color = KerbColors.ink900,
  double? height,
}) =>
    GoogleFonts.sora(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: -0.3,
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
  final text = GoogleFonts.interTextTheme(base.textTheme)
      .apply(bodyColor: KerbColors.ink900, displayColor: KerbColors.ink900)
      .copyWith(
        headlineSmall: kerbDisplay(size: 24),
        titleLarge: kerbDisplay(size: 20),
        titleMedium: kerbDisplay(size: 16, weight: FontWeight.w600),
        titleSmall: kerbDisplay(size: 14, weight: FontWeight.w600),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14.5,
          height: 1.45,
          color: KerbColors.ink900,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12.5,
          height: 1.4,
          color: KerbColors.ink600,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      );

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(KerbRadius.md),
  );

  return base.copyWith(
    scaffoldBackgroundColor: KerbColors.paper,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: KerbColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: KerbColors.ink900,
      titleTextStyle: kerbDisplay(size: 20),
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
        minimumSize: const Size(64, 56),
        shape: buttonShape,
        backgroundColor: KerbColors.brand600,
        foregroundColor: Colors.white,
        textStyle: kerbDisplay(size: 15, weight: FontWeight.w600, color: Colors.white),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: buttonShape,
        side: const BorderSide(color: KerbColors.line, width: 1.4),
        foregroundColor: KerbColors.ink900,
        backgroundColor: KerbColors.surface,
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KerbColors.surface,
      hintStyle: GoogleFonts.inter(fontSize: 14, color: KerbColors.ink300),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KerbRadius.md),
        borderSide: const BorderSide(color: KerbColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KerbRadius.md),
        borderSide: const BorderSide(color: KerbColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KerbRadius.md),
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
      contentTextStyle: GoogleFonts.inter(fontSize: 14, color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KerbRadius.sm),
      ),
    ),
    dividerTheme: const DividerThemeData(color: KerbColors.line, thickness: 1),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: KerbColors.brand600,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KerbRadius.md),
      ),
      extendedTextStyle: kerbDisplay(size: 15, weight: FontWeight.w600, color: Colors.white),
    ),
  );
}
