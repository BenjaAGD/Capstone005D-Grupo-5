import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import 'ajustes_screen.dart';
import 'chat_screen.dart';
import 'dashboard_screen.dart';
import 'documentos_screen.dart';
import 'guia_screen.dart';
import 'indicadores_screen.dart';
import 'informe_screen.dart';
import 'inicio_screen.dart';
import 'mas_screen.dart';
import 'memoria_screen.dart';
import 'resultados_screen.dart';

/// Contenedor con desplazamiento y ancho máximo, para las pantallas de contenido.
class Pagina extends StatelessWidget {
  const Pagina({super.key, required this.child, this.onRefresh});
  final Widget child;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) {
    final scroll = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: child)),
    );
    return onRefresh == null ? scroll : RefreshIndicator(onRefresh: onRefresh!, child: scroll);
  }
}

const _dest = [
  ('Inicio', Icons.home_outlined, Icons.home),
  ('Documentos', Icons.description_outlined, Icons.description),
  ('Preguntar', Icons.chat_bubble_outline, Icons.chat_bubble),
  ('Resultados', Icons.insights_outlined, Icons.insights),
  ('Más', Icons.grid_view_outlined, Icons.grid_view_rounded),
];

const _secundarias = {
  'informe': 'Informe IA',
  'dashboard': 'Dashboard',
  'memoria': 'Memoria Anual',
  'indicadores': 'Indicadores',
  'guia': 'Guía de uso',
  'ajustes': 'Servidor y apariencia',
};

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final List<StreamSubscription> _subs = [];
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    _subs.add(st.toasts.listen((t) {
      if (!mounted) return;
      final sm = ScaffoldMessenger.of(context);
      sm.hideCurrentSnackBar();
      sm.showSnackBar(SnackBar(
        content: Text(t.msg, style: TextStyle(color: t.err ? context.c.crit : context.c.text)),
        duration: Duration(milliseconds: t.err ? 4500 : 2800),
      ));
    }));
    _subs.add(st.navRequests.listen(_abrir));
  }

  void _abrir(String id) {
    final titulo = _secundarias[id];
    if (titulo == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _Secundaria(id: id, titulo: titulo)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Widget _tab(int i, AppState st) => switch (i) {
        0 => Pagina(onRefresh: st.recargarTodo, child: const InicioScreen()),
        1 => Pagina(onRefresh: st.recargarTodo, child: const DocumentosScreen()),
        2 => const ChatScreen(),
        3 => Pagina(onRefresh: st.recargarTodo, child: const ResultadosScreen()),
        _ => const Pagina(child: MasScreen()),
      };

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c = context.c;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final nInf = st.itemsInforme.length;
    Widget icono(int i, bool on) {
      final ic = Icon(on ? _dest[i].$3 : _dest[i].$2);
      return i == 4 && nInf > 0 ? Badge(label: Text('$nInf'), backgroundColor: c.crit, textColor: Colors.white, child: ic) : ic;
    }

    final cuerpo = KeyedSubtree(key: ValueKey(st.tab), child: _tab(st.tab, st));
    return Scaffold(
      key: _navKey,
      appBar: const BarraDirecta(),
      body: wide
          ? Row(children: [
              NavigationRail(
                backgroundColor: c.bg2,
                selectedIndex: st.tab,
                onDestinationSelected: (i) => st.go(AppState.tabs[i]),
                labelType: NavigationRailLabelType.all,
                indicatorColor: c.accentSoft,
                destinations: [
                  for (var i = 0; i < _dest.length; i++)
                    NavigationRailDestination(icon: icono(i, false), selectedIcon: icono(i, true), label: Text(_dest[i].$1)),
                ],
              ),
              VerticalDivider(width: 1, color: c.border),
              Expanded(child: cuerpo),
            ])
          : cuerpo,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: st.tab,
              onDestinationSelected: (i) => st.go(AppState.tabs[i]),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (var i = 0; i < _dest.length; i++)
                  NavigationDestination(icon: icono(i, false), selectedIcon: icono(i, true), label: _dest[i].$1),
              ],
            ),
    );
  }
}

class _Secundaria extends StatelessWidget {
  const _Secundaria({required this.id, required this.titulo});
  final String id, titulo;
  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final Widget hijo = switch (id) {
      'informe' => const InformeScreen(),
      'dashboard' => const DashboardScreen(),
      'memoria' => const MemoriaScreen(),
      'indicadores' => const IndicadoresScreen(),
      'guia' => const GuiaScreen(),
      _ => const AjustesScreen(),
    };
    return Scaffold(
      appBar: BarraDirecta(titulo: titulo, mostrarDoc: id != 'guia' && id != 'ajustes'),
      body: Pagina(onRefresh: id == 'ajustes' || id == 'guia' ? null : st.recargarTodo, child: hijo),
    );
  }
}

/// Barra superior: marca, documento activo (selector) y tema.
class BarraDirecta extends StatelessWidget implements PreferredSizeWidget {
  const BarraDirecta({super.key, this.titulo, this.mostrarDoc = true});
  final String? titulo;
  final bool mostrarDoc;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c = context.c;
    final docs = st.documentos;
    return AppBar(
      toolbarHeight: 64,
      titleSpacing: titulo == null ? 14 : 0,
      title: Row(children: [
        if (titulo == null) ...[
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(9),
                gradient: const LinearGradient(colors: [Brand.accent2, Brand.accent], begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: const Icon(Icons.check_circle_outline, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(titulo ?? 'DIRECTA', style: TextStyle(fontSize: titulo == null ? 15 : 16, fontWeight: FontWeight.w700, letterSpacing: titulo == null ? 2.5 : 0)),
            if (mostrarDoc && docs.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Cambiar documento activo',
                initialValue: st.docActivo,
                onSelected: (id) async {
                  if (await st.cambiarDocumento(id)) st.toast('Documento activado');
                },
                itemBuilder: (_) => [
                  for (final d in docs)
                    PopupMenuItem(
                      value: '${d['id']}',
                      child: Text('${nombreDoc(d)}${estadosProcesando.contains(d['estado']) ? ' (procesando…)' : ''}', style: const TextStyle(fontSize: 13)),
                    ),
                ],
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.description_outlined, size: 13, color: c.text3),
                  const SizedBox(width: 4),
                  Flexible(child: Text(nombreDoc(st.docActivoMap).isEmpty ? 'Elegir documento' : nombreDoc(st.docActivoMap),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: c.text2))),
                  Icon(Icons.arrow_drop_down, size: 18, color: c.text3),
                ]),
              )
            else if (titulo == null)
              Text('GERENCIA GENERAL', style: TextStyle(fontSize: 9.5, letterSpacing: 1.2, color: c.text3)),
          ]),
        ),
      ]),
      actions: [
        IconButton(
          tooltip: 'Cambiar tema',
          onPressed: st.toggleTheme,
          icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 21),
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: c.border)),
    );
  }
}
