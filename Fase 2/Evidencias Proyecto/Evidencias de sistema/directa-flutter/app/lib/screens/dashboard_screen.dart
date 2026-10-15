import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/saver.dart';
import '../core/sev.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'ayudas.dart';

const estadosPlan = [('pendiente', 'Pendiente'), ('curso', 'En curso'), ('hecho', 'Hecha')];

/// Dashboard: mismo contenido que dashboard.html (GET /api/dashboard/{id} y comparación).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? data;
  bool cargando = false;
  String? error;
  String? _doc;
  String orden = 'puntaje';
  String? filtroSev;
  String filtroAg = '';
  bool ocultarTransv = false, verTodasSen = false, verTodasAcc = false;
  String accEstado = '', accAg = '';
  late Map<String, dynamic> acciones;
  String cmpId = '';
  Map<String, dynamic>? cmp;
  bool cmpCargando = false, pdfCargando = false, excelCargando = false, cmpPdfCargando = false;
  String? cmpError;
  final _kSenales = GlobalKey();

  AppState get st => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    acciones = Map<String, dynamic>.from(st.store.getJson<Map>(Store.kAcciones, {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final d = context.watch<AppState>().docActivo;
    if (d != _doc) {
      _doc = d;
      filtroSev = null;
      filtroAg = '';
      verTodasSen = false;
      if (d != null) WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
    }
  }

  Future<void> _cargar({bool forzar = false}) async {
    final id = _doc;
    if (id == null) return;
    setState(() {
      cargando = true;
      cmp = null;
      cmpId = '';
      cmpError = null;
    });
    try {
      final r = await st.api.getJson('/api/dashboard/${Uri.encodeComponent(id)}', query: forzar ? {'refrescar': '1'} : null);
      if (r['ok'] != true) throw Exception(r['error'] ?? 'No se pudo leer el dashboard');
      if (id != _doc) return;
      data = Map<String, dynamic>.from(r);
      error = null;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      data = null;
    }
    if (mounted) setState(() => cargando = false);
  }

  Map<String, dynamic> accDe(String id) =>
      Map<String, dynamic>.from(acciones[id] as Map? ?? {'estado': 'pendiente', 'responsable': '', 'fecha': ''});

  void _setAcc(String id, String campo, String valor) {
    final a = accDe(id)..[campo] = valor;
    acciones[id] = a;
    st.store.setJson(Store.kAcciones, acciones);
    setState(() {});
  }

  String _base() {
    final d = st.docActivoMap;
    final n = nombreDoc(d).replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll(RegExp(r'[^\w-]+'), '_');
    return n.isEmpty ? 'documento' : n;
  }

  Future<void> _descargar(String ruta, Object body, String nombre, String mime, void Function(bool) flag) async {
    setState(() => flag(true));
    try {
      final b = await st.api.download(ruta, json: body);
      st.toast(await guardarArchivo(nombre, b, mime));
    } catch (e) {
      st.toast('No se pudo generar el archivo: $e', err: true);
    }
    if (mounted) setState(() => flag(false));
  }

  Future<void> _comparar(String id) async {
    setState(() {
      cmpId = id;
      cmp = null;
      cmpError = null;
      cmpCargando = id.isNotEmpty;
    });
    if (id.isEmpty) return;
    try {
      final r = await st.api.getJson('/api/dashboard-comparar/${Uri.encodeComponent(id)}/${Uri.encodeComponent(_doc!)}');
      if (r['ok'] != true) throw Exception(r['error'] ?? 'No se pudo comparar');
      cmp = Map<String, dynamic>.from(r);
    } catch (e) {
      cmpError = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => cmpCargando = false);
  }

  void _irASenales() => WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _kSenales.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350));
      });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = context.watch<AppState>();
    final a = ayudas['dashboard']!;
    final head = PageHead(
      title: 'Dashboard',
      subtitle: 'Indicadores para el Gerente General calculados con el análisis que se hizo al subir cada documento.',
      actions: [
        GgButton('Descargar PDF', icon: Icons.picture_as_pdf_outlined, ghost: true, loading: pdfCargando,
            onTap: data == null
                ? null
                : () => _descargar('/api/dashboard/${Uri.encodeComponent(_doc!)}/pdf', {'acciones': acciones}, 'Dashboard_${_base()}.pdf',
                    'application/pdf', (v) => pdfCargando = v)),
        GgButton('Actualizar datos', icon: Icons.refresh, ghost: true, onTap: () => _cargar(forzar: true)),
      ],
    );
    final List<Widget> cuerpo;
    if (!app.backendOk && data == null) {
      cuerpo = [const BackendAviso()];
    } else if (app.documentos.isEmpty) {
      cuerpo = [const GgCard(child: EmptyState(icon: Icons.description_outlined, title: 'Todavía no hay documentos',
          text: 'Sube un documento en Documentos; el análisis se hace una sola vez al subirlo y aparecerá aquí.'))];
    } else if (cargando && data == null) {
      cuerpo = [const GgCard(child: EmptyState(icon: Icons.hourglass_empty, title: 'Cargando…', loading: true))];
    } else if (data == null) {
      cuerpo = [GgCard(child: EmptyState(icon: Icons.error_outline, title: 'No se pudo leer el documento', text: error))];
    } else if ((data!['resumen']['agentes_analizados'] as num? ?? 0) == 0) {
      cuerpo = [const GgCard(child: EmptyState(icon: Icons.insights_outlined, title: 'Este documento no tiene análisis guardado',
          text: 'El análisis se hace una sola vez, al subir el archivo. Si falló, bórralo y vuelve a subirlo.'))];
    } else {
      final d = data!;
      cuerpo = [
        Opacity(opacity: cargando ? 0.55 : 1, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _hero(context, d),
          _graficos(context, d),
          _semaforo(context, d),
          _senales(context, d),
          _plan(context, d),
          _comparar_(context, d),
        ])),
      ];
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      head,
      AyudaTile(parrafos: a.p, pasos: a.pasos),
      if (app.docActivoMap != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('Documento: ${nombreDoc(app.docActivoMap)}', style: TextStyle(fontSize: 12.5, color: c.text3)),
        ),
      ...cuerpo,
    ]);
  }

  // ------------------------------------------------------------------ piezas
  Widget _hero(BuildContext context, Map d) {
    final c = context.c;
    final r = d['resumen'] as Map;
    final g = (r['score_global'] as num?)?.toInt();
    final sen = Map<String, dynamic>.from(r['senales'] as Map);
    final bc = bandaColor(context, r['banda']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Preparación global'),
          Text.rich(TextSpan(children: [
            TextSpan(text: g?.toString() ?? '—', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w600, letterSpacing: -2, height: 1)),
            TextSpan(text: ' /100', style: TextStyle(fontSize: 15, color: c.text3)),
          ])),
          const SizedBox(height: 8),
          Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: bc, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text('${r['etiqueta']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            return Column(children: [
              Stack(clipBehavior: Clip.none, children: [
                GgBar(value: (g ?? 0) / 100, color: bc, height: 12),
                for (final m in [55, 75, 90]) Positioned(left: w * m / 100, top: -3, bottom: -3, child: Container(width: 1, color: c.border2)),
              ]),
              const SizedBox(height: 5),
              SizedBox(
                height: 14,
                child: Stack(children: [
                  for (final m in [0, 55, 75, 90, 100])
                    Positioned(
                      left: (w * m / 100 - (m == 0 ? 0 : m == 100 ? 22 : 9)).clamp(0, w - 22),
                      child: Text('$m', style: TextStyle(fontSize: 10.5, color: c.text3)),
                    ),
                ]),
              ),
            ]);
          }),
          const SizedBox(height: 8),
          Text('Promedio de ${r['agentes_con_info']} agentes con información relevante. Es el mismo cálculo del informe en PDF.',
              style: TextStyle(fontSize: 12, color: c.text3)),
        ]),
      ),
      GridCols(cols: 2, children: [
        for (final s in severidades)
          KpiTile(
            value: '${sen[s] ?? 0}',
            label: 'Señales ${sevPlural(s).toLowerCase()}',
            leading: Container(width: 9, height: 9, decoration: BoxDecoration(color: sevColor(context, s), shape: BoxShape.circle)),
            color: filtroSev == s ? sevColor(context, s) : null,
            onTap: () {
              setState(() {
                filtroSev = s;
                verTodasSen = false;
              });
              _irASenales();
            },
          ),
        KpiTile(value: '${r['agentes_analizados']}/${r['agentes_total']}', label: 'Agentes analizados'),
        KpiTile(value: '${r['omisiones']}', label: 'Omisiones'),
        KpiTile(value: '${r['preguntas']}', label: 'Preguntas probables'),
        KpiTile(value: '${r['recomendaciones']}', label: 'Recomendaciones'),
      ]),
      if ((r['senales_transversales'] as num? ?? 0) > 0)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: MarkdownLite('${r['senales_transversales']} de las ${r['senales_total']} señales son **transversales** (Riesgos y Estrategia cruzan hechos que otros agentes ya reportaron, por lo que pueden repetir un tema).',
              size: 12.3, color: c.text3),
        ),
      const SizedBox(height: 12),
    ]);
  }

  Widget _graficos(BuildContext context, Map d) {
    final c = context.c;
    final sen = Map<String, dynamic>.from((d['resumen'] as Map)['senales'] as Map);
    final tot = severidades.fold<int>(0, (s, k) => s + ((sen[k] as num?)?.toInt() ?? 0));
    final ags = [for (final a in d['agentes'] as List) if (a['con_info'] == true && a['score'] != null) a]
      ..sort((a, b) => (a['score'] as num).compareTo(b['score'] as num));
    return GridCols(cols: 2, minItemWidth: 300, children: [
      GgCard(
        margin: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Alertas por gravedad'),
          Row(children: [
            SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: _Donut([for (final k in severidades) ((sen[k] as num?)?.toDouble() ?? 0, sevColor(context, k))], c.border2),
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$tot', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  Text('alertas', style: TextStyle(fontSize: 10, color: c.text3)),
                ])),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final k in severidades)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: sevColor(context, k), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 8),
                      Text('${sevLabel(k)}: ', style: TextStyle(fontSize: 12.5, color: c.text2)),
                      Text('${sen[k] ?? 0}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ]),
            ),
          ]),
        ]),
      ),
      GgCard(
        margin: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Puntaje por área (0–100, más bajo = más atención)'),
          if (ags.isEmpty) Text('Aún no hay puntajes por área.', style: TextStyle(color: c.text3)),
          for (final a in ags)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 108, child: Text('${a['nombre']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.text2))),
                Expanded(child: GgBar(value: (a['score'] as num) / 100, color: bandaColor(context, a['banda']), height: 10)),
                SizedBox(width: 30, child: Text('${a['score']}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _semaforo(BuildContext context, Map d) {
    final c = context.c;
    final ags = [for (final a in d['agentes'] as List) Map<String, dynamic>.from(a as Map)];
    if (orden == 'puntaje') {
      ags.sort((a, b) {
        final x = ((a['score'] as num?) ?? 999).compareTo((b['score'] as num?) ?? 999);
        return x != 0 ? x : '${a['nombre']}'.compareTo('${b['nombre']}');
      });
    }
    int tot(Map a) => severidades.fold<int>(0, (s, k) => s + ((a['senales'][k] as num?)?.toInt() ?? 0));
    final maxTot = math.max(1, ags.fold<int>(0, (m, a) => math.max(m, tot(a))));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      const Text('Semáforo por agente', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text('Puntaje de cada agente y cuántas señales levantó, por severidad. Toca un agente para ver solo sus señales.',
          style: TextStyle(fontSize: 12.3, color: c.text2)),
      const SizedBox(height: 10),
      Wrap(spacing: 6, children: [
        ChipBtn('Menor puntaje primero', on: orden == 'puntaje', onTap: () => setState(() => orden = 'puntaje')),
        ChipBtn('Orden de análisis', on: orden == 'ola', onTap: () => setState(() => orden = 'ola')),
      ]),
      const SizedBox(height: 10),
      GgCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(children: [
          for (var i = 0; i < ags.length; i++)
            InkWell(
              onTap: () {
                setState(() {
                  filtroAg = '${ags[i]['key']}';
                  filtroSev = null;
                  verTodasSen = false;
                });
                _irASenales();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: i == ags.length - 1 ? null : Border(bottom: BorderSide(color: c.border))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('${ags[i]['nombre']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      if (ags[i]['transversal'] == true) Pill('transversal', fg: c.text3, bg: c.surface3),
                    ])),
                    Text('Omis. ${ags[i]['n_omisiones']} · Preg. ${ags[i]['n_preguntas']}', style: TextStyle(fontSize: 11, color: c.text3)),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    SizedBox(width: 30, child: Text(ags[i]['score'] != null && ags[i]['con_info'] == true ? '${ags[i]['score']}' : '—',
                        style: TextStyle(fontWeight: FontWeight.w700, color: ags[i]['con_info'] == true ? c.text : c.text3))),
                    if (ags[i]['score'] != null && ags[i]['con_info'] == true)
                      Expanded(child: GgBar(value: (ags[i]['score'] as num) / 100, color: bandaColor(context, ags[i]['banda'])))
                    else
                      const Spacer(),
                    const SizedBox(width: 8),
                    SizedBox(width: 130, child: Text('${ags[i]['etiqueta']}', style: TextStyle(fontSize: 11.5, color: c.text2))),
                  ]),
                  const SizedBox(height: 6),
                  if (tot(ags[i]) == 0)
                    Text('Sin señales', style: TextStyle(fontSize: 11.5, color: c.text3))
                  else
                    Row(children: [
                      Flexible(
                        child: FractionallySizedBox(
                          widthFactor: math.max(0.18, tot(ags[i]) / maxTot),
                          alignment: Alignment.centerLeft,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(height: 12, child: Row(children: [
                              for (final k in severidades)
                                if (((ags[i]['senales'][k] as num?) ?? 0) > 0)
                                  Expanded(flex: (ags[i]['senales'][k] as num).toInt(),
                                      child: Container(margin: const EdgeInsets.only(right: 2), color: sevColor(context, k))),
                            ])),
                          ),
                        ),
                      ),
                    ]),
                  if (tot(ags[i]) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        severidades.where((k) => ((ags[i]['senales'][k] as num?) ?? 0) > 0)
                            .map((k) => '${ags[i]['senales'][k]} ${(ags[i]['senales'][k] == 1 ? sevLabel(k) : sevPlural(k)).toLowerCase()}')
                            .join(' · '),
                        style: TextStyle(fontSize: 11.5, color: c.text2),
                      ),
                    ),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _senales(BuildContext context, Map d) {
    final c = context.c;
    final todas = [for (final s in d['senales'] as List) Map<String, dynamic>.from(s as Map)];
    final lista = todas
        .where((s) => (filtroSev == null || s['severidad'] == filtroSev) && (filtroAg.isEmpty || s['agente'] == filtroAg) && !(ocultarTransv && s['transversal'] == true))
        .toList();
    final vis = verTodasSen ? lista : lista.take(10).toList();
    final sen = (d['resumen'] as Map)['senales'] as Map;
    final agOps = [
      for (final a in d['agentes'] as List)
        if (severidades.any((k) => ((a['senales'][k] as num?) ?? 0) > 0)) ('${a['key']}', '${a['nombre']}')
    ];
    return Column(key: _kSenales, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      const Text('Señales', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text('Ordenadas por severidad; a igual severidad, primero las de los agentes especialistas.', style: TextStyle(fontSize: 12.3, color: c.text2)),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ChipBtn('Todas (${todas.length})', on: filtroSev == null, onTap: () => setState(() => filtroSev = null)),
        for (final k in severidades) ChipBtn('${sevLabel(k)} (${sen[k]})', on: filtroSev == k, onTap: () => setState(() => filtroSev = k)),
      ]),
      const SizedBox(height: 10),
      GgSelect<String>(label: 'Agente', value: filtroAg, items: [('', 'Todos'), ...agOps],
          onChanged: (v) => setState(() {
                filtroAg = v;
                verTodasSen = false;
              })),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: ocultarTransv,
        onChanged: (v) => setState(() => ocultarTransv = v),
        title: Text('Ocultar transversales', style: TextStyle(fontSize: 13, color: c.text2)),
      ),
      GgCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(children: [
          if (vis.isEmpty) const EmptyState(icon: Icons.filter_alt_off, title: 'No hay señales con estos filtros.'),
          for (var i = 0; i < vis.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: i == vis.length - 1 ? null : Border(bottom: BorderSide(color: c.border))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SevPill('${vis[i]['severidad']}'),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${vis[i]['titulo']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  if ('${vis[i]['descripcion'] ?? ''}'.isNotEmpty)
                    Text('${vis[i]['descripcion']}', style: TextStyle(fontSize: 12.5, color: c.text2)),
                  const SizedBox(height: 4),
                  Text('${vis[i]['agente_nombre']}${vis[i]['transversal'] == true ? ' · transversal' : ''}', style: TextStyle(fontSize: 11.5, color: c.text3)),
                ])),
              ]),
            ),
        ]),
      ),
      if (lista.length > 10)
        GgButton(verTodasSen ? 'Mostrar menos' : 'Mostrar las ${lista.length} señales', ghost: true, small: true,
            onTap: () => setState(() => verTodasSen = !verTodasSen)),
    ]);
  }

  Widget _plan(BuildContext context, Map d) {
    final c = context.c;
    final recs = [for (final r in d['recomendaciones'] as List) Map<String, dynamic>.from(r as Map)];
    if (recs.isEmpty) return const SizedBox.shrink();
    final n = recs.length;
    final hechas = recs.where((r) => accDe('${r['id']}')['estado'] == 'hecho').length;
    final curso = recs.where((r) => accDe('${r['id']}')['estado'] == 'curso').length;
    final pct = n > 0 ? (hechas / n * 100).round() : 0;
    final lista = recs.where((r) => (accEstado.isEmpty || accDe('${r['id']}')['estado'] == accEstado) && (accAg.isEmpty || r['agente'] == accAg)).toList();
    final vis = verTodasAcc ? lista : lista.take(12).toList();
    final agOps = <String, String>{for (final r in recs) '${r['agente']}': '${r['agente_nombre']}'};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      const Text('Plan de acción', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text('Las recomendaciones de los agentes convertidas en tareas. Asigna responsable y fecha, y marca el avance. Se guarda en este teléfono.',
          style: TextStyle(fontSize: 12.3, color: c.text2)),
      const SizedBox(height: 10),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GgBar(value: pct / 100, color: c.low, height: 10),
          const SizedBox(height: 6),
          Text('$hechas de $n hechas ($pct%) · $curso en curso', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          GgButton('Descargar Excel', icon: Icons.table_view_outlined, ghost: true, small: true, loading: excelCargando,
              onTap: () => _descargar('/api/dashboard/${Uri.encodeComponent(_doc!)}/excel', {'acciones': acciones}, 'Plan_de_accion.xlsx',
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', (v) => excelCargando = v)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ChipBtn('Todas', on: accEstado.isEmpty, onTap: () => setState(() => accEstado = '')),
            for (final (v, l) in estadosPlan) ChipBtn(l, on: accEstado == v, onTap: () => setState(() => accEstado = v)),
          ]),
          const SizedBox(height: 10),
          GgSelect<String>(label: 'Agente', value: accAg, items: [('', 'Todos'), for (final e in agOps.entries) (e.key, e.value)],
              onChanged: (v) => setState(() => accAg = v)),
          const SizedBox(height: 10),
          if (vis.isEmpty) const EmptyState(icon: Icons.filter_alt_off, title: 'No hay tareas con estos filtros.'),
          for (final r in vis) _Tarea(r: r, acc: accDe('${r['id']}'), onSet: (f, v) => _setAcc('${r['id']}', f, v)),
          if (lista.length > 12)
            GgButton(verTodasAcc ? 'Mostrar menos' : 'Mostrar las ${lista.length} tareas', ghost: true, small: true,
                onTap: () => setState(() => verTodasAcc = !verTodasAcc)),
        ]),
      ),
    ]);
  }

  Widget _comparar_(BuildContext context, Map d) {
    final c = context.c;
    final app = context.read<AppState>();
    final otros = app.documentos.where((x) => x['id'] != _doc && ((x['analisis_count'] as num?) ?? 0) > 0).toList();
    final hijos = <Widget>[
      const SizedBox(height: 18),
      const Text('Comparar con otro documento', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
    ];
    if (otros.isEmpty) {
      hijos.add(Text('Cuando tengas un segundo documento analizado (por ejemplo, el trimestre anterior) podrás ver aquí cómo cambió cada agente.',
          style: TextStyle(fontSize: 12.3, color: c.text2)));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: hijos);
    }
    hijos.addAll([
      Text('Elige el documento anterior; se compara contra el que estás viendo.', style: TextStyle(fontSize: 12.3, color: c.text2)),
      const SizedBox(height: 10),
      GgSelect<String>(label: 'Documento anterior', value: cmpId, items: [('', 'Elegir…'), for (final o in otros) ('${o['id']}', nombreDoc(o))],
          onChanged: _comparar),
      const SizedBox(height: 10),
    ]);
    if (cmpCargando) hijos.add(const GgCard(child: EmptyState(icon: Icons.compare_arrows, title: 'Comparando…', loading: true)));
    if (cmpError != null) hijos.add(GgCard(borderColor: c.crit, child: Text(cmpError!)));
    final x = cmp;
    if (x != null) {
      final g = x['global'] as Map;
      Widget delta(Object? v, {double size = 13}) {
        final n = (v as num?)?.toInt();
        if (n == null) return Text('—', style: TextStyle(color: c.text3, fontSize: size));
        if (n == 0) return Text('= 0', style: TextStyle(color: c.text3, fontWeight: FontWeight.w700, fontSize: size));
        return Text(n > 0 ? '▲ +$n' : '▼ $n', style: TextStyle(color: n > 0 ? c.low : c.crit, fontWeight: FontWeight.w700, fontSize: size));
      }

      Widget listaS(List l, String vacio) => l.isEmpty
          ? Padding(padding: const EdgeInsets.all(8), child: Text(vacio, style: TextStyle(color: c.text3)))
          : Column(children: [
              for (final s in l)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: SevPill('${s['severidad']}'),
                  title: Text('${s['titulo']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text('${s['agente_nombre']}${s['severidad_anterior'] != null && s['severidad_anterior'] != s['severidad'] ? ' · antes ${s['severidad_anterior']}' : ''}',
                      style: TextStyle(fontSize: 11.5, color: c.text3)),
                ),
            ]);
      hijos.add(GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Align(
            alignment: Alignment.centerRight,
            child: GgButton('Descargar comparación (PDF)', icon: Icons.picture_as_pdf_outlined, small: true, loading: cmpPdfCargando,
                onTap: () => _descargar('/api/dashboard-comparar/${Uri.encodeComponent(cmpId)}/${Uri.encodeComponent(_doc!)}/pdf', {},
                    'Comparacion_de_documentos.pdf', 'application/pdf', (v) => cmpPdfCargando = v)),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 18, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _bloqueCmp(context, 'Antes', g['a'], nombreDoc(x['a'] as Map?)),
            Text('→', style: TextStyle(fontSize: 24, color: c.text3)),
            _bloqueCmp(context, 'Ahora', g['b'], nombreDoc(x['b'] as Map?)),
            delta(g['delta'], size: 20),
          ]),
          const SizedBox(height: 14),
          for (final ag in x['agentes'] as List)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${ag['nombre']}${ag['transversal'] == true ? ' (transversal)' : ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  Text('${ag['score_a'] ?? '—'} → ${ag['score_b'] ?? '—'}  ', style: TextStyle(fontSize: 12, color: c.text2)),
                  delta(ag['delta']),
                ]),
                const SizedBox(height: 6),
                _Dumbbell(a: (ag['score_a'] as num?)?.toDouble(), b: (ag['score_b'] as num?)?.toDouble()),
                const SizedBox(height: 3),
                Text('Señales: ${ag['senales_a']} → ${ag['senales_b']}', style: TextStyle(fontSize: 11.5, color: c.text3)),
              ]),
            ),
          const SizedBox(height: 8),
          ExpansionTile(tilePadding: EdgeInsets.zero, initiallyExpanded: true, title: Text('Señales nuevas (${(x['nuevas'] as List).length})'),
              children: [listaS(x['nuevas'] as List, 'No aparecieron señales nuevas.')]),
          ExpansionTile(tilePadding: EdgeInsets.zero, title: Text('Señales resueltas (${(x['resueltas'] as List).length})'),
              children: [listaS(x['resueltas'] as List, 'No hay señales resueltas.')]),
          ExpansionTile(tilePadding: EdgeInsets.zero, title: Text('Señales que persisten (${(x['persisten'] as List).length})'),
              children: [listaS(x['persisten'] as List, 'Ninguna señal persiste.')]),
          Text('${x['nota'] ?? ''}', style: TextStyle(fontSize: 12, color: c.text3)),
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: hijos);
  }

  Widget _bloqueCmp(BuildContext context, String t, Object? v, String nombre) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SecTitle(t, bottom: 2),
        Text('${v ?? '—'}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150),
            child: Text(nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: context.c.text3))),
      ]);
}

class _Tarea extends StatelessWidget {
  const _Tarea({required this.r, required this.acc, required this.onSet});
  final Map<String, dynamic> r, acc;
  final void Function(String campo, String valor) onSet;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hecho = acc['estado'] == 'hecho';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${r['agente_nombre']}', style: TextStyle(fontSize: 11.5, color: c.accentText, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text('${r['texto']}', style: TextStyle(fontSize: 13, decoration: hecho ? TextDecoration.lineThrough : null, color: hecho ? c.text3 : c.text)),
        const SizedBox(height: 10),
        TextFormField(
          initialValue: '${acc['responsable'] ?? ''}',
          decoration: const InputDecoration(labelText: 'Responsable'),
          onChanged: (v) => onSet('responsable', v),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: c.text, side: BorderSide(color: c.border2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: () async {
                final ini = DateTime.tryParse('${acc['fecha'] ?? ''}') ?? DateTime.now();
                final f = await showDatePicker(context: context, initialDate: ini, firstDate: DateTime(2020), lastDate: DateTime(2035));
                if (f != null) onSet('fecha', f.toIso8601String().substring(0, 10));
              },
              icon: const Icon(Icons.event, size: 16),
              label: Text('${acc['fecha'] ?? ''}'.isEmpty ? 'Fecha límite' : '${acc['fecha']}', style: const TextStyle(fontSize: 12.5)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GgSelect<String>(label: 'Estado', value: '${acc['estado'] ?? 'pendiente'}', items: estadosPlan,
                onChanged: (v) => onSet('estado', v)),
          ),
        ]),
      ]),
    );
  }
}

class _Donut extends CustomPainter {
  _Donut(this.valores, this.vacio);
  final List<(double, Color)> valores;
  final Color vacio;
  @override
  void paint(Canvas canvas, Size size) {
    final tot = valores.fold<double>(0, (s, v) => s + v.$1);
    final r = size.width / 2 - 12;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20;
    if (tot == 0) {
      canvas.drawCircle(size.center(Offset.zero), r, p..color = vacio);
      return;
    }
    var ini = -math.pi / 2;
    for (final (v, col) in valores) {
      if (v <= 0) continue;
      final ang = 2 * math.pi * v / tot;
      canvas.drawArc(rect, ini, ang, false, p..color = col);
      ini += ang;
    }
  }

  @override
  bool shouldRepaint(_Donut o) => true;
}

class _Dumbbell extends StatelessWidget {
  const _Dumbbell({required this.a, required this.b});
  final double? a, b;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (a == null && b == null) return Text('Sin datos', style: TextStyle(fontSize: 11.5, color: c.text3));
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      double x(double v) => (w - 14) * v / 100;
      final lo = math.min(a ?? b!, b ?? a!), hi = math.max(a ?? b!, b ?? a!);
      return SizedBox(
        height: 16,
        child: Stack(children: [
          Positioned(left: 0, right: 0, top: 7, child: Container(height: 2, color: c.track)),
          if (a != null && b != null) Positioned(left: x(lo) + 7, width: x(hi) - x(lo), top: 6, child: Container(height: 4, color: c.text3.withValues(alpha: 0.6))),
          if (a != null) Positioned(left: x(a!), top: 1, child: _dot(c.text3, c.surface)),
          if (b != null) Positioned(left: x(b!), top: 1, child: _dot(Brand.accent, c.surface)),
        ]),
      );
    });
  }

  Widget _dot(Color col, Color borde) => Container(
        width: 14, height: 14,
        decoration: BoxDecoration(color: col, shape: BoxShape.circle, border: Border.all(color: borde, width: 2)),
      );
}
