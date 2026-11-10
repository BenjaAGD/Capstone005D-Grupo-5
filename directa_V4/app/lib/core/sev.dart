import 'package:flutter/material.dart';

import 'theme.dart';

/// Severidades del backend (siempre en minúscula y con tilde en "crítica").
const severidades = ['crítica', 'alta', 'media', 'baja'];

String quitarTildes(String t) {
  const a = 'áéíóúüñÁÉÍÓÚÜÑ', b = 'aeiouunAEIOUUN';
  final sb = StringBuffer();
  for (final ch in t.split('')) {
    final i = a.indexOf(ch);
    sb.write(i >= 0 ? b[i] : ch);
  }
  return sb.toString();
}

/// Misma regla que normSev() del index.html y _norm_sev() de main.py.
String normSev(Object? v) {
  final t = quitarTildes((v ?? '').toString().toLowerCase());
  if (t.contains('|')) return 'media';
  if (t.contains('crit')) return 'crítica';
  if (t.contains('alt')) return 'alta';
  if (t.contains('baj')) return 'baja';
  return 'media';
}

Color sevColor(BuildContext context, String sev) {
  final c = context.c;
  return switch (sev) {
    'crítica' => c.crit,
    'alta' => c.high,
    'baja' => c.low,
    _ => c.med,
  };
}

String sevLabel(String sev) => switch (sev) {
      'crítica' => 'Crítica',
      'alta' => 'Alta',
      'baja' => 'Baja',
      _ => 'Media',
    };

String sevPlural(String sev) => switch (sev) {
      'crítica' => 'Críticas',
      'alta' => 'Altas',
      'baja' => 'Bajas',
      _ => 'Medias',
    };

/// Bandas del puntaje (mismas del PDF y de scoreInfo() del index.html).
({Color color, String label}) scoreInfo(BuildContext context, num? s) {
  final c = context.c;
  final v = (s ?? 0).toDouble();
  if (v >= 90) return (color: c.low, label: 'Sin observaciones');
  if (v >= 75) return (color: c.lime, label: 'Menor atención');
  if (v >= 55) return (color: c.med, label: 'Requiere revisión');
  if (v >= 40) return (color: c.high, label: 'Observaciones serias');
  return (color: c.crit, label: 'Observaciones críticas');
}

/// Color de la banda que devuelve el backend del Dashboard ("ok", "leve", "revision", "serio", "critico").
Color bandaColor(BuildContext context, String? banda) {
  final c = context.c;
  return switch (banda) {
    'ok' => c.low,
    'leve' => c.lime,
    'revision' => c.med,
    'serio' => c.high,
    'critico' => c.crit,
    _ => c.border2,
  };
}
