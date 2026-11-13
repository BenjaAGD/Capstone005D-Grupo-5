import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/saver.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

const _kMarca = 'directa_marca_memoria_v1';
const _coloresMarca = ['#1B2F4B', '#0E5A8A', '#0E7490', '#12AFC6', '#237AA8', '#4664A8'];

Color _hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));

/// "Borrador de memoria" en un paso (Frente D): se elige el año y se obtiene el PDF para revisar.
class BorradorMemoria extends StatefulWidget {
  const BorradorMemoria({super.key, required this.caps});
  final Map<String, dynamic> Function() caps;
  @override
  State<BorradorMemoria> createState() => _BorradorMemoriaState();
}

class _BorradorMemoriaState extends State<BorradorMemoria> {
  List<Map<String, dynamic>> anios = [];
  int? anio;
  bool cargando = true, generando = false;
  String? error, logo;
  String color = _coloresMarca.first;
  final _nombre = TextEditingController();
  Map<String, dynamic>? progreso, resultado;
  Timer? _poll;

  AppState get st => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    final m = st.store.getJson<Map>(_kMarca, {});
    _nombre.text = '${m['nombre'] ?? ''}';
    if (_coloresMarca.contains(m['color'])) color = '${m['color']}';
    logo = m['logo'] as String?;
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _nombre.dispose();
    super.dispose();
  }

  void _guardarMarca() => st.store.setJson(_kMarca, {'nombre': _nombre.text.trim(), 'color': color, if (logo != null) 'logo': logo});

  Future<void> _cargar() async {
    try {
      final r = await st.api.getJson('/api/memoria/anios');
      anios = [for (final a in (r['anios'] as List? ?? const [])) if (a is Map) Map<String, dynamic>.from(a)];
      anio ??= anios.isEmpty ? null : (anios.first['anio'] as num).toInt();
      error = null;
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => cargando = false);
  }

  Future<void> _elegirLogo() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg']);
    if (f == null) return;
    final bytes = await f.xFile.readAsBytes();
    if (bytes.length > 1500000) {
      st.toast('El logo debe pesar menos de 1,5 MB', err: true);
      return;
    }
    final tipo = f.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
    setState(() => logo = 'data:image/$tipo;base64,${base64Encode(bytes)}');
    _guardarMarca();
  }

  Future<void> _generar() async {
    if (anio == null || generando) return;
    _guardarMarca();
    setState(() {
      generando = true;
      progreso = {'paso': 'Iniciando…', 'hechos': 0, 'total': 1};
      resultado = null;
      error = null;
    });
    try {
      final propios = st.store.getJson<List>(Store.kIndPropios, const []);
      final r = await st.api.postJson('/api/memoria/borrador', {
        'anio': anio,
        'marca': {'nombre': _nombre.text.trim(), 'color': color, if (logo != null) 'logo': logo},
        'caps': widget.caps(),
        'propios': propios,
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'No se pudo iniciar');
      final id = '${r['job_id']}';
      final listo = Completer<Map<String, dynamic>>();
      _poll = Timer.periodic(const Duration(milliseconds: 1500), (t) async {
        try {
          final e = Map<String, dynamic>.from(await st.api.getJson('/api/memoria/borrador/$id') as Map);
          if (!mounted) return;
          setState(() => progreso = e);
          if (e['corriendo'] != true && !listo.isCompleted) {
            t.cancel();
            listo.complete(e);
          }
        } catch (err) {
          if (!listo.isCompleted) {
            t.cancel();
            listo.completeError(err);
          }
        }
      });
      final e = await listo.future;
      if (e['listo'] != true) throw Exception(e['error'] ?? 'El borrador no se pudo generar');
      final bytes = await st.api.getBytes('/api/memoria/borrador/$id/pdf');
      resultado = e;
      st.toast(await guardarArchivo('${e['nombre'] ?? 'Memoria_borrador.pdf'}', bytes, 'application/pdf'));
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => generando = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (cargando) return const GgCard(child: EmptyState(icon: Icons.hourglass_empty, title: 'Cargando…', loading: true));
    if (anios.isEmpty) {
      return GgCard(
        child: EmptyState(
          icon: Icons.menu_book_outlined,
          title: 'No hay documentos con año',
          text: error ?? 'Sube los documentos del año (el año debe ir en el nombre del archivo, por ejemplo «Informe_2025.pdf»).',
        ),
      );
    }
    final docsAnio = [for (final g in anios) if (g['anio'] == anio) ...(g['documentos'] as List)];
    final total = (progreso?['total'] as num?)?.toInt() ?? 1;
    final hechos = (progreso?['hechos'] as num?)?.toInt() ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('1. Año de la memoria'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final g in anios)
              ChipBtn('${g['anio']}', on: anio == g['anio'], onTap: () => setState(() => anio = (g['anio'] as num).toInt())),
          ]),
          const SizedBox(height: 8),
          Text('Documentos del año: ${docsAnio.map((d) => d['nombre']).join(', ')}', style: TextStyle(fontSize: 12, color: c.text3)),
          const SizedBox(height: 16),
          const SecTitle('2. Marca de la portada'),
          TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre de la empresa'), onChanged: (_) => _guardarMarca()),
          const SizedBox(height: 12),
          Row(children: [
            for (final h in _coloresMarca)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    setState(() => color = h);
                    _guardarMarca();
                  },
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: _hex(h), shape: BoxShape.circle,
                        border: Border.all(color: color == h ? c.text : Colors.transparent, width: 2.5)),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            GgButton(logo == null ? 'Agregar logo' : 'Cambiar logo', icon: Icons.image_outlined, ghost: true, small: true, onTap: _elegirLogo),
            const SizedBox(width: 8),
            if (logo != null)
              TextButton(onPressed: () {
                setState(() => logo = null);
                _guardarMarca();
              }, child: const Text('Quitar logo')),
          ]),
          const SizedBox(height: 16),
          GgButton(generando ? 'Generando…' : 'Generar borrador en PDF', icon: Icons.picture_as_pdf_outlined, expand: true,
              loading: generando, onTap: anio == null ? null : _generar),
          const SizedBox(height: 8),
          Text('Incluye portada, índice, carta del Gerente General, los 11 capítulos (tus notas o un borrador del Redactor), '
              'gráficos de indicadores, una página tipo dashboard, la cobertura de la NCG 461 y la revisión de cifras.',
              style: TextStyle(fontSize: 12, color: c.text3, height: 1.4)),
        ]),
      ),
      if (generando && progreso != null)
        GgCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${progreso!['paso'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GgBar(value: total == 0 ? 0 : hechos / total),
            const SizedBox(height: 4),
            Text('$hechos de $total pasos', style: TextStyle(fontSize: 11.5, color: c.text3)),
          ]),
        ),
      if (error != null) GgCard(borderColor: c.crit, child: Text(error!, style: TextStyle(color: c.crit))),
      if (resultado != null)
        GgCard(
          borderColor: c.low,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.check_circle_outline, color: c.low),
              const SizedBox(width: 8),
              const Expanded(child: Text('Borrador listo', style: TextStyle(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 6),
            Text('${resultado!['graficos'] ?? 0} gráficos · '
                '${(resultado!['revision'] as List? ?? const []).length} alertas de cifras · '
                '${resultado!['tono'] == null ? 'sin perfil de tono aprobado' : 'con el perfil de tono v${(resultado!['tono'] as Map)['version']}'}',
                style: TextStyle(fontSize: 12.5, color: c.text2)),
            for (final a in (resultado!['revision'] as List? ?? const []).take(6))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• ${a['seccion']}: ${a['alerta']}', style: TextStyle(fontSize: 12, color: c.med)),
              ),
            if (resultado!['tono'] == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Para que suene como las memorias anteriores, aprueba un perfil en «Perfil de tono».',
                    style: TextStyle(fontSize: 12, color: c.text3)),
              ),
          ]),
        ),
    ]);
  }
}

/// Perfil de tono (Frente D1): el Redactor lo extrae de memorias anteriores; el gerente lo corrige y aprueba.
class PerfilTono extends StatefulWidget {
  const PerfilTono({super.key});
  @override
  State<PerfilTono> createState() => _PerfilTonoState();
}

class _PerfilTonoState extends State<PerfilTono> {
  static const _textos = [
    ('persona', 'Persona y a quién se dirige'),
    ('formalidad', 'Formalidad'),
    ('largo_capitulos', 'Largo típico'),
    ('cifras', 'Cómo presenta las cifras'),
    ('cierres', 'Cómo cierra las secciones'),
  ];
  static const _listas = [
    ('vocabulario_frecuente', 'Vocabulario típico (separado por comas)'),
    ('vocabulario_evitar', 'Vocabulario a evitar (separado por comas)'),
    ('rasgos', 'Otros rasgos (separados por comas)'),
  ];
  Map<String, dynamic>? perfil;
  int minimo = 3;
  bool cargando = true, trabajando = false;
  final Set<String> seleccion = {};
  final Map<String, TextEditingController> ctrl = {};
  String? error;

  AppState get st => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    for (final (k, _) in [..._textos, ..._listas]) {
      ctrl[k] = TextEditingController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  @override
  void dispose() {
    for (final c in ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _llenar() {
    final p = (perfil?['perfil'] as Map?) ?? {};
    for (final (k, _) in _textos) {
      ctrl[k]!.text = '${p[k] ?? ''}';
    }
    for (final (k, _) in _listas) {
      ctrl[k]!.text = [for (final x in (p[k] as List? ?? const [])) '$x'].join(', ');
    }
  }

  Future<void> _cargar() async {
    try {
      final r = await st.api.getJson('/api/memoria/perfil-tono');
      if (r['ok'] != true) throw Exception(r['error']);
      perfil = r['perfil'] is Map ? Map<String, dynamic>.from(r['perfil'] as Map) : null;
      minimo = (r['minimo_memorias'] as num?)?.toInt() ?? 3;
      _llenar();
      error = null;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => cargando = false);
  }

  Map<String, dynamic> _editado() => {
        for (final (k, _) in _textos) k: ctrl[k]!.text.trim(),
        for (final (k, _) in _listas) k: [for (final x in ctrl[k]!.text.split(',')) if (x.trim().isNotEmpty) x.trim()],
      };

  Future<void> _accion(Future<dynamic> Function() f, String ok) async {
    setState(() => trabajando = true);
    try {
      final r = await f();
      if (r['ok'] != true) throw Exception(r['error'] ?? 'error');
      perfil = Map<String, dynamic>.from(r['perfil'] as Map);
      _llenar();
      st.toast(ok);
    } catch (e) {
      st.toast(e.toString().replaceFirst('Exception: ', ''), err: true);
    }
    if (mounted) setState(() => trabajando = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = context.watch<AppState>();
    if (cargando) return const GgCard(child: EmptyState(icon: Icons.hourglass_empty, title: 'Cargando…', loading: true));
    final docs = app.documentos.where((d) => !estadosProcesando.contains(d['estado'])).toList();
    final corpus = [for (final x in (perfil?['corpus'] as List? ?? const [])) if (x is Map) x];
    final medidas = (perfil?['medidas'] as Map?) ?? {};
    final aprobado = perfil?['estado'] == 'aprobado';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (error != null) GgCard(borderColor: c.crit, child: Text(error!, style: TextStyle(color: c.crit))),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Memorias anteriores para aprender el tono'),
          Text('Elige al menos $minimo memorias de años anteriores ya subidas. El Redactor describe su estilo sin copiar frases ni cifras.',
              style: TextStyle(fontSize: 12.5, color: c.text2)),
          const SizedBox(height: 8),
          for (final d in docs)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: seleccion.contains('${d['id']}'),
              onChanged: (v) => setState(() => v == true ? seleccion.add('${d['id']}') : seleccion.remove('${d['id']}')),
              title: Text(nombreDoc(d), style: const TextStyle(fontSize: 13)),
            ),
          const SizedBox(height: 8),
          GgButton(perfil == null ? 'Extraer perfil de tono' : 'Volver a extraer con estas memorias', icon: Icons.auto_awesome,
              loading: trabajando, onTap: seleccion.isEmpty ? null : () => _accion(
                  () => st.api.postJson('/api/memoria/perfil-tono/extraer', {'documentos': seleccion.toList()}),
                  'Perfil extraído: revísalo y apruébalo')),
        ]),
      ),
      if (perfil != null)
        GgCard(
          borderColor: aprobado ? c.low : c.med,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Perfil de tono v${perfil!['version']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              Pill(aprobado ? 'APROBADO' : 'BORRADOR', fg: aprobado ? c.low : c.med),
            ]),
            const SizedBox(height: 4),
            Text('Corpus: ${corpus.map((x) => '${x['nombre']}${x['anio'] != null ? ' (${x['anio']})' : ''}').join(', ')}',
                style: TextStyle(fontSize: 12, color: c.text3)),
            if ('${perfil!['aviso'] ?? ''}'.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('${perfil!['aviso']}', style: TextStyle(fontSize: 12, color: c.med))),
            const SizedBox(height: 12),
            KpiStrip(items: [
              (valor: '${medidas['palabras_por_oracion'] ?? '-'}', etiqueta: 'Palabras por oración', color: null, onTap: null),
              (valor: '${medidas['primera_persona_pct'] ?? '-'}%', etiqueta: 'Primera persona', color: null, onTap: null),
              (valor: '${medidas['tercera_persona_pct'] ?? '-'}%', etiqueta: '«La Compañía»', color: null, onTap: null),
            ]),
            for (final (k, l) in _textos) ...[
              TextField(controller: ctrl[k], minLines: 1, maxLines: 3, decoration: InputDecoration(labelText: l)),
              const SizedBox(height: 12),
            ],
            for (final (k, l) in _listas) ...[
              TextField(controller: ctrl[k], minLines: 1, maxLines: 3, decoration: InputDecoration(labelText: l)),
              const SizedBox(height: 12),
            ],
            if ((medidas['terminos_frecuentes'] as List? ?? const []).isNotEmpty)
              Text('Términos más frecuentes (medidos): ${(medidas['terminos_frecuentes'] as List).take(10).join(', ')}',
                  style: TextStyle(fontSize: 11.5, color: c.text3)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              GgButton('Guardar cambios', icon: Icons.save_outlined, ghost: true, small: true, loading: trabajando,
                  onTap: () => _accion(() => st.api.putJson('/api/memoria/perfil-tono/${perfil!['id']}', {'perfil': _editado()}),
                      'Cambios guardados')),
              GgButton(aprobado ? 'Aprobado' : 'Aprobar perfil', icon: Icons.verified_outlined, small: true, loading: trabajando,
                  onTap: aprobado ? null : () => _accion(
                      () => st.api.putJson('/api/memoria/perfil-tono/${perfil!['id']}', {'perfil': _editado(), 'aprobar': true}),
                      'Perfil aprobado: los borradores lo usarán')),
            ]),
            const SizedBox(height: 16),
            const SecTitle('Sumar una memoria aprobada al corpus'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in docs.where((d) => !corpus.any((x) => x['document_id'] == d['id'])))
                ChipBtn(nombreDoc(d), on: false, maxWidth: 260, onTap: () => _accion(
                    () => st.api.postJson('/api/memoria/perfil-tono/corpus', {'document_id': d['id']}),
                    'Memoria sumada: el perfil nuevo queda en borrador para aprobar')),
            ]),
          ]),
        ),
    ]);
  }
}
