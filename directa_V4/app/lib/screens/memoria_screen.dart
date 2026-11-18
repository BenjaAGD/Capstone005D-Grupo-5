import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/saver.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/demo_offline.dart';
import 'memoria_extra.dart';

const estadosCap = [('pend', 'Pendiente'), ('curso', 'En redacción'), ('listo', 'Listo')];

/// Memoria Anual: mismo contenido que memoria.html (GET /api/memoria/cobertura, /sugerir y /pdf).
class MemoriaScreen extends StatefulWidget {
  const MemoriaScreen({super.key});
  @override
  State<MemoriaScreen> createState() => _MemoriaScreenState();
}

class _MemoriaScreenState extends State<MemoriaScreen> {
  String pestana = 'borrador';
  String fuente = '__todos__';
  Map<String, dynamic>? data;
  String? cap, error;
  bool cargando = false, soloMarcados = true, pdfCargando = false, sugiriendo = false;
  late Map<String, dynamic> mem;
  final Map<String, Map<String, dynamic>> sug = {};
  String sugMsg = 'Usa solo la evidencia ya encontrada: una consulta corta por capítulo.';
  final _notas = TextEditingController();
  Timer? _tNotas;
  String? _notasCap;

  AppState get st => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    mem = Map<String, dynamic>.from(st.store.getJson<Map>(Store.kMemoria, {'caps': {}}));
    mem['caps'] = Map<String, dynamic>.from(mem['caps'] as Map? ?? {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  @override
  void dispose() {
    _tNotas?.cancel();
    _notas.dispose();
    super.dispose();
  }

  Map<String, dynamic> capMem(String id) {
    final caps = mem['caps'] as Map<String, dynamic>;
    final m = Map<String, dynamic>.from(caps[id] as Map? ?? {'estado': 'pend', 'notas': '', 'revisados': {}});
    m['revisados'] = Map<String, dynamic>.from(m['revisados'] as Map? ?? {});
    caps[id] = m;
    return m;
  }

  void _save() => st.store.setJson(Store.kMemoria, mem);

  Future<void> _cargar({bool forzar = false}) async {
    if (st.documentos.isEmpty) {
      setState(() => data = null);
      return;
    }
    setState(() => cargando = true);
    try {
      final q = <String, String>{if (fuente != '__todos__') 'docs': fuente, if (forzar) 'refrescar': '1'};
      final r = await st.api.getJson('/api/memoria/cobertura', query: q.isEmpty ? null : q, timeout: const Duration(seconds: 8));
      if (r['ok'] != true) throw Exception(r['error'] ?? 'No se pudo leer la cobertura');
      data = Map<String, dynamic>.from(r);
      error = null;
      final caps = data!['capitulos'] as List;
      if (cap == null || !caps.any((c) => c['id'] == cap)) cap = '${caps.first['id']}';
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      data = null;
    }
    if (mounted) setState(() => cargando = false);
  }

  Future<void> _sugerir() async {
    final c0 = cap!;
    setState(() {
      sugiriendo = true;
      sugMsg = 'Preparando borrador…';
    });
    try {
      final r = await st.api.postJson('/api/memoria/sugerir', {'capitulo': c0, 'docs': fuente == '__todos__' ? '' : fuente});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Sin respuesta');
      sug[c0] = Map<String, dynamic>.from(r);
      sugMsg = r['cache'] == true ? 'Borrador listo (sin nueva consulta a la IA).' : 'Borrador listo.';
    } catch (e) {
      sugMsg = 'No se pudo sugerir: ${e.toString().replaceFirst('Exception: ', '')}';
    }
    if (mounted) setState(() => sugiriendo = false);
  }

  void _usarSug() {
    final r = sug[cap!];
    if (r == null) return;
    final m = capMem(cap!);
    final previo = '${m['notas'] ?? ''}'.trim();
    final pend = [for (final p in (r['pendientes'] as List? ?? const [])) '- ${p['dato']}${'${p['quien'] ?? ''}'.isNotEmpty ? ' (${p['quien']})' : ''}'].join('\n');
    m['notas'] = '${previo.isNotEmpty ? '$previo\n\n' : ''}${r['texto']}${pend.isNotEmpty ? '\n\nPor completar:\n$pend' : ''}';
    _notas.text = m['notas'];
    _save();
    setState(() {
      sug.remove(cap);
      sugMsg = 'Agregado a tus notas. Edítalo a tu gusto.';
    });
  }

  Future<void> _pdf() async {
    setState(() => pdfCargando = true);
    try {
      final b = await st.api.download('/api/memoria/pdf', json: {'docs': fuente, 'caps': mem['caps'], 'solo_marcados': soloMarcados});
      st.toast(await guardarArchivo('Esquema_Memoria_Anual.pdf', b, 'application/pdf'));
    } catch (e) {
      st.toast('No se pudo generar el PDF: $e', err: true);
    }
    if (mounted) setState(() => pdfCargando = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead(
        title: 'Memoria anual',
        subtitle: 'Prepara, completa y revisa el informe anual de tu organización.',
      ),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('¿Qué quieres hacer?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.c.text)),
          const SizedBox(height: 5),
          Text('La memoria reúne la gestión, los resultados y la información de la empresa durante el año. DIRECTA te ayuda a ordenar la evidencia y preparar un borrador revisable.',
              style: TextStyle(fontSize: 13, height: 1.45, color: context.c.text2)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.c.surface2,
              border: Border.all(color: context.c.border),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(children: [
              _opcionMemoria('borrador', Icons.auto_awesome_outlined, 'Crear memoria'),
              _opcionMemoria('capitulos', Icons.fact_check_outlined, 'Revisar avance'),
              _opcionMemoria('tono', Icons.tune_outlined, 'Personalizar estilo'),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      if (pestana == 'borrador') BorradorMemoria(caps: () => mem['caps'] as Map<String, dynamic>),
      if (pestana == 'tono') const PerfilTono(),
      if (pestana == 'capitulos') _capitulos(context, app),
    ]);
  }

  Widget _opcionMemoria(String id, IconData icono, String titulo) {
    final c = context.c;
    final activa = pestana == id;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: activa ? c.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() => pestana = id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icono, color: activa ? Brand.accent : c.text2, size: 18),
                const SizedBox(height: 4),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, height: 1.15, fontWeight: FontWeight.w700,
                      color: activa ? c.accentText : c.text2),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _capitulos(BuildContext context, AppState app) {
    final c = context.c;
    final hijos = <Widget>[
      Wrap(spacing: 8, runSpacing: 8, children: [
        GgButton('Descargar checklist de cobertura', icon: Icons.picture_as_pdf_outlined, ghost: true, small: true, loading: pdfCargando,
            onTap: data == null ? null : _pdf),
        GgButton('Actualizar datos', icon: Icons.refresh, ghost: true, small: true, onTap: () => _cargar(forzar: true)),
      ]),
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        value: soloMarcados,
        onChanged: (v) => setState(() => soloMarcados = v ?? true),
        title: Text('En el PDF, solo los temas que marqué como revisados', style: TextStyle(fontSize: 13, color: c.text2)),
      ),
      GgSelect<String>(
        label: 'Buscar evidencia en',
        value: fuente,
        items: [('__todos__', 'Todos los documentos'), for (final d in app.documentos) ('${d['id']}', nombreDoc(d))],
        onChanged: (v) {
          setState(() => fuente = v);
          _cargar();
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 16, color: c.text3),
          const SizedBox(width: 7),
          Expanded(child: Text(
            'La casilla marca que revisaste el tema. La evidencia se calcula aparte a partir de los documentos.',
            style: TextStyle(fontSize: 11.5, height: 1.35, color: c.text3),
          )),
        ]),
      ),
      const SizedBox(height: 12),
    ];

    if (app.documentos.isEmpty) {
      hijos.add(const DemoAviso(text: 'Ejemplo para revisar la estructura de capítulos y su avance. La cobertura real requiere documentos y conexión al servidor.'));
      hijos.add(GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Avance ilustrativo · NCG 461'),
        const DemoFila(titulo: '1 · Índice de contenidos', detalle: '2 de 2 temas con evidencia · muestra', icon: Icons.check_circle_outline),
        const DemoFila(titulo: '2 · Perfil de la entidad', detalle: '3 de 5 temas con evidencia · muestra', icon: Icons.timelapse),
        const DemoFila(titulo: '3 · Gobierno corporativo', detalle: 'Pendiente de revisión · muestra', icon: Icons.radio_button_unchecked),
        GgButton('Ir a Documentos', icon: Icons.upload_file, ghost: true, onTap: () => app.go('docs')),
      ])));
    } else if (!app.backendOk && data == null) {
      hijos.add(const BackendAviso());
    } else if (cargando && data == null) {
      hijos.add(const GgCard(child: EmptyState(icon: Icons.search, title: 'Buscando evidencia…', loading: true)));
    } else if (data == null) {
      hijos.add(GgCard(child: EmptyState(icon: Icons.error_outline, title: 'No se pudo leer la información', text: error)));
    } else {
      hijos.add(Opacity(opacity: cargando ? 0.55 : 1, child: _contenido(context)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: hijos);
  }

  Widget _contenido(BuildContext context) {
    final c = context.c;
    final d = data!;
    final r = d['resumen'] as Map;
    final caps = [for (final x in d['capitulos'] as List) Map<String, dynamic>.from(x as Map)];
    final listos = caps.where((x) => capMem('${x['id']}')['estado'] == 'listo').length;
    final actual = caps.firstWhere((x) => x['id'] == cap, orElse: () => caps.first);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(
        color: c.surface2,
        child: MarkdownLite('**Cómo leer esto.** ${d['aviso']} ${d['referencia']}', size: 12.3, color: c.text2),
      ),
      GridCols(cols: 4, minItemWidth: 150, children: [
        KpiTile(value: '$listos/${caps.length}', label: 'Capítulos listos'),
        KpiTile(value: '${r['fuertes']}/${r['temas_total']}', label: 'Temas con evidencia'),
        KpiTile(value: '${r['debiles']}', label: 'Con evidencia débil'),
        KpiTile(value: '${r['sin_evidencia']}', label: 'Sin evidencia'),
      ]),
      const SizedBox(height: 14),
      const SecTitle('Capítulos'),
      SizedBox(
        height: 118,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: caps.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final x = caps[i];
            final e = '${capMem('${x['id']}')['estado']}';
            final pct = (x['total_temas'] as num) == 0 ? 0.0 : (x['con_evidencia'] as num) / (x['total_temas'] as num);
            final sel = x['id'] == cap;
            return SizedBox(
              width: 220,
              child: Material(
                color: sel ? c.accentSoft : c.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: sel ? Brand.accent : c.border)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => cap = '${x['id']}'),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          width: 24, height: 24, alignment: Alignment.center,
                          decoration: BoxDecoration(color: sel ? Brand.accent : c.surface3, borderRadius: BorderRadius.circular(7)),
                          child: Text('${x['numero']}', style: AppTheme.mono(context, size: 12, weight: FontWeight.w700, color: sel ? Brand.onAccent : c.text2)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${x['titulo']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5))),
                      ]),
                      const Spacer(),
                      Text('${x['con_evidencia']} de ${x['total_temas']} temas con evidencia', style: TextStyle(fontSize: 11, color: c.text2)),
                      const SizedBox(height: 5),
                      Row(children: [
                        Expanded(child: GgBar(value: pct.toDouble(), color: c.lime, height: 6)),
                        const SizedBox(width: 8),
                        _estadoPill(context, e),
                      ]),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 14),
      _detalle(context, actual, caps.length, (d['fuentes'] as List).length == 1),
    ]);
  }

  Widget _estadoPill(BuildContext context, String e) {
    final c = context.c;
    final (col, txt) = switch (e) {
      'curso' => (c.med, 'En redacción'),
      'listo' => (c.low, 'Listo'),
      _ => (c.text2, 'Pendiente'),
    };
    return Pill(txt, fg: col, bg: e == 'pend' ? c.surface3 : null);
  }

  Widget _detalle(BuildContext context, Map<String, dynamic> x, int total, bool unico) {
    final c = context.c;
    final id = '${x['id']}';
    final m = capMem(id);
    if (_notasCap != id) {
      _notasCap = id;
      _notas.text = '${m['notas'] ?? ''}';
    }
    final temas = [for (final t in x['temas'] as List) Map<String, dynamic>.from(t as Map)];
    final agentes = [for (final a in x['agentes'] as List) Map<String, dynamic>.from(a as Map)];
    final s = sug[id];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SecTitle('Capítulo ${x['numero']} de $total', bottom: 2),
          Text('${x['titulo']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          GgSelect<String>(label: 'Estado del capítulo', value: '${m['estado']}', items: estadosCap, onChanged: (v) {
            setState(() => m['estado'] = v);
            _save();
          }),
          const SizedBox(height: 10),
          Text('${x['descripcion']}', style: TextStyle(fontSize: 12.8, color: c.text2)),
          const SizedBox(height: 12),
          const SecTitle('Temas que pide la norma'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 16, color: c.text3),
              const SizedBox(width: 7),
              Expanded(child: Text(
                'Marca cada casilla cuando hayas revisado ese tema. El nivel de evidencia se muestra por separado.',
                style: TextStyle(fontSize: 11.5, height: 1.35, color: c.text3),
              )),
            ]),
          ),
          for (var i = 0; i < temas.length; i++) _tema(context, temas[i], m, unico, i == temas.length - 1),
        ]),
      ),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Lo que dicen los agentes relacionados'),
          if (agentes.isEmpty) Text('Este capítulo no tiene un agente asociado.', style: TextStyle(color: c.text3)),
          for (final a in agentes)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${a['nombre']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Pill(a['analizado'] != true ? 'Sin analizar' : a['score'] != null ? 'Puntaje ${a['score']}' : '${(a['senales'] as List).length} señal${(a['senales'] as List).length == 1 ? '' : 'es'}',
                      fg: c.text2, bg: c.surface3),
                ]),
                const SizedBox(height: 4),
                if ((a['senales'] as List).isEmpty)
                  Text(a['analizado'] == true ? 'Sin señales para este tema.' : 'Este agente no tiene análisis guardado para los documentos elegidos.',
                      style: TextStyle(fontSize: 12.3, color: c.text3)),
                for (final sg in (a['senales'] as List).take(6))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SevPill('${sg['severidad']}'),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${sg['titulo']}${unico ? '' : ' · ${sg['doc']}'}', style: const TextStyle(fontSize: 12.5))),
                    ]),
                  ),
                if ((a['senales'] as List).length > 6)
                  Padding(padding: const EdgeInsets.only(top: 4),
                      child: Text('… y ${(a['senales'] as List).length - 6} más (ver el Dashboard)', style: TextStyle(fontSize: 12, color: c.text3))),
              ]),
            ),
        ]),
      ),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Notas de redacción'),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            GgButton('Sugerir borrador con IA', icon: Icons.auto_awesome, ghost: true, small: true, loading: sugiriendo, onTap: _sugerir),
            Text(sugMsg, style: TextStyle(fontSize: 12, color: c.text3)),
          ]),
          if (s != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10), border: Border.all(color: Brand.accent)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SecTitle('Borrador sugerido · revísalo antes de usarlo'),
                for (final p in '${s['texto']}'.split('\n\n'))
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(p, style: const TextStyle(fontSize: 13, height: 1.5))),
                if (s['verificacion'] is Map) _revisionCifras(context, s),
                if ((s['pendientes'] as List? ?? const []).isNotEmpty) ...[
                  const SecTitle('Por completar', bottom: 4),
                  for (final p in s['pendientes'] as List)
                    Text('• ${p['dato']}${'${p['quien'] ?? ''}'.isNotEmpty ? ' — ${p['quien']}' : ''}', style: const TextStyle(fontSize: 12.5)),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  GgButton('Usar en mis notas', small: true, onTap: _usarSug),
                  GgButton('Descartar', ghost: true, small: true, onTap: () => setState(() => sug.remove(id))),
                ]),
              ]),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _notas,
            minLines: 6,
            maxLines: 14,
            decoration: const InputDecoration(hintText: 'Escribe aquí el borrador, pendientes o a quién pedirle cada dato. Se guarda en este teléfono.'),
            onChanged: (v) {
              m['notas'] = v;
              _tNotas?.cancel();
              _tNotas = Timer(const Duration(milliseconds: 350), _save);
            },
          ),
        ]),
      ),
    ]);
  }

  Widget _tema(BuildContext context, Map<String, dynamic> t, Map<String, dynamic> m, bool unico, bool ultimo) {
    final c = context.c;
    final rev = m['revisados'] as Map<String, dynamic>;
    final (col, txt, ic) = switch ('${t['nivel']}') {
      'fuerte' => (c.low, 'Con evidencia', Icons.check),
      'debil' => (c.med, 'Evidencia débil', Icons.remove),
      _ => (c.text2, 'Sin evidencia', Icons.close),
    };
    final paginas = [for (final p in t['paginas'] as List) Map<String, dynamic>.from(p as Map)];
    final fr = t['fragmento'] as Map?;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(border: ultimo ? null : Border(bottom: BorderSide(color: c.border))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Tooltip(
          message: 'Marcar como revisado por mí',
          child: Checkbox(
            value: rev['${t['id']}'] == true,
            onChanged: (v) {
              setState(() => v == true ? rev['${t['id']}'] = true : rev.remove('${t['id']}'));
              _save();
            },
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${t['nombre']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (rev['${t['id']}'] == true ? c.low : c.text3).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(rev['${t['id']}'] == true ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                        size: 12, color: rev['${t['id']}'] == true ? c.low : c.text3),
                    const SizedBox(width: 4),
                    Text(rev['${t['id']}'] == true ? 'Revisado por mí' : 'Sin revisar',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600,
                            color: rev['${t['id']}'] == true ? c.low : c.text3)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: col.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(ic, size: 12, color: col),
                    const SizedBox(width: 4),
                    Text(txt, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: col)),
                  ]),
                ),
              ]),
              if (paginas.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final p in paginas) _pg(context, '${unico ? '' : '${p['doc']} · '}pág. ${p['pagina'] ?? '?'}'),
                  if ((t['n_paginas'] as num? ?? 0) > paginas.length) _pg(context, '+${(t['n_paginas'] as num) - paginas.length} más'),
                ]),
              ],
              if (fr != null)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('Ver fragmento', style: TextStyle(fontSize: 12.3, color: c.text3)),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: c.surface2, border: Border(left: BorderSide(color: Brand.accent, width: 3))),
                        child: Text('${fr['texto']}\n${fr['doc']} · pág. ${fr['pagina'] ?? '?'}', style: TextStyle(fontSize: 12.3, color: c.text2)),
                      ),
                    ],
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _revisionCifras(BuildContext context, Map<String, dynamic> s) {
    final c = context.c;
    final v = s['verificacion'] as Map;
    final estado = '${v['estado']}';
    final col = estado == 'cifras_ok' ? c.low : estado == 'con_reservas' ? c.med : c.text3;
    final otros = [for (final o in (s['otros_periodos'] as List? ?? const [])) if (o is Map) o];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(estado == 'cifras_ok' ? Icons.verified_outlined : Icons.rule, size: 15, color: col),
          const SizedBox(width: 5),
          Expanded(child: Text('${v['etiqueta']} · ${v['resumen']}', style: TextStyle(fontSize: 12, color: col))),
        ]),
        for (final o in otros)
          Text('• «${o['cifra']}» solo aparece en ${o['documento'] ?? 'un documento anterior'} (pág. ${o['pagina'] ?? '?'}).',
              style: TextStyle(fontSize: 11.8, color: c.med)),
        for (final a in (s['alertas'] as List? ?? const [])) Text('• $a', style: TextStyle(fontSize: 11.8, color: c.med)),
        if (s['tono'] is Map) Text('Escrito con el perfil de tono v${(s['tono'] as Map)['version']}.', style: TextStyle(fontSize: 11.5, color: c.text3)),
      ]),
    );
  }

  Widget _pg(BuildContext context, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: context.c.border2)),
        child: Text(t, style: AppTheme.mono(context, size: 11, color: context.c.text2)),
      );
}
