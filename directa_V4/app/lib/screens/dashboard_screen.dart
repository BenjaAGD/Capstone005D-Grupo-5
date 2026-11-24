import 'dart:async';
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
import '../widgets/demo_offline.dart';

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
  int _tab = 0;
  bool _competencia = false;
  Map<String, dynamic>? cob;
  String orden = 'puntaje';
  String? filtroSev;
  String filtroAg = '';
  bool ocultarTransv = false, verTodasSen = false, verTodasAcc = false;
  String accEstado = '', accAg = '';
  late Map<String, dynamic> acciones;
  String cmpId = '';
  final _competidor = TextEditingController();
  Map<String, dynamic>? cmp;
  bool cmpCargando = false, pdfCargando = false, excelCargando = false, cmpPdfCargando = false;
  String? cmpError;
  final _kSenales = GlobalKey();

  AppState get st => context.read<AppState>();

  @override
  void dispose() {
    _competidor.dispose();
    super.dispose();
  }

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
      _tab = 0;
      _competencia = false;
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
      cob = null;
    });
    try {
      final r = await st.api.getJson('/api/dashboard/${Uri.encodeComponent(id)}', query: forzar ? {'refrescar': '1'} : null);
      if (r['ok'] != true) throw Exception(r['error'] ?? 'No se pudo leer el dashboard');
      if (id != _doc) return;
      data = Map<String, dynamic>.from(r);
      error = null;
      unawaited(_cargarCobertura(id));
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      data = null;
    }
    if (mounted) setState(() => cargando = false);
  }

  /// Cobertura NCG 461 del documento. Es un dato de apoyo: si falla, la tarjeta simplemente no aparece.
  Future<void> _cargarCobertura(String id) async {
    try {
      final r = await st.api.getJson('/api/memoria/cobertura', query: {'docs': id}, timeout: const Duration(seconds: 8));
      if (r['ok'] == true && mounted && id == _doc) setState(() => cob = Map<String, dynamic>.from(r));
    } catch (_) {}
  }

  Map<String, dynamic> accDe(String id) =>
      Map<String, dynamic>.from(acciones[id] as Map? ?? {'estado': 'pendiente', 'responsable': '', 'fecha': ''});

  void _guardarAccion(String id, Map<String, String> cambios) {
    final a = accDe(id)..addAll(cambios);
    acciones[id] = a;
    st.store.setJson(Store.kAcciones, acciones);
    st.toast('Cambios guardados en este teléfono');
    setState(() {});
  }

  Future<String?> _sugerirResponsable(Map<String, dynamic> recomendacion) async {
    try {
      final r = await st.api.postJson('/api/dashboard/${Uri.encodeComponent(_doc!)}/responsable',
          {'recomendacion_id': '${recomendacion['id']}'});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'No se pudo generar la sugerencia');
      return '${r['responsable_sugerido'] ?? ''}'.trim();
    } catch (e) {
      st.toast('No se pudo sugerir un responsable: $e', err: true);
      return null;
    }
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

  void _irASenales() {
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _kSenales.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350));
      });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = context.watch<AppState>();
    final head = PageHead(
      title: 'Dashboard ejecutivo',
      subtitle: 'Lectura rápida del análisis: nivel de preparación, señales y temas que requieren seguimiento.',
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
    if (app.docActivoMap == null) {
      cuerpo = [_demoDashboard(context)];
    } else if (!app.backendOk && data == null) {
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
          _pestanasDashboard(context),
          const SizedBox(height: 12),
          if (_tab == 0) ...[
            _hero(context, d),
            _queAtender(context, d),
            _kpis(context, d),
            _areas(context, d),
            _cobertura(context),
            _masDetalle(context, d),
          ]
          else if (_tab == 1) ...[_semaforo(context, d), _senales(context, d)]
          else if (_tab == 2) _plan(context, d)
          else _comparar_(context, d),
        ])),
      ];
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      head,
      if (app.docActivoMap != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('Documento: ${nombreDoc(app.docActivoMap)}', style: TextStyle(fontSize: 12.5, color: c.text3)),
        ),
      ...cuerpo,
    ]);
  }

  Widget _pestanasDashboard(BuildContext context) {
    final c = context.c;
    const tabs = ['Resumen', 'Señales', 'Plan de acción', 'Comparar'];
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (var i = 0; i < tabs.length; i++) ChipBtn(tabs[i], on: _tab == i, onTap: () => setState(() => _tab = i)),
    ]);
  }

  Widget _demoDashboard(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.insights_outlined, color: c.accentText), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Panel de análisis ejecutivo', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Cuando selecciones un documento analizado, este panel mostrará sus resultados y gráficos. Puedes explorar la estructura desde ahora.', style: TextStyle(fontSize: 12.5, height: 1.4, color: c.text2)),
        ])),
      ])),
      GridCols(cols: 2, children: const [
        DemoDato(valor: '—', titulo: 'Preparación global', detalle: 'Se calcula con los agentes'),
        DemoDato(valor: '—', titulo: 'Señales críticas y altas', detalle: 'Del documento analizado'),
        DemoDato(valor: '—', titulo: 'Omisiones', detalle: 'Temas no cubiertos'),
        DemoDato(valor: '—', titulo: 'Agentes con hallazgos', detalle: 'Resultados disponibles'),
      ]),
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Gráficos del análisis'),
        for (final x in [('Señales por gravedad', Icons.donut_large_outlined), ('Puntaje por área', Icons.bar_chart_outlined), ('Evolución entre documentos', Icons.show_chart_outlined)])
          Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [Icon(x.$2, color: c.accentText, size: 18), const SizedBox(width: 9), Expanded(child: Text(x.$1, style: TextStyle(color: c.text2))), Text('Sin datos', style: TextStyle(color: c.text3, fontSize: 11.5))])),
        const SizedBox(height: 4),
        Text('Los gráficos se completan con información de tus documentos, sin estimar cifras.', style: TextStyle(fontSize: 11.5, color: c.text3)),
      ])),
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Prioridades para la sesión'),
        Text('Las prioridades aparecerán al seleccionar un documento con análisis.', style: TextStyle(color: c.text2, fontSize: 12.5)),
      ])),
    ]);
  }

  // ------------------------------------------------------------------ piezas
  Widget _hero(BuildContext context, Map d) {
    final c = context.c;
    final r = d['resumen'] as Map;
    final g = (r['score_global'] as num?)?.toInt();
    final bc = bandaColor(context, r['banda']);
    return GgCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Preparación global'),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(g?.toString() ?? '—', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w600, letterSpacing: -2, height: 1)),
          const SizedBox(width: 4),
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('/100', style: TextStyle(fontSize: 15, color: c.text3))),
          const Spacer(),
          Flexible(child: Pill('${r['etiqueta']}', fg: bc, dot: true)),
        ]),
        const SizedBox(height: 16),
        _barraPreparacion(context, g),
        const SizedBox(height: 10),
        Text('Promedio de ${r['agentes_con_info']} agentes con información relevante. Es el mismo cálculo del informe en PDF.',
            style: TextStyle(fontSize: 12, color: c.text3)),
      ]),
    );
  }

  /// Barra por tramos (0–55, 55–75, 75–90, 90–100) con una marca en el puntaje actual.
  Widget _barraPreparacion(BuildContext context, int? g) {
    final c = context.c;
    const cortes = [0, 55, 75, 90, 100];
    final colores = [c.crit, c.med, c.lime, c.low];
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final x = (g ?? 0) / 100 * w;
      return Column(children: [
        SizedBox(
          height: 18,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                width: w,
                child: Row(children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      flex: cortes[i + 1] - cortes[i],
                      child: Container(margin: EdgeInsets.only(right: i < 3 ? 2 : 0), color: colores[i].withValues(alpha: 0.85)),
                    ),
                ]),
              ),
            ),
            if (g != null)
              Positioned(
                left: math.max(0.0, math.min(w - 4, x - 2)),
                child: Container(width: 4, height: 18, decoration: BoxDecoration(color: c.text, borderRadius: BorderRadius.circular(2))),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 14,
          child: Stack(children: [
            for (final m in cortes)
              Positioned(
                left: math.max(0.0, math.min(w - 22, w * m / 100 - (m == 0 ? 0 : (m == 100 ? 22 : 9)))),
                child: Text('$m', style: TextStyle(fontSize: 10.5, color: c.text3)),
              ),
          ]),
        ),
      ]);
    });
  }

  /// Las dos señales más graves, para saber por dónde empezar.
  Widget _queAtender(BuildContext context, Map d) {
    final c = context.c;
    final top = [
      for (final s in d['senales'] as List)
        if (s['severidad'] == 'crítica' || s['severidad'] == 'alta') Map<String, dynamic>.from(s as Map)
    ].take(2).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    return GgCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: SecTitle('Qué atender ahora', bottom: 0)),
          InkWell(
            onTap: _irASenales,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text('Ver señales', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.accentText)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        for (var i = 0; i < top.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SevPill('${top[i]['severidad']}'),
            const SizedBox(width: 10),
            Expanded(child: Text('${top[i]['titulo']}', style: const TextStyle(fontSize: 13, height: 1.35))),
          ]),
        ],
      ]),
    );
  }

  Widget _kpis(BuildContext context, Map d) {
    final c = context.c;
    final r = d['resumen'] as Map;
    final sen = Map<String, dynamic>.from(r['senales'] as Map);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GridCols(cols: 2, children: [
        KpiTile(value: '${r['agentes_analizados']}/${r['agentes_total']}', label: 'Agentes analizados',
            leading: Icon(Icons.groups_2_outlined, size: 17, color: c.accentText)),
        KpiTile(value: '${(sen['crítica'] as num? ?? 0) + (sen['alta'] as num? ?? 0)}', label: 'Señales críticas y altas',
            leading: Icon(Icons.warning_amber_rounded, size: 17, color: c.high), onTap: _irASenales),
      ]),
    );
  }

  /// Áreas de menor a mayor puntaje; tocar una lleva a sus señales.
  Widget _areas(BuildContext context, Map d) {
    final c = context.c;
    final todos = [for (final a in d['agentes'] as List) Map<String, dynamic>.from(a as Map)];
    bool conPuntaje(Map a) => a['con_info'] == true && a['score'] != null;
    final con = todos.where(conPuntaje).toList()..sort((a, b) => (a['score'] as num).compareTo(b['score'] as num));
    final sin = todos.where((a) => !conPuntaje(a)).toList();
    Widget fila(Map<String, dynamic> a, {required bool puntaje}) => InkWell(
          onTap: () {
            setState(() {
              filtroAg = '${a['key']}';
              filtroSev = null;
              verTodasSen = false;
            });
            _irASenales();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(width: 112, child: Text('${a['nombre']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: puntaje ? c.text : c.text3))),
              Expanded(
                child: puntaje
                    ? GgBar(value: (a['score'] as num) / 100, color: bandaColor(context, a['banda']), height: 8)
                    : GgBar(value: 0, height: 8),
              ),
              SizedBox(
                width: 62,
                child: Text(puntaje ? '${a['score']}' : 'Sin datos', textAlign: TextAlign.right,
                    style: TextStyle(fontSize: puntaje ? 13 : 11, fontWeight: puntaje ? FontWeight.w700 : FontWeight.w500,
                        color: puntaje ? c.text : c.text3)),
              ),
            ]),
          ),
        );
    return GgCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Áreas · de menor a mayor puntaje', bottom: 6),
        if (con.isEmpty && sin.isEmpty) Text('Aún no hay puntajes por área.', style: TextStyle(color: c.text3)),
        for (final a in con) fila(a, puntaje: true),
        for (final a in sin) fila(a, puntaje: false),
      ]),
    );
  }

  /// Cobertura de temas de la NCG 461 (viene de Memoria anual). Sin dato, no se muestra.
  Widget _cobertura(BuildContext context) {
    final c = context.c;
    final r = cob?['resumen'];
    if (r is! Map) return const SizedBox.shrink();
    final f = (r['fuertes'] as num?)?.toInt() ?? 0;
    final w = (r['debiles'] as num?)?.toInt() ?? 0;
    final s = (r['sin_evidencia'] as num?)?.toInt() ?? 0;
    final t = (r['temas_total'] as num?)?.toInt() ?? 0;
    if (t == 0) return const SizedBox.shrink();
    return GgCard(
      onTap: () => st.go('memoria'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: SecTitle('Cobertura NCG 461', bottom: 0)),
          Text('$f de $t temas', style: TextStyle(fontSize: 12, color: c.text2)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 10,
            child: Row(children: [
              if (f > 0) Expanded(flex: f, child: Container(margin: const EdgeInsets.only(right: 2), color: c.low)),
              if (w > 0) Expanded(flex: w, child: Container(margin: const EdgeInsets.only(right: 2), color: c.med)),
              if (s > 0) Expanded(flex: s, child: Container(color: c.crit)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text('Con evidencia $f · Débil $w · Sin evidencia $s', style: TextStyle(fontSize: 11.5, color: c.text3)),
      ]),
    );
  }

  Widget _masDetalle(BuildContext context, Map d) {
    final c = context.c;
    final r = d['resumen'] as Map;
    final transv = (r['senales_transversales'] as num? ?? 0) > 0;
    return GgCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          shape: const Border(),
          collapsedShape: const Border(),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: const Text('Más detalle', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text('Distribución por tramo y volumen detectado', style: TextStyle(fontSize: 11.5, color: c.text3)),
          children: [
            GridCols(cols: 2, children: [
              KpiTile(value: '${r['omisiones']}', label: 'Omisiones detectadas', leading: Icon(Icons.checklist_outlined, size: 17, color: c.accentText)),
              KpiTile(value: '${r['preguntas']}', label: 'Preguntas para la sesión', leading: Icon(Icons.help_outline, size: 17, color: c.accentText)),
            ]),
            if (transv)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: MarkdownLite('${r['senales_transversales']} de las ${r['senales_total']} señales son **transversales** (Riesgos y Estrategia cruzan hechos que otros agentes ya reportaron, por lo que pueden repetir un tema).',
                    size: 12.3, color: c.text3),
              ),
            const SizedBox(height: 12),
            _graficos(context, d),
          ],
        ),
      ),
    );
  }

  Widget _graficos(BuildContext context, Map d) {
    final c = context.c;
    final sen = Map<String, dynamic>.from((d['resumen'] as Map)['senales'] as Map);
    final tot = severidades.fold<int>(0, (s, k) => s + ((sen[k] as num?)?.toInt() ?? 0));
    final maxSen = math.max(1, severidades.fold<int>(0, (m, k) => math.max(m, (sen[k] as num?)?.toInt() ?? 0)));
    final ags = [for (final a in d['agentes'] as List) if (a['con_info'] == true && a['score'] != null) a]
      ..sort((a, b) => (a['score'] as num).compareTo(b['score'] as num));
    final maxActividad = math.max(
      (d['omisiones'] as List? ?? const []).length,
      math.max((d['preguntas'] as List? ?? const []).length, (d['recomendaciones'] as List? ?? const []).length),
    );
    return GridCols(cols: 2, minItemWidth: 300, children: [
      GgCard(
        margin: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Alertas por gravedad'),
          Text('$tot señales en el análisis', style: TextStyle(fontSize: 12, color: c.text3)),
          const SizedBox(height: 10),
          for (final k in severidades)
            Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
              SizedBox(width: 82, child: Text(sevLabel(k), style: TextStyle(fontSize: 12, color: c.text2))),
              Expanded(child: GgBar(value: ((sen[k] as num?)?.toInt() ?? 0) / maxSen, color: sevColor(context, k), height: 10)),
              SizedBox(width: 30, child: Text('${sen[k] ?? 0}', textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            ])),
        ]),
      ),
      GgCard(
        margin: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Distribución de puntajes'),
          Text('Agentes con información sustantiva por tramo', style: TextStyle(fontSize: 12, color: c.text3)),
          const SizedBox(height: 10),
          for (final tramo in [
            ('0–39', 0, 39, c.crit),
            ('40–54', 40, 54, c.high),
            ('55–74', 55, 74, c.med),
            ('75–89', 75, 89, c.accentText),
            ('90–100', 90, 100, c.low),
          ])
            Builder(builder: (context) {
              final n = ags.where((a) => (a['score'] as num).toInt() >= tramo.$2 && (a['score'] as num).toInt() <= tramo.$3).length;
              return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
                SizedBox(width: 58, child: Text(tramo.$1, style: TextStyle(fontSize: 11.5, color: c.text2))),
                Expanded(child: GgBar(value: n / math.max(1, ags.length), color: tramo.$4, height: 9)),
                SizedBox(width: 25, child: Text('$n', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
              ]));
            }),
        ]),
      ),
      GgCard(
        margin: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Trabajo generado por los agentes'),
          Text('Volumen detectado en el documento', style: TextStyle(fontSize: 12, color: c.text3)),
          const SizedBox(height: 10),
          for (final item in [
            ('Omisiones', (d['omisiones'] as List? ?? const []).length, c.accentText),
            ('Preguntas', (d['preguntas'] as List? ?? const []).length, c.med),
            ('Recomendaciones', (d['recomendaciones'] as List? ?? const []).length, c.low),
          ])
            Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
              SizedBox(width: 100, child: Text(item.$1, style: TextStyle(fontSize: 12, color: c.text2))),
              Expanded(child: GgBar(value: item.$2 / math.max(1, maxActividad), color: item.$3, height: 10)),
              SizedBox(width: 30, child: Text('${item.$2}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            ])),
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
          for (final r in vis) _Tarea(
            key: ValueKey('${r['id']}'),
            r: r,
            acc: accDe('${r['id']}'),
            onSave: (draft) => _guardarAccion('${r['id']}', draft),
            onSuggest: () => _sugerirResponsable(r),
          ),
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
      Row(children: [
        Expanded(child: _modo(context, 'Mi año anterior', !_competencia, () => _cambiarModo(false))),
        const SizedBox(width: 8),
        Expanded(child: _modo(context, 'Competencia', _competencia, () => _cambiarModo(true))),
      ]),
      const SizedBox(height: 14),
      Text(_competencia ? 'Comparación de competencia' : 'Comparar con otro documento', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      if (_competencia) ...[
        Text('Selecciona un documento cargado que represente a la empresa competidora. La comparación usa solo documentos de tu espacio; no consulta fuentes externas.', style: TextStyle(fontSize: 12.3, color: c.text2)),
        const SizedBox(height: 8),
        TextField(controller: _competidor, decoration: const InputDecoration(labelText: 'Nombre de la empresa competidora', prefixIcon: Icon(Icons.business_outlined))),
        const SizedBox(height: 8),
      ],
    ];
    if (otros.isEmpty) {
      hijos.add(Text('Cuando tengas un segundo documento analizado (por ejemplo, el trimestre anterior) podrás ver aquí cómo cambió cada agente.',
          style: TextStyle(fontSize: 12.3, color: c.text2)));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: hijos);
    }
    hijos.addAll([
      Text(_competencia ? 'Elige el documento de la empresa competidora; se compara con el documento activo. Los resultados son referenciales y dependen del contenido cargado.' : 'Elige el documento anterior; se compara contra el que estás viendo.', style: TextStyle(fontSize: 12.3, color: c.text2)),
      const SizedBox(height: 10),
      GgSelect<String>(label: _competencia ? 'Documento de la empresa competidora' : 'Documento anterior', value: cmpId, items: [('', 'Elegir…'), for (final o in otros) ('${o['id']}', nombreDoc(o))],
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
          if (_competencia) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('Comparación basada en el documento cargado “${nombreDoc(x['a'] as Map?)}” y el documento activo. No representa investigación de mercado externa.', style: TextStyle(fontSize: 11.5, color: c.text3))),
          Align(
            alignment: Alignment.centerRight,
            child: GgButton('Descargar comparación (PDF)', icon: Icons.picture_as_pdf_outlined, small: true, loading: cmpPdfCargando,
                onTap: () => _descargar('/api/dashboard-comparar/${Uri.encodeComponent(cmpId)}/${Uri.encodeComponent(_doc!)}/pdf', {},
                    'Comparacion_de_documentos.pdf', 'application/pdf', (v) => cmpPdfCargando = v)),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 18, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _bloqueCmp(context, _competencia ? (_competidor.text.trim().isEmpty ? 'Competidor' : _competidor.text.trim()) : 'Antes', g['a'], nombreDoc(x['a'] as Map?)),
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

  void _cambiarModo(bool competencia) => setState(() {
        _competencia = competencia;
        cmp = null;
        cmpId = '';
        cmpError = null;
        cmpCargando = false;
      });

  Widget _modo(BuildContext context, String texto, bool activo, VoidCallback onTap) {
    final c = context.c;
    return Material(
      color: activo ? c.accentSoft : c.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: activo ? Brand.accent : c.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Text(texto, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: activo ? c.accentText : c.text2)),
        ),
      ),
    );
  }

  Widget _bloqueCmp(BuildContext context, String t, Object? v, String nombre) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SecTitle(t, bottom: 2),
        Text('${v ?? '—'}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150),
            child: Text(nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: context.c.text3))),
      ]);
}

class _Tarea extends StatefulWidget {
  const _Tarea({super.key, required this.r, required this.acc, required this.onSave, required this.onSuggest});
  final Map<String, dynamic> r, acc;
  final void Function(Map<String, String> cambios) onSave;
  final Future<String?> Function() onSuggest;

  @override
  State<_Tarea> createState() => _TareaState();
}

class _TareaState extends State<_Tarea> {
  late final TextEditingController _responsable;
  late String _fecha;
  late String _estado;
  bool _dirty = false;
  bool _guardado = false;
  bool _sugiriendo = false;

  @override
  void initState() {
    super.initState();
    _responsable = TextEditingController(text: '${widget.acc['responsable'] ?? ''}');
    _fecha = '${widget.acc['fecha'] ?? ''}';
    _estado = '${widget.acc['estado'] ?? 'pendiente'}';
  }

  @override
  void didUpdateWidget(covariant _Tarea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && oldWidget.acc != widget.acc) {
      _responsable.text = '${widget.acc['responsable'] ?? ''}';
      _fecha = '${widget.acc['fecha'] ?? ''}';
      _estado = '${widget.acc['estado'] ?? 'pendiente'}';
    }
  }

  @override
  void dispose() {
    _responsable.dispose();
    super.dispose();
  }

  Future<void> _pedirSugerencia() async {
    setState(() => _sugiriendo = true);
    final sugerido = await widget.onSuggest();
    if (!mounted) return;
    setState(() {
      _sugiriendo = false;
      if (sugerido != null && sugerido.isNotEmpty) {
        _responsable.text = sugerido;
        _dirty = true;
        _guardado = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hecho = _estado == 'hecho';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${widget.r['agente_nombre']}', style: TextStyle(fontSize: 11.5, color: c.accentText, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text('${widget.r['texto']}', style: TextStyle(fontSize: 13, decoration: hecho ? TextDecoration.lineThrough : null, color: hecho ? c.text3 : c.text)),
        const SizedBox(height: 10),
        TextFormField(
          controller: _responsable,
          decoration: const InputDecoration(labelText: 'Responsable'),
          onChanged: (_) => setState(() { _dirty = true; _guardado = false; }),
        ),
        const SizedBox(height: 5),
        GgButton(_sugiriendo ? 'Buscando sugerencia…' : 'Sugerir responsable con IA',
          icon: Icons.auto_awesome, small: true, ghost: true, loading: _sugiriendo,
          onTap: _sugiriendo ? null : _pedirSugerencia),
        if (_dirty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(
          'Revisa el responsable y guarda los cambios.', style: TextStyle(fontSize: 11, color: c.text3))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: c.text, side: BorderSide(color: c.border2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: () async {
                final ini = DateTime.tryParse(_fecha) ?? DateTime.now();
                final f = await showDatePicker(context: context, initialDate: ini, firstDate: DateTime(2020), lastDate: DateTime(2035));
                if (f != null) setState(() {
                  _fecha = f.toIso8601String().substring(0, 10);
                  _dirty = true;
                  _guardado = false;
                });
              },
              icon: const Icon(Icons.event, size: 16),
              label: Text(_fecha.isEmpty ? 'Fecha límite' : _fecha, style: const TextStyle(fontSize: 12.5)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GgSelect<String>(label: 'Estado', value: _estado, items: estadosPlan,
                onChanged: (v) => setState(() { _estado = v; _dirty = true; _guardado = false; })),
          ),
        ]),
        const SizedBox(height: 10),
        GgButton('Guardar cambios', icon: Icons.save_outlined, expand: true, onTap: _dirty ? () {
          widget.onSave({'responsable': _responsable.text.trim(), 'fecha': _fecha, 'estado': _estado});
          setState(() { _dirty = false; _guardado = true; });
        } : null),
        if (_guardado) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [
          Icon(Icons.check_circle_outline, size: 16, color: c.low),
          const SizedBox(width: 6),
          Text('Guardado en este teléfono', style: TextStyle(fontSize: 11.5, color: c.low)),
        ])),
      ]),
    );
  }
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
