import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colores fijos de la marca.
class Brand {
  Brand._();
  static const accent = Color(0xFF06B6D4);
  static const accent2 = Color(0xFF22D3EE);
  static const accentInk = Color(0xFF0E7490);
  static const onAccent = Color(0xFF062B31);
  static const gold = Color(0xFFC9A84C);
  static const purple = Color(0xFFC77DFF);
}

/// Tokens del MVP (index.html / dashboard.html): cambian con el tema claro u oscuro.
@immutable
class GgColors extends ThemeExtension<GgColors> {
  const GgColors({
    required this.bg, required this.bg2, required this.surface, required this.surface2, required this.surface3,
    required this.text, required this.text2, required this.text3, required this.border, required this.border2,
    required this.accentText, required this.accentSoft, required this.track,
    required this.crit, required this.high, required this.med, required this.low, required this.lime, required this.info,
  });

  final Color bg, bg2, surface, surface2, surface3, text, text2, text3, border, border2;
  final Color accentText, accentSoft, track;
  final Color crit, high, med, low, lime, info;

  static const dark = GgColors(
    bg: Color(0xFF070710), bg2: Color(0xFF0C0C16), surface: Color(0xFF14141F), surface2: Color(0xFF1B1B2A),
    surface3: Color(0xFF232335), text: Color(0xFFF0EEF8), text2: Color(0xFFA6A6BE), text3: Color(0xFF8A8AA6),
    border: Color(0xFF26263A), border2: Color(0xFF33334D), accentText: Brand.accent2,
    accentSoft: Color(0x2206B6D4), track: Color(0xFF2A2A40),
    crit: Color(0xFFFF2D55), high: Color(0xFFE05A5A), med: Color(0xFFF4A261), low: Color(0xFF50C878),
    lime: Color(0xFF9ACD32), info: Color(0xFF4A9FD4),
  );

  static const light = GgColors(
    bg: Color(0xFFF4F6F9), bg2: Color(0xFFEEF1F5), surface: Color(0xFFFFFFFF), surface2: Color(0xFFF5F7FA),
    surface3: Color(0xFFEDF0F4), text: Color(0xFF0B1220), text2: Color(0xFF566072), text3: Color(0xFF667085),
    border: Color(0xFFE2E7EE), border2: Color(0xFFD2D9E3), accentText: Brand.accentInk,
    accentSoft: Color(0x1606B6D4), track: Color(0xFFE1E6EE),
    crit: Color(0xFFD61F45), high: Color(0xFFC94444), med: Color(0xFFC77422), low: Color(0xFF2E9E5B),
    lime: Color(0xFF6E9B1F), info: Color(0xFF3B82C4),
  );

  @override
  GgColors copyWith() => this;

  @override
  GgColors lerp(ThemeExtension<GgColors>? other, double t) {
    if (other is! GgColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return GgColors(
      bg: l(bg, other.bg), bg2: l(bg2, other.bg2), surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2), surface3: l(surface3, other.surface3), text: l(text, other.text),
      text2: l(text2, other.text2), text3: l(text3, other.text3), border: l(border, other.border),
      border2: l(border2, other.border2), accentText: l(accentText, other.accentText),
      accentSoft: l(accentSoft, other.accentSoft), track: l(track, other.track), crit: l(crit, other.crit),
      high: l(high, other.high), med: l(med, other.med), low: l(low, other.low), lime: l(lime, other.lime),
      info: l(info, other.info),
    );
  }
}

extension GgContext on BuildContext {
  GgColors get c => Theme.of(this).extension<GgColors>()!;
}

class AppTheme {
  AppTheme._();

  static ThemeData build(Brightness b) {
    final dark = b == Brightness.dark;
    final c = dark ? GgColors.dark : GgColors.light;
    final base = ThemeData(brightness: b, useMaterial3: true);
    final text = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: c.text, displayColor: c.text);
    OutlineInputBorder borde(Color col) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: col));
    return base.copyWith(
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme(
        brightness: b, primary: Brand.accent, onPrimary: Brand.onAccent, secondary: Brand.accent2,
        onSecondary: Brand.onAccent, error: c.crit, onError: Colors.white, surface: c.surface, onSurface: c.text,
      ),
      textTheme: text,
      extensions: [c],
      dividerColor: c.border,
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg2, foregroundColor: c.text, elevation: 0, scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent, centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.bg2, surfaceTintColor: Colors.transparent, indicatorColor: c.accentSoft, height: 66,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.text2)),
        iconTheme: WidgetStateProperty.resolveWith((s) =>
            IconThemeData(color: s.contains(WidgetState.selected) ? c.accentText : c.text2)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: borde(c.border2),
        enabledBorder: borde(c.border2),
        focusedBorder: borde(Brand.accent),
        labelStyle: TextStyle(color: c.text3, fontSize: 13),
        hintStyle: TextStyle(color: c.text3, fontSize: 13),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.surface, surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(backgroundColor: c.surface, surfaceTintColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(color: c.surface2, surfaceTintColor: Colors.transparent),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.accent : null),
        checkColor: const WidgetStatePropertyAll(Brand.onAccent),
        side: BorderSide(color: c.border2, width: 1.5),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surface3,
        contentTextStyle: TextStyle(color: c.text, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.border2)),
      ),
    );
  }

  static TextStyle mono(BuildContext context, {double size = 12, Color? color, FontWeight? weight}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, color: color ?? context.c.text, fontWeight: weight);
}
