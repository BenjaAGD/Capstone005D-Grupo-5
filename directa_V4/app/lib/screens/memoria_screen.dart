import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/saver.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../state/trabajo_memoria.dart';
import '../widgets/common.dart';
import 'memoria_extra.dart';

const estadosCap = [('pend', 'Pendiente'), ('curso', 'En redacción'), ('listo', 'Listo')];

/// Memoria Anual: mismo contenido que memoria.html (GET /api/memoria/cobertura, /sugerir y /pdf).
class MemoriaScreen extends StatefulWidget {
  const MemoriaScreen({super.key});
  @override
  State<MemoriaScreen> createState() => _MemoriaScreenState();
}

const _kFuente = 'directa_memoria_fuente_v1';

class _MemoriaScreenState extends State<MemoriaScreen> {
  // Orden natural: 1) revisar fuentes y avance, 2) estilo, 3) crear la memoria.
  String pestana = TrabajoMemoria.instance.corriendo ? 'borrador' : 'capitulos';
  String fuente = '__todos__';
  Map<String, dynamic>? data;
  String? cap, error;
  bool cargando = false, soloMarcados = true, pdfCargando = false, sugiriendo = false;
  late Map<String, dynamic> mem;
  final Map<String, Map<String, dynamic>> sug = {};
  String sugMsg = 'Usa solo la evidencia ya encontrada: una consulta corta por capítulo.';
  final _notas = TextEditingController();
  Timer? _tNotas;
  final _kDetalle = GlobalKey();
  String? _notasCap;

  AppState get st => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    mem = Map<String, dynamic>.from(st.store.getJson<Map>(Store.kMemoria, {'caps': {}}));
    mem['caps'] = Map<String, dynamic>.from(mem['caps'] as Map? ?? {});
    // Por defecto la memoria usa SOLO el documento activo (antes mezclaba todos los documentos
    // y el borrador podía traer datos de otra empresa). La elección queda guardada.
    final guardada = st.store.getString(_kFuente);
    final ids = st.documentos.map((d) => '${d['id']}').toSet();
    if (guardada != null && (guardada == '__todos__' || ids.contains(guardada))) {
      fuente = guardada;
    } else if (st.docActivo != null) {
      fuente = st.docActivo!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  @override
  void dispose() {
    _tNotas?.cancel();
    _notas.dispose();
    super.dispose();
  }

  void _cambiarFuente(String v) {
    setState(() {
      fuente = v;
      sug.clear();
    });
    st.store.setString(_kFuente, v);
    _cargar();
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
          Text('¿Qué quieres hacer?', style: TextStyle(fontSize: Fs.xl, fontWeight: FontWeight.w700, color: context.c.text)),
          const SizedBox(height: 5),
          Text('La memoria reúne la gestión, los resultados y la información de la empresa durante el año. DIRECTA te ayuda a ordenar la evidencia y preparar un borrador revisable.',
              style: TextStyle(fontSize: Fs.md, height: 1.45, color: context.c.text2)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.c.surface2,
              border: Border.all(color: context.c.border),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(children: [
              _opcionMemoria('capitulos', Icons.fact_check_outlined, '1 · Fuentes y avance'),
              _opcionMemoria('tono', Icons.tune_outlined, '2 · Estilo'),
              _opcionMemoria('borrador', Icons.auto_awesome_outlined, '3 · Crear memoria'),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      if (pestana == 'borrador') BorradorMemoria(caps: () => mem['caps'] as Map<String, dynamic>),
      if (pestana == 'tono') const PerfilTono(),
      if (pestana == 'capitulos') _capitulos(context, app),
      if (pestana != 'borrador')
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: GgButton(
            pestana == 'capitulos' ? 'Siguiente: estilo' : 'Siguiente: crear memoria',
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onTap: () => setState(() => pestana = pestana == 'capitulos' ? 'tono' : 'borrador'),
          ),
        ),
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
                  style: TextStyle(fontSize: Fs.xs, height: 1.15, fontWeight: FontWeight.w700,
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
        title: Text('En el PDF, solo los temas que marqué como revisados', style: TextStyle(fontSize: Fs.md, color: c.text2)),
      ),
      GgSelect<String>(
            key: ValueKey('fuente-$fuente-Busca'),
        label: 'Buscar evidencia en',
        value: fuente,
        items: [('__todos__', 'Todos los documentos'), for (final d in app.documentos) ('${d['id']}', nombreDoc(d))],
        onChanged: _cambiarFuente,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 16, color: c.text3),
          const SizedBox(width: 7),
          Expanded(child: Text(
            'La casilla marca que revisaste el tema. La evidencia se calcula aparte a partir de los documentos.',
            style: TextStyle(fontSize: Fs.sm, height: 1.35, color: c.text3),
          )),
        ]),
      ),
      const SizedBox(height: 12),
    ];

    if (app.documentos.isEmpty) {
      hijos.add(GgCard(child: EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'Aún no hay documentos',
        text: 'La cobertura de la memoria (NCG 461) se calcula a partir de tus documentos. Sube uno para empezar.',
        action: GgButton('Ir a Documentos', icon: Icons.upload_file, expand: true, onTap: () => app.go('docs')),
      )));
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
    final f = (r['fuertes'] as num?)?.toInt() ?? 0;
    final w = (r['debiles'] as num?)?.toInt() ?? 0;
    final sn = (r['sin_evidencia'] as num?)?.toInt() ?? 0;
    final t = (r['temas_total'] as num?)?.toInt() ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: SecTitle('Cobertura NCG 461', bottom: 0)),
            Text('$f de $t temas', style: TextStyle(fontSize: Fs.sm, color: c.text2)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: Row(children: [
                if (f > 0) Expanded(flex: f, child: Container(margin: const EdgeInsets.only(right: 2), color: c.low)),
                if (w > 0) Expanded(flex: w, child: Container(margin: const EdgeInsets.only(right: 2), color: c.med)),
                if (sn > 0) Expanded(flex: sn, child: Container(color: c.crit)),
                if (f + w + sn == 0) Expanded(child: Container(color: c.track)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text('Con evidencia $f · Débil $w · Sin evidencia $sn', style: TextStyle(fontSize: Fs.sm, color: c.text3)),
          const SizedBox(height: 4),
          Text('$listos de ${caps.length} capítulos marcados como listos', style: TextStyle(fontSize: Fs.sm, color: c.text3)),
        ]),
      ),
      const SecTitle('Capítulos'),
      GgCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < caps.length; i++) _filaCapitulo(context, caps[i], i == caps.length - 1),
        ]),
      ),
      GgCard(
        color: c.surface2,
        child: MarkdownLite('**Cómo leer esto.** ${d['aviso']} ${d['referencia']}', size: Fs.sm, color: c.text2),
      ),
      KeyedSubtree(key: _kDetalle, child: _detalle(context, actual, caps.length, (d['fuentes'] as List).length == 1)),
    ]);
  }

  Widget _filaCapitulo(BuildContext context, Map<String, dynamic> x, bool ultima) {
    final c = context.c;
    final e = '${capMem('${x['id']}')['estado']}';
    final total = (x['total_temas'] as num?)?.toInt() ?? 0;
    final con = (x['con_evidencia'] as num?)?.toInt() ?? 0;
    final pct = total == 0 ? 0.0 : con / total;
    final sel = x['id'] == cap;
    return InkWell(
      onTap: () {
        setState(() => cap = '${x['id']}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _kDetalle.currentContext;
          if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350));
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: sel ? c.accentSoft : null,
          border: ultima ? null : Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(children: [
          Container(
            width: 26, height: 26, alignment: Alignment.center,
            decoration: BoxDecoration(color: sel ? Brand.accent : c.surface3, borderRadius: BorderRadius.circular(8)),
            child: Text('${x['numero']}',
                style: AppTheme.mono(context, size: Fs.sm, weight: FontWeight.w700, color: sel ? Brand.onAccent : c.text2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${x['titulo']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: Fs.body)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: GgBar(value: pct, color: pct >= 0.8 ? c.low : (pct >= 0.4 ? c.med : c.crit), height: 6)),
                const SizedBox(width: 8),
                Text('$con/$total', style: TextStyle(fontSize: Fs.xs, color: c.text3)),
              ]),
            ]),
          ),
          const SizedBox(width: 10),
          _estadoPill(context, e),
        ]),
      ),
    );
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
          Text('${x['titulo']}', style: const TextStyle(fontSize: Fs.xl, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          GgSelect<String>(label: 'Estado del capítulo', value: '${m['estado']}', items: estadosCap, onChanged: (v) {
            setState(() => m['estado'] = v);
            _save();
          }),
          const SizedBox(height: 10),
          Text('${x['descripcion']}', style: TextStyle(fontSize: Fs.md, color: c.text2)),
          const SizedBox(height: 12),
          const SecTitle('Temas que pide la norma'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 16, color: c.text3),
              const SizedBox(width: 7),
              Expanded(child: Text(
                'Marca cada casilla cuando hayas revisado ese tema. El nivel de evidencia se muestra por separado.',
                style: TextStyle(fontSize: Fs.sm, height: 1.35, color: c.text3),
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
                      style: TextStyle(fontSize: Fs.sm, color: c.text3)),
                for (final sg in (a['senales'] as List).take(6))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SevPill('${sg['severidad']}'),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${sg['titulo']}${unico ? '' : ' · ${sg['doc']}'}', style: const TextStyle(fontSize: Fs.md))),
                    ]),
                  ),
                if ((a['senales'] as List).length > 6)
                  Padding(padding: const EdgeInsets.only(top: 4),
                      child: Text('… y ${(a['senales'] as List).length - 6} más (ver el Dashboard)', style: TextStyle(fontSize: Fs.sm, color: c.text3))),
              ]),
            ),
        ]),
      ),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Notas de redacción'),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            GgButton('Sugerir borrador con IA', icon: Icons.auto_awesome, ghost: true, small: true, loading: sugiriendo, onTap: _sugerir),
            Text(sugMsg, style: TextStyle(fontSize: Fs.sm, color: c.text3)),
          ]),
          const SizedBox(height: 8),
          GgSelect<String>(
            key: ValueKey('fuente-$fuente-La IA'),
            label: 'La IA escribe usando',
            value: fuente,
            items: [('__todos__', 'Todos los documentos'), for (final d in context.read<AppState>().documentos) ('${d['id']}', nombreDoc(d))],
            onChanged: _cambiarFuente,
          ),
          if (s != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10), border: Border.all(color: Brand.accent)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SecTitle('Borrador sugerido · revísalo antes de usarlo'),
                for (final p in '${s['texto']}'.split('\n\n'))
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(p, style: AppTheme.lectura(context))),
                if (s['verificacion'] is Map) _revisionCifras(context, s),
                if ((s['pendientes'] as List? ?? const []).isNotEmpty) ...[
                  const SecTitle('Por completar', bottom: 4),
                  for (final p in s['pendientes'] as List)
                    Text('• ${p['dato']}${'${p['quien'] ?? ''}'.isNotEmpty ? ' — ${p['quien']}' : ''}', style: const TextStyle(fontSize: Fs.md)),
                ],
                const SizedBox(height: 10),
                GgButton('Usar en mis notas', expand: true, onTap: _usarSug),
                const SizedBox(height: 8),
                GgButton('Descartar', ghost: true, expand: true, onTap: () => setState(() => sug.remove(id))),
              ]),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _notas,
            minLines: 6,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: AppTheme.lectura(context),
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
                Text('${t['nombre']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: Fs.md)),
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
                        style: TextStyle(fontSize: Fs.xs, fontWeight: FontWeight.w600,
                            color: rev['${t['id']}'] == true ? c.low : c.text3)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: col.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(ic, size: 12, color: col),
                    const SizedBox(width: 4),
                    Text(txt, style: TextStyle(fontSize: Fs.xs, fontWeight: FontWeight.w700, color: col)),
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
                    title: Text('Ver fragmento', style: TextStyle(fontSize: Fs.sm, color: c.text3)),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: c.surface2, border: Border(left: BorderSide(color: Brand.accent, width: 3))),
                        child: Text('${fr['texto']}\n${fr['doc']} · pág. ${fr['pagina'] ?? '?'}', style: TextStyle(fontSize: Fs.sm, color: c.text2)),
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
          Expanded(child: Text('${v['etiqueta']} · ${v['resumen']}', style: TextStyle(fontSize: Fs.sm, color: col))),
        ]),
        for (final o in otros)
          Text('• «${o['cifra']}» solo aparece en ${o['documento'] ?? 'un documento anterior'} (pág. ${o['pagina'] ?? '?'}).',
              style: TextStyle(fontSize: Fs.sm, color: c.med)),
        for (final a in (s['alertas'] as List? ?? const [])) Text('• $a', style: TextStyle(fontSize: Fs.sm, color: c.med)),
        if (s['tono'] is Map) Text('Escrito con el perfil de tono v${(s['tono'] as Map)['version']}.', style: TextStyle(fontSize: Fs.sm, color: c.text3)),
      ]),
    );
  }

  Widget _pg(BuildContext context, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: context.c.border2)),
        child: Text(t, style: AppTheme.mono(context, size: Fs.xs, color: context.c.text2)),
      );
}
