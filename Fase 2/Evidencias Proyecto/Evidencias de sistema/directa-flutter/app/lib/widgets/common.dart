import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/sev.dart';
import '../core/theme.dart';
import '../state/app_state.dart';

class GgCard extends StatelessWidget {
  const GgCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.borderColor,
    this.color, this.onTap, this.margin = const EdgeInsets.only(bottom: 12), this.gradient});
  final Widget child;
  final EdgeInsets padding, margin;
  final Color? borderColor, color;
  final VoidCallback? onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: margin,
      child: Material(
        color: gradient != null ? Colors.transparent : (color ?? c.surface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: borderColor ?? c.border)),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: gradient != null ? BoxDecoration(gradient: gradient, color: c.surface) : null,
          child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      ),
    );
  }
}

class SecTitle extends StatelessWidget {
  const SecTitle(this.text, {super.key, this.bottom = 10, this.color});
  final String text;
  final double bottom;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w600, color: color ?? context.c.text3)),
      );
}

class PageHead extends StatelessWidget {
  const PageHead({super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(fontSize: 13.5, color: context.c.text2, height: 1.4)),
          ],
          if (actions.isNotEmpty) ...[const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: actions)],
        ]),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.fg, this.bg, this.dot = false});
  final String text;
  final Color fg;
  final Color? bg;
  final bool dot;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg ?? fg.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 7, height: 7, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg, letterSpacing: 0.3))),
        ]),
      );
}

class SevPill extends StatelessWidget {
  const SevPill(this.sev, {super.key});
  final String sev;
  @override
  Widget build(BuildContext context) => Pill(sevLabel(sev).toUpperCase(), fg: sevColor(context, sev), dot: true);
}

class AgentBadge extends StatelessWidget {
  const AgentBadge(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      constraints: const BoxConstraints(minWidth: 36),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: c.surface3, borderRadius: BorderRadius.circular(6), border: Border.all(color: c.border2)),
      child: Text(text, textAlign: TextAlign.center, style: AppTheme.mono(context, size: 9.5, color: c.accentText, weight: FontWeight.w700)),
    );
  }
}

class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.value, required this.label, this.color, this.onTap, this.leading});
  final String value, label;
  final Color? color;
  final VoidCallback? onTap;
  final Widget? leading;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GgCard(
      margin: EdgeInsets.zero,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, height: 1, color: color ?? c.text)),
        const SizedBox(height: 6),
        Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: c.text2))),
        ]),
      ]),
    );
  }
}

/// Distribuye hijos en [cols] columnas (1 si no caben).
class GridCols extends StatelessWidget {
  const GridCols({super.key, required this.children, this.cols = 2, this.gap = 10, this.minItemWidth = 140});
  final List<Widget> children;
  final int cols;
  final double gap, minItemWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        var n = cols;
        while (n > 1 && (box.maxWidth - gap * (n - 1)) / n < minItemWidth) {
          n--;
        }
        final w = (box.maxWidth - gap * (n - 1)) / n;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}

class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.value, required this.color, this.caption = '/100', this.size = 92});
  final int value;
  final Color color;
  final String caption;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: Size(size, size), painter: _Ring(value / 100, color, c.surface3)),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$value', style: TextStyle(fontSize: size * 0.24, fontWeight: FontWeight.w700, height: 1.05)),
          Text(caption, style: TextStyle(fontSize: 10, color: c.text3, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.pct, this.color, this.track);
  final double pct;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 6;
    final ctr = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(ctr, r, p..color = track);
    if (pct > 0) {
      canvas.drawArc(Rect.fromCircle(center: ctr, radius: r), -math.pi / 2, 2 * math.pi * pct.clamp(0, 1), false, p..color = color);
    }
  }

  @override
  bool shouldRepaint(_Ring o) => o.pct != pct || o.color != color || o.track != track;
}

class GgBar extends StatelessWidget {
  const GgBar({super.key, required this.value, this.color, this.height = 8});
  final double value;
  final Color? color;
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Container(
          height: height,
          color: context.c.track,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(widthFactor: value.clamp(0.0, 1.0), child: Container(color: color ?? Brand.accent)),
        ),
      );
}

class GgButton extends StatelessWidget {
  const GgButton(this.label, {super.key, this.icon, this.onTap, this.ghost = false, this.small = false, this.expand = false,
    this.loading = false, this.danger = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool ghost, small, expand, loading, danger;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = danger ? c.crit : (ghost ? c.text : Brand.onAccent);
    return Opacity(
      opacity: onTap == null || loading ? 0.5 : 1,
      child: Material(
        color: ghost || danger ? c.surface2 : Brand.accent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10), side: ghost || danger ? BorderSide(color: c.border2) : BorderSide.none),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: loading ? null : onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: small ? 11 : 15, vertical: small ? 7 : 10),
            child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (loading)
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              else if (icon != null)
                Icon(icon, size: small ? 15 : 17, color: fg),
              if (loading || icon != null) const SizedBox(width: 7),
              Flexible(child: Text(label, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: small ? 12 : 13, fontWeight: FontWeight.w600, color: fg))),
            ]),
          ),
        ),
      ),
    );
  }
}

class ChipBtn extends StatelessWidget {
  const ChipBtn(this.label, {super.key, required this.on, required this.onTap, this.leading, this.maxWidth});
  final String label;
  final bool on;
  final VoidCallback onTap;
  final Widget? leading;
  final double? maxWidth;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: on ? c.accentSoft : c.surface2,
      shape: StadiumBorder(side: BorderSide(color: on ? Brand.accent : c.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? c.accentText : c.text2)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class KvRow extends StatelessWidget {
  const KvRow(this.k, this.v, {super.key, this.vColor, this.last = false});
  final String k, v;
  final Color? vColor;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.border))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(k, style: TextStyle(fontSize: 12.5, color: c.text3))),
        Expanded(child: Text(v, style: TextStyle(fontSize: 12.5, color: vColor ?? c.text))),
      ]),
    );
  }
}

/// Fila con barra de color a la izquierda (equivale a .sig-row del MVP).
class SigRow extends StatelessWidget {
  const SigRow({super.key, required this.color, required this.title, this.body, this.footer, this.onTap});
  final Color color;
  final String title;
  final String? body;
  final Widget? footer;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(children: [
            Positioned(
              left: 12, top: 12, bottom: 12,
              child: Container(width: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 11, 13, 11),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.35)),
                if (body != null && body!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(body!, style: TextStyle(fontSize: 12.3, color: c.text2, height: 1.45)),
                ],
                if (footer != null) ...[const SizedBox(height: 8), footer!],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.text, this.action, this.loading = false});
  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
      child: Column(children: [
        loading
            ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))
            : Icon(icon, size: 34, color: c.text3),
        const SizedBox(height: 10),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        if (text != null) ...[
          const SizedBox(height: 6),
          Text(text!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.8, color: c.text2, height: 1.45)),
        ],
        if (action != null) ...[const SizedBox(height: 12), action!],
      ]),
    );
  }
}

/// "¿Para qué sirve esta pantalla?" — misma ayuda del MVP, plegable.
class AyudaTile extends StatelessWidget {
  const AyudaTile({super.key, required this.parrafos, required this.pasos});
  final List<String> parrafos, pasos;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GgCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(Icons.help_outline, size: 20, color: c.accentText),
          title: const Text('¿Para qué sirve esta pantalla?', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in parrafos)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: MarkdownLite(p, size: 13)),
            const Text('Cómo usarla:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            for (var i = 0; i < pasos.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 20, child: Text('${i + 1}.', style: TextStyle(fontSize: 13, color: c.text2))),
                  Expanded(child: MarkdownLite(pasos[i], size: 13)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Aviso cuando no hay conexión con el backend.
class BackendAviso extends StatelessWidget {
  const BackendAviso({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    if (st.backendOk) return const SizedBox.shrink();
    final c = context.c;
    return GgCard(
      borderColor: c.crit,
      color: c.crit.withValues(alpha: 0.08),
      child: Row(children: [
        Icon(Icons.cloud_off, color: c.crit),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('No se pudo conectar con el backend', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Dirección usada: ${st.apiUrl}. Revisa que el servidor esté encendido o cámbiala en Más → Servidor.',
                style: TextStyle(fontSize: 12, color: c.text2)),
          ]),
        ),
        const SizedBox(width: 8),
        IconButton(tooltip: 'Reintentar', onPressed: st.recargarTodo, icon: const Icon(Icons.refresh)),
      ]),
    );
  }
}

/// Markdown mínimo, igual que renderMarkdownLigero() del MVP: párrafos, listas "-" y "1.", **negrita** y *cursiva*.
class MarkdownLite extends StatelessWidget {
  const MarkdownLite(this.texto, {super.key, this.size = 13.5, this.color});
  final String texto;
  final double size;
  final Color? color;

  List<InlineSpan> _inline(String t, TextStyle base) {
    final out = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|(?<![*\w])\*([^*\n]+?)\*(?!\*)|<b>(.+?)</b>|<i>(.+?)</i>');
    var i = 0;
    for (final m in re.allMatches(t)) {
      if (m.start > i) out.add(TextSpan(text: t.substring(i, m.start)));
      if (m.group(1) != null || m.group(3) != null) {
        out.add(TextSpan(text: m.group(1) ?? m.group(3), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else {
        out.add(TextSpan(text: m.group(2) ?? m.group(4), style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      i = m.end;
    }
    if (i < t.length) out.add(TextSpan(text: t.substring(i)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: size, height: 1.5, color: color ?? context.c.text);
    final bloques = <Widget>[];
    for (final linea in texto.split('\n')) {
      final t = linea.trim();
      if (t.isEmpty) continue;
      final ul = RegExp(r'^[-•*]\s+(.*)$').firstMatch(t);
      final ol = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(t);
      if (ul != null || ol != null) {
        bloques.add(Padding(
          padding: const EdgeInsets.only(bottom: 3, left: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: ol != null ? 22 : 14, child: Text(ol != null ? '${ol.group(1)}.' : '•', style: base)),
            Expanded(child: Text.rich(TextSpan(style: base, children: _inline(ul?.group(1) ?? ol!.group(2)!, base)))),
          ]),
        ));
      } else {
        bloques.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(TextSpan(style: base, children: _inline(t, base))),
        ));
      }
    }
    if (bloques.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: bloques);
  }
}

/// Selector simple con etiqueta (equivale a los <select> del MVP).
class GgSelect<T> extends StatelessWidget {
  const GgSelect({super.key, required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        initialValue: items.any((e) => e.$1 == value) ? value : items.first.$1,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        dropdownColor: context.c.surface2,
        style: TextStyle(fontSize: 13.5, color: context.c.text),
        items: [for (final (v, l) in items) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );
}

Future<bool> confirmar(BuildContext context, String texto, {String ok = 'Aceptar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

String formatTiempo(num seg) {
  final s = seg.round().clamp(0, 1 << 30);
  if (s < 60) return '$s seg';
  final m = s ~/ 60, r = s % 60;
  return r > 0 ? '$m min $r seg' : '$m min';
}
