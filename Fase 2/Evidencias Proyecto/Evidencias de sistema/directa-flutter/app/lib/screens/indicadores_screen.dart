import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/saver.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'ayudas.dart';

const estadosSol = [
  ('pendiente', 'Pendiente'),
  ('curso', 'En curso'),
  ('hecho', 'Hecha'),
];
const semTxt = {
  'verde': 'En meta',
  'amarillo': 'Atención',
  'rojo': 'Fuera de meta',
  'sin_dato': 'Sin dato',
};

double? numero(Object? x) => x == null
    ? null
    : double.tryParse('$x'.replaceAll(',', '.').replaceAll('%', '').trim());

/// Misma regla que semaforo() de indicadores.html / estado_semaforo() de indicadores.py.
String semaforo(Object? valor, Object? meta, Object? limite, String? dir) {
  final v = numero(valor), m = numero(meta);
  if (v == null || m == null) return 'sin_dato';
  final l = numero(limite) ?? m;
  if (dir == 'menor') return v <= m ? 'verde' : (v <= l ? 'amarillo' : 'rojo');
  return v >= m ? 'verde' : (v >= l ? 'amarillo' : 'rojo');
}

String fmtNum(Object? x) {
  final n = numero(x);
  if (n == null) return '—';
  return n == n.roundToDouble()
      ? n.toInt().toString()
      : ((n * 100).round() / 100).toString();
}

Color semColor(BuildContext context, String e) {
  final c = context.c;
  return switch (e) {
    'verde' => c.low,
    'amarillo' => c.med,
    'rojo' => c.crit,
    _ => c.text3,
  };
}

/// Indicadores (KPI / KRI): mismo contenido que indicadores.html.
class IndicadoresScreen extends StatefulWidget {
  const IndicadoresScreen({super.key});
  @override
  State<IndicadoresScreen> createState() => _IndicadoresScreenState();
}

class _IndicadoresScreenState extends State<IndicadoresScreen> {
  Map<String, dynamic>? sug;
  bool cargando = false, pdfCargando = false;
  String? errorSug, _doc;
  late List<Map<String, dynamic>> propios;
  late Map<String, dynamic> ajustes;
  final Set<String> iaCargando = {};

  AppState get st => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    propios = [
      for (final p in st.store.getJson<List>(Store.kIndPropios, const []))
        if (p is Map) Map<String, dynamic>.from(p),
    ];
    ajustes = Map<String, dynamic>.from(
      st.store.getJson<Map>(Store.kIndAjustes, {}),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final d = context.watch<AppState>().docActivo;
    if (d != _doc) {
      _doc = d;
      if (d != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
      }
    }
  }

  void _saveProp() => st.store.setJson(Store.kIndPropios, propios);
  void _saveAj() => st.store.setJson(Store.kIndAjustes, ajustes);
  String _claveAj(String id) => '$_doc|$id';
  Map<String, dynamic> _aj(String id) =>
      Map<String, dynamic>.from(ajustes[_claveAj(id)] as Map? ?? {});
  void _setAj(String id, String f, String v) {
    final a = _aj(id)..[f] = v;
    ajustes[_claveAj(id)] = a;
    _saveAj();
  }

  Future<void> _cargar({bool forzar = false}) async {
    if (_doc == null) return;
    setState(() {
      cargando = true;
      errorSug = null;
    });
    try {
      final r = await st.api.getJson(
        '/api/indicadores/sugeridos/${Uri.encodeComponent(_doc!)}',
        query: forzar ? {'refrescar': '1'} : null,
      );
      if (r['ok'] != true) {
        throw Exception(
          r['error'] ?? 'No se pudieron calcular los indicadores',
        );
      }
      sug = Map<String, dynamic>.from(r);
    } catch (e) {
      sug = null;
      errorSug = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => cargando = false);
  }

  List<Map<String, dynamic>> _todos() => [
    for (final i in (sug?['indicadores'] as List? ?? const []))
      {...Map<String, dynamic>.from(i as Map), 'origen': 'auto'},
    for (final p in propios)
      {
        ...p,
        'origen': 'propio',
        'soluciones': <String>[],
        'como': '',
        'estado': semaforo(p['valor'], p['meta'], p['limite'], p['direccion']),
      },
  ];

  Future<void> _pdf() async {
    final aj = <String, dynamic>{};
    ajustes.forEach((k, v) {
      final partes = k.split('|');
      if (partes.first == '$_doc') {
        final m = v as Map;
        aj[partes.sublist(1).join('|')] = {
          'responsable': m['responsable'],
          'fecha': m['fecha'],
          'estado_solucion': m['estado'],
          'solucion': m['solucion'],
        };
      }
    });
    setState(() => pdfCargando = true);
    try {
      final b = await st.api.download(
        '/api/indicadores/pdf',
        json: {'documento_id': _doc, 'propios': propios, 'ajustes': aj},
      );
      st.toast(
        await guardarArchivo(
          'Indicadores_${DateTime.now().toIso8601String().substring(0, 10)}.pdf',
          b,
          'application/pdf',
        ),
      );
    } catch (e) {
      st.toast('No se pudo generar el PDF: $e', err: true);
    }
    if (mounted) setState(() => pdfCargando = false);
  }

  Future<void> _exportar() async {
    final txt = const JsonEncoder.withIndent('  ')
        .convert({'version': 1, 'propios': propios, 'ajustes': ajustes});
    st.toast(
      await guardarArchivo(
        'Indicadores_Directa_${DateTime.now().toIso8601String().substring(0, 10)}.json',
        Uint8List.fromList(utf8.encode(txt)),
        'application/json',
      ),
    );
  }

  Future<void> _importar() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (f == null) return;
    try {
      final j = jsonDecode(utf8.decode(await f.xFile.readAsBytes())) as Map;
      final nuevos = [
        for (final p in (j['propios'] as List? ?? const []))
          if (p is Map && p['id'] != null && p['nombre'] != null)
            Map<String, dynamic>.from(p),
      ];
      for (final p in nuevos) {
        final k = propios.indexWhere((x) => x['id'] == p['id']);
        k >= 0 ? propios[k] = p : propios.add(p);
      }
      ajustes.addAll(Map<String, dynamic>.from(j['ajustes'] as Map? ?? {}));
      _saveProp();
      _saveAj();
      setState(() {});
      st.toast('Copia cargada (${nuevos.length} indicadores propios)');
    } catch (_) {
      st.toast('El archivo no es una copia válida', err: true);
    }
  }

  Future<void> _iaSolucion(Map<String, dynamic> it) async {
    final id = '${it['id']}';
    setState(() => iaCargando.add(id));
    try {
      final r = await st.api.postJson('/api/indicadores/sugerir', {
        'documento_id': _doc,
        'modo': 'solucion',
        'tipo': it['tipo'],
        'nombre': it['nombre'],
        'valor': it['valor'],
        'meta': it['meta'],
        'limite': it['limite'],
        'unidad': it['unidad'],
        'estado': it['estado'],
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Sin respuesta');
      final a = _aj(id);
      final previo = '${a['solucion'] ?? ''}'.trim();
      a['solucion'] = '${previo.isNotEmpty ? '$previo\n' : ''}${r['solucion']}';
      if ('${a['responsable'] ?? ''}'.isEmpty &&
          '${r['responsable'] ?? ''}'.isNotEmpty) {
        a['responsable'] = r['responsable'];
      }
      ajustes[_claveAj(id)] = a;
      _saveAj();
      st.toast('Solución sugerida agregada. Revísala.');
    } catch (e) {
      st.toast(
        'No se pudo sugerir: ${e.toString().replaceFirst('Exception: ', '')}',
        err: true,
      );
    }
    if (mounted) setState(() => iaCargando.remove(id));
  }

  Future<void> _form([Map<String, dynamic>? previo]) async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FormIndicador(previo: previo, doc: _doc, api: st),
    );
    if (r == null) return;
    final k = propios.indexWhere((p) => p['id'] == r['id']);
    k >= 0 ? propios[k] = r : propios.add(r);
    _saveProp();
    setState(() {});
    st.toast('Indicador guardado');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = context.watch<AppState>();
    final a = ayudas['indicadores']!;
    final todos = _todos();
    final cont = {'rojo': 0, 'amarillo': 0, 'verde': 0, 'sin_dato': 0};
    for (final i in todos) {
      cont['${i['estado']}'] = (cont['${i['estado']}'] ?? 0) + 1;
    }
    Widget? aviso;
    if (!app.backendOk && sug == null) {
      aviso = GgCard(
        borderColor: c.med,
        child: Text(
          'No se pudo conectar con el servidor. Los indicadores sugeridos no están disponibles, pero puedes ver y editar los tuyos.',
          style: TextStyle(color: c.text2),
        ),
      );
    } else if (errorSug != null) {
      aviso = GgCard(
        borderColor: c.med,
        child: Text(
          'No se pudieron calcular los indicadores sugeridos para este documento. $errorSug',
        ),
      );
    } else if (app.backendOk && app.documentos.isEmpty) {
      aviso = const GgCard(
        child: Text(
          'Todavía no hay documentos analizados, así que no hay indicadores sugeridos. Puedes agregar los tuyos con el botón de arriba.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHead(
          title: 'Indicadores',
          subtitle: 'Los números clave para el Gerente General: cómo vamos (KPI), qué nos puede salir mal (KRI) y qué hacemos al respecto (soluciones).',
          actions: [
            GgButton('+ Agregar indicador', onTap: () => _form()),
            GgButton(
              'Descargar PDF',
              icon: Icons.picture_as_pdf_outlined,
              ghost: true,
              small: true,
              loading: pdfCargando,
              onTap: _pdf,
            ),
            GgButton(
              'Guardar copia',
              icon: Icons.save_alt,
              ghost: true,
              small: true,
              onTap: _exportar,
            ),
            GgButton(
              'Cargar copia',
              icon: Icons.file_open_outlined,
              ghost: true,
              small: true,
              onTap: _importar,
            ),
            GgButton(
              'Actualizar datos',
              icon: Icons.refresh,
              ghost: true,
              small: true,
              onTap: () => _cargar(forzar: true),
            ),
          ],
        ),
        AyudaTile(parrafos: a.p, pasos: a.pasos),
        ?aviso,
        Opacity(
          opacity: cargando ? 0.55 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GridCols(
                cols: 4,
                minItemWidth: 150,
                children: [
                  KpiTile(
                    value: '${cont['rojo']}',
                    label: 'Fuera de meta',
                    color: c.crit,
                  ),
                  KpiTile(
                    value: '${cont['amarillo']}',
                    label: 'En atención',
                    color: c.med,
                  ),
                  KpiTile(
                    value: '${cont['verde']}',
                    label: 'En meta',
                    color: c.low,
                  ),
                  KpiTile(
                    value: '${todos.length}',
                    label: 'Indicadores en total',
                  ),
                ],
              ),
              for (final tipo in ['KPI', 'KRI']) _seccion(context, tipo, todos),
            ],
          ),
        ),
      ],
    );
  }

  Widget _seccion(
    BuildContext context,
    String tipo,
    List<Map<String, dynamic>> todos,
  ) {
    final c = context.c;
    const ord = ['rojo', 'amarillo', 'sin_dato', 'verde'];
    final lista = todos.where((i) => i['tipo'] == tipo).toList()
      ..sort(
        (a, b) => ord
            .indexOf('${a['estado']}')
            .compareTo(ord.indexOf('${b['estado']}')),
      );
    final t = tipo == 'KPI'
        ? (
            'KPI — ¿Cómo vamos?',
            'Indicadores de desempeño: miden si estamos cumpliendo las metas.',
          )
        : (
            'KRI — ¿Qué nos puede salir mal?',
            'Indicadores de riesgo: avisan cuando nos acercamos a un problema.',
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Text(
          t.$1,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(t.$2, style: TextStyle(fontSize: 12.3, color: c.text2)),
        const SizedBox(height: 10),
        if (lista.isEmpty)
          GgCard(
            child: Text(
              'Aún no hay $tipo para mostrar. Agrega uno con "+ Agregar indicador".',
              style: TextStyle(color: c.text2),
            ),
          ),
        for (final i in lista) _tarjeta(context, i),
      ],
    );
  }

  Widget _tarjeta(BuildContext context, Map<String, dynamic> i) {
    final c = context.c;
    final auto = i['origen'] == 'auto';
    final id = '${i['id']}';
    final a = auto ? _aj(id) : i;
    final estSol = auto
        ? '${a['estado'] ?? 'pendiente'}'
        : '${i['estado_solucion'] ?? 'pendiente'}';
    final resp = '${(auto ? a['responsable'] : i['responsable']) ?? ''}';
    final fecha = '${(auto ? a['fecha'] : i['fecha']) ?? ''}';
    final est = '${i['estado']}';
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    final vencida =
        fecha.isNotEmpty &&
        estSol != 'hecho' &&
        fecha.compareTo(hoy) < 0 &&
        est != 'verde';
    final u = '${i['unidad'] ?? ''}';
    final menor = i['direccion'] == 'menor';
    final metaTxt =
        'Meta: ${menor ? '≤' : '≥'} ${fmtNum(i['meta'])}$u${numero(i['limite']) == null ? '' : ' · Rojo si ${menor ? '>' : '<'} ${fmtNum(i['limite'])}$u'}';
    final soluciones = [
      for (final s in (i['soluciones'] as List? ?? const [])) '$s',
    ];

    void setCampo(String f, String v) {
      if (auto) {
        _setAj(id, f == 'estado' ? 'estado' : f, v);
      } else {
        final p = propios.firstWhere((x) => x['id'] == id);
        f == 'estado' ? p['estado_solucion'] = v : p[f] = v;
        _saveProp();
      }
      setState(() {});
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: semColor(context, est)),
          ),
          SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Pill(
                          '${i['tipo']} · ${auto ? 'sugerido' : 'propio'}',
                          fg: c.text3,
                          bg: c.surface3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Spacer(),
                      Flexible(
                        child: Pill(
                          semTxt[est]!.toUpperCase(),
                          fg: semColor(context, est),
                          dot: est != 'sin_dato',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${i['nombre']}',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: fmtNum(i['valor']),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -1,
                          ),
                        ),
                        TextSpan(
                          text: ' $u',
                          style: TextStyle(fontSize: 14, color: c.text3),
                        ),
                      ],
                    ),
                  ),
                  Text(metaTxt, style: TextStyle(fontSize: 12, color: c.text3)),
                  _Bala(
                    valor: numero(i['valor']),
                    meta: numero(i['meta']),
                    limite: numero(i['limite']),
                    menor: menor,
                  ),
                  if ('${i['como'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${i['como']}',
                        style: TextStyle(fontSize: 12, color: c.text2),
                      ),
                    ),
                  Divider(height: 24, color: c.border),
                  const SecTitle('Solución', bottom: 6),
                  if (auto) ...[
                    if (soluciones.isNotEmpty)
                      for (final s in soluciones)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            '• $s',
                            style: TextStyle(fontSize: 12.5, color: c.text2),
                          ),
                        )
                    else
                      Text(
                        est == 'verde'
                            ? 'En meta: no requiere acción por ahora.'
                            : 'Sin solución sugerida: escribe la tuya abajo.',
                        style: TextStyle(fontSize: 12.5, color: c.text3),
                      ),
                    const SizedBox(height: 8),
                    GgButton(
                      'Sugerir solución con IA',
                      icon: Icons.auto_awesome,
                      ghost: true,
                      small: true,
                      loading: iaCargando.contains(id),
                      onTap: () => _iaSolucion(i),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: ValueKey(
                        'sol-$_doc-$id-${a['solucion']?.toString().length ?? 0}',
                      ),
                      initialValue: '${a['solucion'] ?? ''}',
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Mi solución (opcional)',
                      ),
                      onChanged: (v) => _setAj(id, 'solucion', v),
                    ),
                  ] else
                    Text(
                      '${i['solucion'] ?? ''}'.isEmpty
                          ? 'Sin solución definida. Pulsa "Editar" para escribirla.'
                          : '${i['solucion']}',
                      style: TextStyle(
                        fontSize: 12.8,
                        color: '${i['solucion'] ?? ''}'.isEmpty
                            ? c.text3
                            : c.text,
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: ValueKey('resp-$_doc-$id'),
                    initialValue: resp,
                    decoration: const InputDecoration(
                      labelText: 'Responsable',
                      hintText: 'Nombre o área',
                    ),
                    onChanged: (v) => auto
                        ? _setAj(id, 'responsable', v)
                        : setCampo('responsable', v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.text,
                            side: BorderSide(color: c.border2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          onPressed: () async {
                            final f = await showDatePicker(
                              context: context,
                              initialDate:
                                  DateTime.tryParse(fecha) ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (f != null) {
                              setCampo(
                                'fecha',
                                f.toIso8601String().substring(0, 10),
                              );
                            }
                          },
                          icon: const Icon(Icons.event, size: 16),
                          label: Text(
                            fecha.isEmpty ? 'Fecha límite' : fecha,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GgSelect<String>(
                          label: 'Estado',
                          value: estSol,
                          items: estadosSol,
                          onChanged: (v) => setCampo('estado', v),
                        ),
                      ),
                    ],
                  ),
                  if (vencida)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '⚠ La fecha límite ya pasó y la solución no está hecha.',
                        style: TextStyle(
                          color: c.crit,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (!auto) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        GgButton(
                          'Editar',
                          ghost: true,
                          small: true,
                          onTap: () =>
                              _form(propios.firstWhere((x) => x['id'] == id)),
                        ),
                        GgButton(
                          'Eliminar',
                          danger: true,
                          small: true,
                          onTap: () async {
                            if (await confirmar(
                              context,
                              '¿Eliminar el indicador "${i['nombre']}"?',
                              ok: 'Eliminar',
                            )) {
                              propios.removeWhere((x) => x['id'] == id);
                              _saveProp();
                              setState(() {});
                              st.toast('Indicador eliminado');
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra de "bala": zonas verde/amarilla/roja, marca del valor actual y línea de la meta.
class _Bala extends StatelessWidget {
  const _Bala({
    required this.valor,
    required this.meta,
    required this.limite,
    required this.menor,
  });
  final double? valor, meta, limite;
  final bool menor;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (valor == null || meta == null) return const SizedBox.shrink();
    final v = valor!, m = meta!;
    final lim = limite ?? m;
    final max = math.max(math.max(v, m), math.max(lim, 1)) * 1.25;
    double p(double x) => (x / max).clamp(0, 1);
    final zonas = menor
        ? [(0.0, p(m), c.low), (p(m), p(lim), c.med), (p(lim), 1.0, c.high)]
        : [(0.0, p(lim), c.high), (p(lim), p(m), c.med), (p(m), 1.0, c.low)];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              return SizedBox(
                height: 14,
                child: Stack(
                  children: [
                    for (final (a, b, col) in zonas)
                      if (b > a)
                        Positioned(
                          left: w * a,
                          width: w * (b - a),
                          top: 4,
                          bottom: 4,
                          child: Container(color: col.withValues(alpha: 0.55)),
                        ),
                    Positioned(
                      left: (w * p(m) - 1).clamp(0, w - 2),
                      top: 1,
                      bottom: 1,
                      child: Container(width: 2, color: c.text3),
                    ),
                    Positioned(
                      left: (w * p(v) - 2).clamp(0, w - 4),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: c.text,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                'Valor actual',
                style: TextStyle(fontSize: 10.5, color: c.text3),
              ),
              const Spacer(),
              Text('Meta', style: TextStyle(fontSize: 10.5, color: c.text3)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormIndicador extends StatefulWidget {
  const _FormIndicador({
    required this.previo,
    required this.doc,
    required this.api,
  });
  final Map<String, dynamic>? previo;
  final String? doc;
  final AppState api;
  @override
  State<_FormIndicador> createState() => _FormIndicadorState();
}

class _FormIndicadorState extends State<_FormIndicador> {
  late String tipo;
  late final Map<String, TextEditingController> f;
  String? error;
  String iaMsg = '';
  bool ia = false;

  @override
  void initState() {
    super.initState();
    final p = widget.previo ?? {};
    tipo = p['tipo'] == 'KRI' ? 'KRI' : 'KPI';
    String v(String k) => p[k] == null ? '' : '${p[k]}';
    f = {
      for (final k in [
        'nombre',
        'unidad',
        'valor',
        'meta',
        'limite',
        'solucion',
        'responsable',
        'fecha',
      ])
        k: TextEditingController(text: v(k)),
    };
  }

  @override
  void dispose() {
    for (final x in f.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _ia() async {
    setState(() {
      ia = true;
      iaMsg = 'Pensando…';
    });
    try {
      final r = await widget.api.api.postJson('/api/indicadores/sugerir', {
        'documento_id': widget.doc,
        'modo': 'form',
        'tipo': tipo,
        'nombre': f['nombre']!.text.trim(),
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Sin respuesta');
      void poner(String k, Object? val) {
        if (f[k]!.text.trim().isEmpty && val != null && '$val'.isNotEmpty) {
          f[k]!.text = fmtNum(val) == '—' ? '$val' : fmtNum(val);
        }
      }

      poner('nombre', r['nombre']);
      poner('unidad', r['unidad']);
      poner('meta', r['meta']);
      poner('limite', r['limite']);
      poner('solucion', r['solucion']);
      poner('responsable', r['responsable']);
      iaMsg = 'Listo: completé solo los campos vacíos. Ingresa el valor actual y revisa meta y límite.';
    } catch (e) {
      iaMsg = 'No se pudo: ${e.toString().replaceFirst('Exception: ', '')}';
    }
    if (mounted) setState(() => ia = false);
  }

  void _guardar() {
    String g(String k) => f[k]!.text.trim();
    if (g('nombre').isEmpty) {
      return setState(() => error = 'Escribe el nombre del indicador.');
    }
    if (numero(g('valor')) == null) {
      return setState(() => error = 'El valor actual debe ser un número.');
    }
    if (numero(g('meta')) == null) {
      return setState(() => error = 'La meta debe ser un número.');
    }
    if (g('limite').isNotEmpty && numero(g('limite')) == null) {
      return setState(
        () => error = 'El límite debe ser un número (o déjalo vacío).',
      );
    }
    final p = widget.previo ?? {};
    Navigator.pop(context, <String, dynamic>{
      ...p,
      'id':
          p['id'] ??
          'p${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${math.Random().nextInt(1 << 20).toRadixString(36)}',
      'tipo': tipo,
      'direccion': tipo == 'KRI' ? 'menor' : 'mayor',
      'nombre': g('nombre'),
      'unidad': g('unidad'),
      'valor': numero(g('valor')),
      'meta': numero(g('meta')),
      'limite': g('limite').isEmpty ? null : numero(g('limite')),
      'solucion': g('solucion'),
      'responsable': g('responsable'),
      'fecha': g('fecha'),
      'estado_solucion': p['estado_solucion'] ?? 'pendiente',
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final kri = tipo == 'KRI';
    Widget campo(
      String k,
      String label, {
      String? hint,
      bool num = false,
      int lines = 1,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: f[k],
        minLines: lines,
        maxLines: lines == 1 ? 1 : 4,
        keyboardType: num
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : null,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.previo == null ? 'Nuevo indicador' : 'Editar indicador',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Completa lo básico. El semáforo se calcula solo con el valor, la meta y el límite.',
              style: TextStyle(fontSize: 12.5, color: c.text2),
            ),
            const SizedBox(height: 14),
            GgSelect<String>(
              label: 'Tipo',
              value: tipo,
              items: const [
                ('KPI', 'KPI — desempeño (más alto es mejor)'),
                ('KRI', 'KRI — riesgo (más bajo es mejor)'),
              ],
              onChanged: (v) => setState(() => tipo = v),
            ),
            const SizedBox(height: 10),
            campo(
              'nombre',
              'Nombre del indicador *',
              hint: 'Ej: Ventas versus presupuesto',
            ),
            Row(
              children: [
                Expanded(child: campo('valor', 'Valor actual *', num: true)),
                const SizedBox(width: 8),
                Expanded(
                  child: campo('unidad', 'Unidad', hint: '%, \$, días…'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: campo(
                    'meta',
                    'Meta *',
                    hint: kri ? 'Máximo aceptable' : 'Lo que queremos lograr',
                    num: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: campo(
                    'limite',
                    'Límite (pasa a rojo)',
                    hint: kri
                        ? 'Sobre este valor es rojo'
                        : 'Bajo este valor es rojo',
                    num: true,
                  ),
                ),
              ],
            ),
            campo('solucion', 'Solución / acción a tomar', lines: 2),
            Row(
              children: [
                Expanded(
                  child: campo(
                    'responsable',
                    'Responsable',
                    hint: 'Nombre o área',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: campo('fecha', 'Fecha límite', hint: 'AAAA-MM-DD'),
                ),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: c.crit, fontWeight: FontWeight.w600),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GgButton('Guardar indicador', onTap: _guardar),
                GgButton(
                  'Sugerir con IA',
                  icon: Icons.auto_awesome,
                  ghost: true,
                  loading: ia,
                  onTap: _ia,
                ),
                GgButton(
                  'Cancelar',
                  ghost: true,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
            if (iaMsg.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  iaMsg,
                  style: TextStyle(fontSize: 12, color: c.text3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
