import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/sev.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'ayudas.dart';

class ResultadosScreen extends StatefulWidget {
  const ResultadosScreen({super.key});
  @override
  State<ResultadosScreen> createState() => _ResultadosScreenState();
}

class _ResultadosScreenState extends State<ResultadosScreen> {
  String tab = 'consolidado';
  String filtroSev = 'todas';
  String filtroAgente = 'todos';
  String? _doc;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    if (_doc != st.docActivo) {
      _doc = st.docActivo;
      filtroSev = 'todas';
      filtroAgente = 'todos';
    }
    final res = st.analisis ?? {};
    final keys = res.keys.toList()..sort((a, b) => st.ordenAgente(a).compareTo(st.ordenAgente(b)));
    final doc = st.docActivoMap;
    final a = ayudas['resultados']!;

    if (keys.isEmpty) {
      final procesando = doc != null && estadosProcesando.contains(doc['estado']);
      return Column(children: [
        const PageHead(title: 'Resultados', subtitle: 'Aquí aparece el resumen consolidado de los agentes sobre el documento activo.'),
        AyudaTile(parrafos: a.p, pasos: a.pasos),
        const BackendAviso(),
        GgCard(
          child: EmptyState(
            icon: Icons.insights_outlined,
            loading: st.cargandoAnalisis,
            title: st.cargandoAnalisis ? 'Cargando análisis…' : procesando ? 'El documento se está procesando' : 'Sin resultados todavía',
            text: doc == null
                ? 'Sube un documento. El análisis se ejecuta automáticamente y los resultados aparecerán aquí.'
                : procesando
                    ? 'Los resultados aparecerán solos cuando termine el análisis.'
                    : 'Este documento no tiene análisis guardados. El análisis se hace una sola vez, al subir el archivo. Si falló, elimina el documento y vuelve a subirlo.',
            action: doc == null ? GgButton('Ir a Documentos', icon: Icons.upload_file, onTap: () => st.go('docs')) : null,
          ),
        ),
      ]);
    }

    final todas = <Map<String, dynamic>>[];
    for (final k in keys) {
      for (final s in listaDe(res[k], 'senales')) {
        todas.add({...s, 'severidad': normSev(s['severidad']), 'agente': k});
      }
    }
    final cont = st.conteoSeveridad(res);
    final g = st.scoreGlobal(res);
    final gi = scoreInfo(context, g.score);
    final faltan = st.agentes.where((x) => !res.containsKey(x.key)).toList();

    Widget cuerpo;
    switch (tab) {
      case 'senales':
        final conSenal = {for (final s in todas) s['agente'] as String}.toList();
        final filtradas = todas
            .where((s) => (filtroSev == 'todas' || s['severidad'] == filtroSev) && (filtroAgente == 'todos' || s['agente'] == filtroAgente))
            .toList()
          ..sort((x, y) {
            final d = severidades.indexOf(x['severidad']).compareTo(severidades.indexOf(y['severidad']));
            return d != 0 ? d : st.ordenAgente(x['agente']).compareTo(st.ordenAgente(y['agente']));
          });
        cuerpo = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            ChipBtn('Todas (${todas.length})', on: filtroSev == 'todas', onTap: () => setState(() => filtroSev = 'todas')),
            for (final s in severidades)
              ChipBtn('${sevPlural(s)} (${cont[s]})', on: filtroSev == s, onTap: () => setState(() => filtroSev = s)),
          ]),
          const SizedBox(height: 10),
          GgSelect<String>(
            label: 'Filtrar por agente',
            value: filtroAgente,
            items: [('todos', 'Todos los agentes'), for (final k in conSenal) (k, st.nombreAgente(k))],
            onChanged: (v) => setState(() => filtroAgente = v),
          ),
          const SizedBox(height: 12),
          if (filtradas.isEmpty) const EmptyState(icon: Icons.filter_alt_off, title: 'No hay señales con estos filtros.'),
          for (final s in filtradas)
            SigRow(
              color: sevColor(context, s['severidad']),
              title: '${s['titulo'] ?? ''}',
              body: '${s['descripcion'] ?? ''}',
              footer: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SevPill(s['severidad']),
                AgentBadge(st.badgeAgente(s['agente'])),
                Text(st.nombreAgente(s['agente']), style: TextStyle(fontSize: 11.5, color: c.text3)),
              ]),
            ),
        ]);
      case 'omisiones':
        final all = [for (final k in keys) for (final o in listaDe(res[k], 'omisiones')) {...o, 'agente': k}];
        cuerpo = Column(children: [
          if (all.isEmpty) const EmptyState(icon: Icons.check, title: 'No se registraron omisiones.'),
          for (final o in all)
            SigRow(color: c.med, title: '${o['descripcion'] ?? o['titulo'] ?? ''}',
                footer: _quien(context, st, o['agente'])),
        ]);
      case 'preguntas':
        final all = [for (final k in keys) for (final p in listaDe(res[k], 'preguntas')) {...p, 'agente': k}];
        cuerpo = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (all.isEmpty) const EmptyState(icon: Icons.help_outline, title: 'No se registraron preguntas.'),
          if (all.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Son preguntas que el directorio podría hacer y que el documento no deja resueltas. Sirven para llegar preparado a la sesión; por eso no se envían al chat, que solo puede responder con lo que dice el documento.',
                  style: TextStyle(fontSize: 12.5, color: c.text2, height: 1.45)),
            ),
          for (final p in all)
            SigRow(color: c.info, title: '“${p['pregunta'] ?? ''}”', footer: _quien(context, st, p['agente'])),
        ]);
      case 'agentes':
        cuerpo = Column(children: [for (final k in keys) _TarjetaAgente(k: k, r: res[k]!)]);
      default:
        cuerpo = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (faltan.isNotEmpty)
            GgCard(
              borderColor: c.med,
              color: c.med.withValues(alpha: 0.08),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Faltan ${faltan.length} agente${faltan.length > 1 ? 's' : ''} por analizar: ${faltan.map((x) => x.name).join(', ')}.',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 3),
                Text('No se pudieron analizar al subir el archivo. El análisis no se repite solo. El puntaje global solo considera los agentes que tienen resultado.',
                    style: TextStyle(fontSize: 12, color: c.text2)),
              ]),
            ),
          GgCard(
            color: c.surface2,
            child: MarkdownLite('**¿Qué significa el Score?** Índice 0-100 por agente. **90-100** sin observaciones · **75-89** menor atención · **55-74** requiere revisión · **40-54** observaciones serias · **0-39** críticas, no enviar aún. Con la configuración por defecto se calcula a partir de las señales: cada crítica resta 30, alta 15, media 6 y baja 2.',
                size: 12.5),
          ),
          const SecTitle('Agentes con resultado'),
          for (final k in keys)
            Builder(builder: (context) {
              final si = scoreInfo(context, scoreDe(res[k]));
              return SigRow(
                color: si.color,
                title: st.nombreAgente(k),
                footer: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  MarkdownLite('${res[k]!['resumen_ejecutivo'] ?? 'Sin resumen ejecutivo.'}', size: 12.5, color: c.text2),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    AgentBadge(st.badgeAgente(k)),
                    Pill('Score ${scoreDe(res[k])}', fg: si.color),
                    Text(si.label, style: TextStyle(fontSize: 11, color: si.color)),
                  ]),
                ]),
              );
            }),
        ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead(
        title: 'Resultados del análisis',
        subtitle: 'Resumen consolidado de los agentes sobre el documento activo${doc != null ? ': ${nombreDoc(doc)}' : ''}.',
        actions: [
          GgButton('Agregar al informe', icon: Icons.add, onTap: st.agregarTodoAlInforme),
          GgButton('Recargar', icon: Icons.refresh, ghost: true, onTap: () async {
            if (st.docActivo == null) return;
            await st.cargarAnalisis(st.docActivo!);
            st.toast('Análisis recargados');
          }),
        ],
      ),
      AyudaTile(parrafos: a.p, pasos: a.pasos),
      const BackendAviso(),
      GgCard(
        child: Row(children: [
          ScoreRing(value: g.score, color: gi.color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SecTitle('Preparación global', bottom: 4),
              Text(gi.label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: gi.color)),
              const SizedBox(height: 3),
              Text('Promedio de ${g.n} agente${g.n == 1 ? '' : 's'} con hallazgos${g.sinInfo > 0 ? ' (${g.sinInfo} sin información relevante no cuentan)' : ''}. Igual que en el PDF.',
                  style: TextStyle(fontSize: 12, color: c.text2, height: 1.45)),
            ]),
          ),
        ]),
      ),
      GridCols(cols: 4, minItemWidth: 150, children: [
        for (final s in severidades)
          KpiTile(value: '${cont[s]}', label: 'Señales ${sevPlural(s).toLowerCase()}', color: sevColor(context, s)),
      ]),
      const SizedBox(height: 14),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final t in [
            ('consolidado', 'Resumen consolidado'),
            ('senales', 'Señales (${todas.length})'),
            ('omisiones', 'Omisiones'),
            ('preguntas', 'Preguntas probables'),
            ('agentes', 'Por agente (${keys.length})'),
          ])
            Padding(padding: const EdgeInsets.only(right: 6), child: ChipBtn(t.$2, on: tab == t.$1, onTap: () => setState(() => tab = t.$1))),
        ]),
      ),
      const SizedBox(height: 14),
      cuerpo,
    ]);
  }

  Widget _quien(BuildContext context, AppState st, String k) => Row(children: [
        AgentBadge(st.badgeAgente(k)),
        const SizedBox(width: 6),
        Text(st.nombreAgente(k), style: TextStyle(fontSize: 11.5, color: context.c.text3)),
      ]);
}

class _TarjetaAgente extends StatelessWidget {
  const _TarjetaAgente({required this.k, required this.r});
  final String k;
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final si = scoreInfo(context, scoreDe(r));
    final sens = listaDe(r, 'senales');
    final enInforme = st.analisisEnInforme(k);
    Widget bloque(String titulo, List<Map<String, dynamic>> items, Widget Function(Map<String, dynamic>) f) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$titulo (${items.length})', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: c.text2)),
          const SizedBox(height: 6),
          for (final it in items) Padding(padding: const EdgeInsets.only(bottom: 8), child: f(it)),
        ]),
      );
    }

    return GgCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: AgentBadge(st.badgeAgente(k)),
          title: Text(st.nombreAgente(k), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Text('${si.label} · ${listaDe(r, 'hallazgos').length} hallaz. · ${sens.length} señales · ${listaDe(r, 'omisiones').length} omis.',
              style: TextStyle(fontSize: 11.5, color: si.color)),
          trailing: Text('${scoreDe(r)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: si.color)),
          children: [
            const SecTitle('Resumen', bottom: 4),
            MarkdownLite('${r['resumen_ejecutivo'] ?? '—'}', size: 13),
            bloque('Hallazgos', listaDe(r, 'hallazgos'), (h) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${h['titulo'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text('${h['descripcion'] ?? ''}', style: TextStyle(fontSize: 12.5, color: c.text2)),
                ])),
            bloque('Señales', sens, (s) {
              final sv = normSev(s['severidad']);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SevPill(sv),
                  Text('${s['titulo'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
                const SizedBox(height: 2),
                Text('${s['descripcion'] ?? ''}', style: TextStyle(fontSize: 12.5, color: c.text2)),
              ]);
            }),
            bloque('Omisiones', listaDe(r, 'omisiones'), (o) => Text('${o['descripcion'] ?? o['titulo'] ?? ''}', style: const TextStyle(fontSize: 12.5))),
            bloque('Preguntas probables del directorio (para preparar la sesión)', listaDe(r, 'preguntas'),
                (q) => Text('“${q['pregunta'] ?? ''}”', style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic))),
            bloque('Recomendaciones', listaDe(r, 'recomendaciones'), (x) => Text('${x['descripcion'] ?? x['titulo'] ?? ''}', style: const TextStyle(fontSize: 12.5))),
            const SizedBox(height: 12),
            GgButton(enInforme ? 'En el informe (quitar)' : 'Agregar al informe', icon: enInforme ? Icons.check : Icons.add, ghost: true, small: true,
                onTap: () => st.toggleAnalisisEnInforme(k)),
          ],
        ),
      ),
    );
  }
}
