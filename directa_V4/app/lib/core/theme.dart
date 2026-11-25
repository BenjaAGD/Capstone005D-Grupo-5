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

/// Escala tipográfica única de la app (pensada para celular, 360–430 dp de ancho).
/// Las pantallas usan estos tamaños en vez de números sueltos.
class Fs {
  Fs._();
  static const double xxs = 10; // etiquetas mínimas de gráficos
  static const double xs = 11; // pills, leyendas, menú inferior
  static const double sm = 12; // texto secundario
  static const double md = 13; // texto de apoyo y etiquetas
  static const double body = 14; // cuerpo
  static const double lg = 15; // títulos de tarjeta
  static const double reading = 16; // lectura de documentos y memoria
  static const double xl = 18; // títulos de sección
  static const double xxl = 21; // título de página
  static const double display = 24; // cifras destacadas
  static const double hero = 28; // cifras grandes
  static const double giant = 44; // puntaje principal

  /// Interlineado de lectura cómoda.
  static const double alturaLectura = 1.55;
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
    // "Hielo": blanco con un toque celeste de la marca, para que tarjetas y botones no se pierdan.
    bg: Color(0xFFEAF2F8), bg2: Color(0xFFE2ECF4), surface: Color(0xFFF8FBFE), surface2: Color(0xFFF0F6FA),
    surface3: Color(0xFFE6EFF6), text: Color(0xFF0B1220), text2: Color(0xFF566072), text3: Color(0xFF667085),
    border: Color(0xFFCFE0EC), border2: Color(0xFFBDD3E3), accentText: Brand.accentInk,
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
    final text = GoogleFonts.interTextTheme(base.textTheme.copyWith(
      headlineSmall: const TextStyle(fontSize: Fs.display, fontWeight: FontWeight.w700, height: 1.2),
      titleLarge: const TextStyle(fontSize: Fs.xxl, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.25),
      titleMedium: const TextStyle(fontSize: Fs.lg, fontWeight: FontWeight.w700, height: 1.3),
      titleSmall: const TextStyle(fontSize: Fs.md, fontWeight: FontWeight.w600, height: 1.3),
      bodyLarge: const TextStyle(fontSize: Fs.reading, height: Fs.alturaLectura),
      bodyMedium: const TextStyle(fontSize: Fs.body, height: 1.45),
      bodySmall: const TextStyle(fontSize: Fs.sm, height: 1.4),
      labelLarge: const TextStyle(fontSize: Fs.body, fontWeight: FontWeight.w600),
      labelMedium: const TextStyle(fontSize: Fs.sm, fontWeight: FontWeight.w600),
      labelSmall: const TextStyle(fontSize: Fs.xs, fontWeight: FontWeight.w600),
    )).apply(bodyColor: c.text, displayColor: c.text);
    const botonMin = Size(48, 48);
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
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: Fs.xs, fontWeight: FontWeight.w600, color: c.text2)),
        iconTheme: WidgetStateProperty.resolveWith((s) =>
            IconThemeData(color: s.contains(WidgetState.selected) ? c.accentText : c.text2)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14), // campo de 48 dp
        border: borde(c.border2),
        enabledBorder: borde(c.border2),
        focusedBorder: borde(Brand.accent),
        labelStyle: TextStyle(color: c.text3, fontSize: Fs.md),
        hintStyle: TextStyle(color: c.text3, fontSize: Fs.md),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: botonMin)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: botonMin)),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: botonMin)),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
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

  /// Estilo de lectura (documentos, memoria, informe): cuerpo de 16 sp con interlineado ~1.5.
  static TextStyle lectura(BuildContext context, {Color? color}) =>
      Theme.of(context).textTheme.bodyLarge!.copyWith(color: color ?? context.c.text);

  static TextStyle mono(BuildContext context, {double size = Fs.sm, Color? color, FontWeight? weight}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, color: color ?? context.c.text, fontWeight: weight);
}
