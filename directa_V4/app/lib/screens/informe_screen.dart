import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/saver.dart';
import '../core/sev.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/verificacion.dart';

String plano(Object? t) => (t ?? '').toString().replaceAll(RegExp(r'\*\*|__'), '').replaceAll(RegExp(r'^\s*[-•*]\s+', multiLine: true), '• ');

class InformeScreen extends StatefulWidget {
  const InformeScreen({super.key});

  @override
  State<InformeScreen> createState() => _InformeScreenState();
}

class _InformeScreenState extends State<InformeScreen> {
  int _paso = 0;

  /// Mantiene el mismo cálculo ejecutivo que resumenGeneralJS() del MVP.
  List<String> _resumen(AppState st, List<Map<String, dynamic>> activos) {
    final an = activos.where((i) => i['tipo'] == 'analisis' && i['resultado'] is Map).toList();
    if (an.isEmpty) return [];
    final conInfo = an.where((i) => tieneInfo(i['resultado'] as Map)).toList();
    if (conInfo.length <= 2) {
      return [conInfo.isEmpty
          ? 'Ninguno de los ${an.length} agentes incluidos identificó contenido sustantivo en el documento.'
          : 'Solo ${conInfo.length} de los ${an.length} agentes incluidos identificó contenido relevante para su área.'];
    }
    final partes = ['El documento fue evaluado por ${an.length} agentes; ${conInfo.length} identificaron hallazgos relevantes.'];
    final cont = {for (final s in severidades) s: 0};
    final graves = <({String sv, String k, String t})>[];
    bool integ(String k) => st.agente(k)?.tipo == 'integrador';
    var transv = 0;
    for (final i in conInfo) {
      for (final s in listaDe(i['resultado'] as Map, 'senales')) {
        final sv = normSev(s['severidad']);
        cont[sv] = cont[sv]! + 1;
        if (integ('${i['agente_key']}')) transv++;
        if ((sv == 'crítica' || sv == 'alta') && s['titulo'] != null) graves.add((sv: sv, k: '${i['agente_key']}', t: '${s['titulo']}'));
      }
    }
    final total = cont.values.fold<int>(0, (a, b) => a + b);
    if (total > 0) {
      partes.add('Se levantaron $total señales: ${severidades.where((s) => cont[s]! > 0).map((s) => '${cont[s]} ${sevPlural(s).toLowerCase()}').join(', ')}.'
          '${transv > 0 ? ' $transv de ellas son transversales (Riesgos y Estrategia cruzan hechos que otros agentes ya reportaron, por lo que pueden repetir un mismo tema).' : ''}');
    }
    graves.sort((a, b) {
      final d = severidades.indexOf(a.sv).compareTo(severidades.indexOf(b.sv));
      return d != 0 ? d : (integ(a.k) ? 1 : 0).compareTo(integ(b.k) ? 1 : 0);
    });
    if (graves.isNotEmpty) {
      partes.add('Señales de mayor severidad: ${graves.take(5).map((g) => '${st.nombreAgente(g.k)}: ${g.t} (${g.sv})').join('; ')}.');
    }
    final bajos = [for (final i in conInfo) (k: '${i['agente_key']}', s: scoreDe(i['resultado'] as Map))].where((x) => x.s < 70).toList()
      ..sort((a, b) => a.s.compareTo(b.s));
    if (bajos.isNotEmpty) {
      partes.add('Áreas que requieren más atención: ${bajos.take(3).map((b) => '${st.nombreAgente(b.k)} (${b.s}/100)').join(', ')}.');
    }
    return partes;
  }

  Future<void> _pdf(BuildContext context, AppState st) async {
    final bytes = await st.descargarInformePdf();
    if (bytes == null) return;
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    try {
      st.toast(await guardarArchivo('Directa_Informe_$hoy.pdf', bytes, 'application/pdf'));
    } catch (e) {
      st.toast('No se pudo guardar el PDF: $e', err: true);
    }
  }

  List<Map<String, dynamic>> _verificaciones(List<Map<String, dynamic>> items) {
    final out = <Map<String, dynamic>>[];
    for (final item in items) {
      if (item['tipo'] == 'chat' && item['verificacion'] is Map) {
        out.add({
          'titulo': '${item['agente'] ?? 'Asistente'} · respuesta',
          'verificacion': Map<String, dynamic>.from(item['verificacion'] as Map),
        });
      }
      if (item['tipo'] == 'analisis' && item['resultado'] is Map) {
        for (final senal in listaDe(item['resultado'] as Map, 'senales')) {
          if (senal['verificacion'] is Map) {
            out.add({
              'titulo': '${item['agente'] ?? 'Agente'} · ${senal['titulo'] ?? 'hallazgo'}',
              'verificacion': Map<String, dynamic>.from(senal['verificacion'] as Map),
            });
          }
        }
      }
    }
    return out;
  }

  bool _tieneVerificacion(Map<String, dynamic> item) {
    if (item['tipo'] == 'chat') return item['verificacion'] is Map;
    if (item['tipo'] == 'analisis' && item['resultado'] is Map) {
      final senales = listaDe(item['resultado'] as Map, 'senales');
      return senales.isNotEmpty && senales.every((s) => s['verificacion'] is Map);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final items = st.itemsInforme;
    final activos = items.where((i) => i['excluido'] != true).toList();
    final ordenados = [...items]..sort((a, b) => st.ordenAgente('${a['agente_key']}').compareTo(st.ordenAgente('${b['agente_key']}')));
    final doc = st.docActivoMap;
    final analisisIncl = activos.where((i) => i['tipo'] == 'analisis' && i['resultado'] is Map).toList();
    final gs = st.scoreGlobal({for (final i in analisisIncl) '${i['agente_key']}': Map<String, dynamic>.from(i['resultado'] as Map)});
    final gi = scoreInfo(context, gs.score);
    final verificaciones = _verificaciones(activos);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead(
        title: 'Informe IA',
        subtitle: 'Prepara un informe para el directorio con contenido revisado y fuentes visibles.',
        actions: [
          if (items.isNotEmpty) GgButton('Vaciar', icon: Icons.delete_outline, ghost: true, onTap: () async {
            if (await confirmar(context, '¿Vaciar los ítems del informe del documento activo?', ok: 'Vaciar')) st.limpiarInforme();
          }),
        ],
      ),
      _PasoInforme(paso: _paso),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: switch (_paso) {
          0 => _contenido(context, st, items, ordenados, activos.length),
          1 => _revision(context, activos, verificaciones, doc),
          _ => _vistaPrevia(context, st, activos, analisisIncl, gs, gi, doc, verificaciones.length),
        },
      ),
      const SizedBox(height: 4),
      _acciones(context, st, activos.isNotEmpty),
    ]);
  }

  Widget _contenido(BuildContext context, AppState st, List<Map<String, dynamic>> items,
      List<Map<String, dynamic>> ordenados, int cantidad) {
    final c = context.c;
    return Column(key: const ValueKey('contenido'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Contenido del informe', style: TextStyle(fontWeight: FontWeight.w700, fontSize: Fs.reading))),
          if (items.isNotEmpty)
            Flexible(
              child: Text('$cantidad de ${items.length} seleccionados', textAlign: TextAlign.end,
                  style: TextStyle(fontSize: Fs.sm, color: c.accentText, fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 4),
        Text('Elige qué análisis y conversaciones se incluirán en el PDF.', style: TextStyle(fontSize: Fs.md, color: c.text2)),
        const SizedBox(height: 12),
        if (items.isNotEmpty) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            GgButton('Seleccionar todos', ghost: true, small: true, onTap: () => st.setTodosExcluidos(false)),
            GgButton('Quitar selección', ghost: true, small: true, onTap: () => st.setTodosExcluidos(true)),
          ]),
          const SizedBox(height: 10),
        ],
        if (items.isEmpty)
          EmptyState(
            icon: Icons.description_outlined,
            title: 'Aún no hay contenido',
            text: 'En Resultados o en el chat, toca "Agregar al informe" en lo que quieras incluir. Luego vuelve aquí para generar el PDF.',
            action: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GgButton('Ir a Resultados', icon: Icons.insights_outlined, ghost: true, expand: true, onTap: () => st.go('resultados')),
              const SizedBox(height: 8),
              GgButton('Ir al chat', icon: Icons.chat_bubble_outline, ghost: true, expand: true, onTap: () => st.go('chat')),
            ]),
          ),
        for (final it in ordenados) _itemContenido(context, st, it),
      ])),
    ]);
  }

  Widget _itemContenido(BuildContext context, AppState st, Map<String, dynamic> it) {
    final c = context.c;
    final chat = it['tipo'] == 'chat';
    final nombre = '${it['agente'] ?? st.nombreAgente('${it['agente_key']}')}';
    final resumen = chat
        ? '${it['pregunta'] ?? 'Conversación'}'
        : plano((it['resultado'] as Map?)?['resumen_ejecutivo']).replaceAll(RegExp(r'\s+'), ' ');
    final registrosVerif = _verificaciones([it]);
    final verif = it['verificacion'] is Map ? it['verificacion'] as Map : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
      color: c.surface2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(color: it['excluido'] == true ? c.border : Brand.accent.withValues(alpha: 0.55)),
      ),
      child: CheckboxListTile(
        value: it['excluido'] != true,
        onChanged: (_) => st.toggleExcluir(it),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        title: Row(children: [
          AgentBadge(st.badgeAgente('${it['agente_key']}')),
          const SizedBox(width: 7),
          Expanded(child: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: Fs.md))),
          Pill(chat ? 'CHAT' : 'ANÁLISIS', fg: c.text2, bg: c.surface3),
        ]),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(resumen.isEmpty ? (chat ? 'Respuesta de conversación' : 'Análisis del agente') : resumen,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: Fs.sm, color: c.text2, height: 1.35)),
            if (registrosVerif.isNotEmpty) ...[
              const SizedBox(height: 5),
              Builder(builder: (context) {
                final estado = verif?['estado'] ?? (registrosVerif.first['verificacion'] as Map)['estado'];
                final info = selloInfo(context, '$estado');
                final etiqueta = verif?['etiqueta'] ?? (registrosVerif.first['verificacion'] as Map)['etiqueta'] ?? info.label;
                return Row(children: [Icon(info.icon, size: 14, color: info.color), const SizedBox(width: 4),
                  Text('$etiqueta', style: TextStyle(fontSize: Fs.xs, color: info.color, fontWeight: FontWeight.w600))]);
              }),
            ],
          ]),
        ),
      ),
      ),
    );
  }

  Widget _revision(BuildContext context, List<Map<String, dynamic>> activos,
      List<Map<String, dynamic>> verificaciones, Map? doc) {
    final c = context.c;
    final sinVerificar = activos.where((item) => !_tieneVerificacion(item)).length;
    return Column(key: const ValueKey('verificacion'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Revisión de evidencia', style: TextStyle(fontWeight: FontWeight.w700, fontSize: Fs.reading)),
        const SizedBox(height: 4),
        Text('Se muestran las verificaciones que ya están registradas en los elementos seleccionados.', style: TextStyle(fontSize: Fs.md, color: c.text2)),
        const SizedBox(height: 12),
        if (verificaciones.isEmpty)
          _AvisoInforme(
            icon: Icons.info_outline,
            color: c.med,
            title: 'No hay verificaciones guardadas',
            text: 'El PDF no marcará estos contenidos como verificados. Revisa las respuestas o señales desde sus módulos antes de compartir el informe.',
          )
        else ...[
          Row(children: [
            Expanded(child: _ResumenVerif(valor: '${verificaciones.length}', titulo: 'Registros con verificación', color: c.low)),
            const SizedBox(width: 8),
            Expanded(child: _ResumenVerif(valor: '$sinVerificar', titulo: 'Elementos con verificación incompleta', color: sinVerificar > 0 ? c.med : c.low)),
          ]),
          const SizedBox(height: 10),
          for (final registro in verificaciones) _filaVerificacion(context, registro),
          if (sinVerificar > 0) ...[
            const SizedBox(height: 6),
            _AvisoInforme(
              icon: Icons.rule_outlined,
              color: c.med,
              title: 'Hay contenido con verificación incompleta',
              text: 'Algunos elementos no tienen un sello para todo su contenido. La ausencia de un sello no significa que esté validado; revisa las fuentes antes de distribuir el PDF.',
            ),
          ],
        ],
      ])),
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Fuentes disponibles', style: TextStyle(fontWeight: FontWeight.w700, fontSize: Fs.lg)),
        const SizedBox(height: 4),
        Text('Las referencias de página se conservarán cuando estén disponibles.', style: TextStyle(fontSize: Fs.sm, color: c.text2)),
        const SizedBox(height: 8),
        for (final item in activos.where((i) => i['tipo'] == 'chat'))
          for (final fuente in (item['fuentes'] as List? ?? const []).whereType<Map>())
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.description_outlined, size: 16, color: c.accentText),
                const SizedBox(width: 8),
                Expanded(child: Text('${fuente['documento'] ?? nombreDoc(doc)} · pág. ${fuente['pagina'] ?? '?'}',
                    style: TextStyle(fontSize: Fs.sm, color: c.text2))),
              ]),
            ),
        if (!activos.any((i) => i['tipo'] == 'chat' && (i['fuentes'] as List? ?? const []).isNotEmpty))
          Text('No hay referencias de página guardadas para los elementos seleccionados.', style: TextStyle(fontSize: Fs.sm, color: c.text3)),
      ])),
    ]);
  }

  Widget _filaVerificacion(BuildContext context, Map<String, dynamic> registro) {
    final c = context.c;
    final v = registro['verificacion'] as Map;
    final info = selloInfo(context, '${v['estado'] ?? ''}');
    final afirmaciones = [for (final a in (v['afirmaciones'] as List? ?? const [])) if (a is Map) Map<String, dynamic>.from(a)];
    return Material(
      color: Colors.transparent,
      child: InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: () => mostrarDetalleVerificacion(context, Map<String, dynamic>.from(v)),
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: c.surface2, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(11)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(info.icon, size: 17, color: info.color), const SizedBox(width: 7),
          Expanded(child: Text('${registro['titulo']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: Fs.md))),
          Text('${v['etiqueta'] ?? info.label}', style: TextStyle(color: info.color, fontSize: Fs.xs, fontWeight: FontWeight.w700)),
        ]),
        if ('${v['resumen'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('${v['resumen']}', style: TextStyle(fontSize: Fs.sm, color: c.text2, height: 1.35)),
        ],
        if (afirmaciones.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('${afirmaciones.length} afirmaciones revisadas', style: TextStyle(fontSize: Fs.xs, color: c.text3)),
          for (final a in afirmaciones.take(2)) ...[
            const SizedBox(height: 6),
            Builder(builder: (context) {
              final estado = estadoAfirmacion(context, '${a['estado_final'] ?? a['estado'] ?? ''}');
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.circle, size: 7, color: estado.color),
                const SizedBox(width: 6),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${a['texto'] ?? 'Afirmación revisada'}', maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: Fs.sm, color: c.text2)),
                  Text('${estado.label}${a['pagina'] != null ? ' · pág. ${a['pagina']}' : ''}',
                      style: TextStyle(fontSize: Fs.xs, color: estado.color)),
                  if ('${a['cita'] ?? ''}'.isNotEmpty)
                    Text('«${a['cita']}»', maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: Fs.xs, color: c.text3, fontStyle: FontStyle.italic)),
                ])),
              ]);
            }),
          ],
        ],
        const SizedBox(height: 5),
        Text('Toca para ver el detalle completo', style: TextStyle(fontSize: Fs.xs, color: c.text3)),
      ]),
      ),
      ),
    );
  }

  Widget _vistaPrevia(BuildContext context, AppState st, List<Map<String, dynamic>> activos,
      List<Map<String, dynamic>> analisisIncl, ({int score, int n, int sinInfo}) gs, ({Color color, String label}) gi,
      Map? doc, int registrosVerif) {
    final c = context.c;
    final resumen = _resumen(st, activos);
    final nombre = nombreDoc(doc).isEmpty ? 'Documento de trabajo' : nombreDoc(doc);
    return Column(key: const ValueKey('vista'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(padding: const EdgeInsets.all(8), child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.border)),
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFF23354A)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 9, height: 26, decoration: BoxDecoration(color: Brand.accent, borderRadius: BorderRadius.circular(5))),
              const SizedBox(width: 8),
              const Text('DIRECTA', style: TextStyle(fontSize: Fs.sm, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const Spacer(),
              const Text('GERENCIA GENERAL', style: TextStyle(fontSize: Fs.xxs, letterSpacing: 0.8)),
            ]),
            const SizedBox(height: 18),
            const Text('INFORME EJECUTIVO', style: TextStyle(fontSize: Fs.xxs, color: Color(0xFF23869A), fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 5),
            const Text('Informe de Preparación\nPre-Directorio', style: TextStyle(fontSize: Fs.xxl, height: 1.12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: Fs.xs, color: Color(0xFF687586))),
            const Divider(height: 20),
            if (analisisIncl.isNotEmpty) ...[
              Row(children: [
                Expanded(child: _DatoVista(valor: '${gs.score}/100', titulo: 'Preparación global', detalle: gi.label)),
                const SizedBox(width: 8),
                Expanded(child: _DatoVista(valor: '${analisisIncl.length}', titulo: 'Análisis incluidos', detalle: 'por agente')),
              ]),
              const SizedBox(height: 12),
            ],
            const Text('RESUMEN EJECUTIVO', style: TextStyle(fontSize: Fs.xxs, color: Color(0xFF23869A), fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 5),
            Text(resumen.isEmpty ? 'El informe incluirá las conversaciones seleccionadas y sus fuentes.' : resumen.first,
                maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: Fs.reading, height: Fs.alturaLectura)),
            const SizedBox(height: 13),
            const Text('CONTENIDO', style: TextStyle(fontSize: Fs.xxs, color: Color(0xFF23869A), fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 5),
            for (final seccion in _secciones(activos))
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $seccion', style: const TextStyle(fontSize: Fs.body, height: 1.5))),
            const SizedBox(height: 10),
            Text('$registrosVerif verificaciones registradas · Las fuentes y páginas se incluyen cuando están disponibles.',
                style: const TextStyle(fontSize: Fs.xxs, color: Color(0xFF687586), height: 1.35)),
          ]),
        ),
      )),
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Antes de descargar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: Fs.lg)),
        const SizedBox(height: 7),
        _ChecklistInforme(texto: '${activos.length} contenidos seleccionados', ok: activos.isNotEmpty),
        _ChecklistInforme(texto: 'Verificación de afirmaciones revisada', ok: registrosVerif > 0),
        _ChecklistInforme(texto: 'Fuente: $nombre', ok: doc != null),
        const SizedBox(height: 4),
        Text('Esta vista resume la estructura. El PDF se genera con el contenido completo y puede tener más páginas.',
            style: TextStyle(fontSize: Fs.sm, color: c.text3, height: 1.35)),
      ])),
    ]);
  }

  List<String> _secciones(List<Map<String, dynamic>> activos) {
    final out = <String>[];
    if (activos.any((i) => i['tipo'] == 'analisis')) out.add('Hallazgos y análisis por agente');
    if (activos.any((i) => i['tipo'] == 'chat')) out.add('Conversaciones y respuestas seleccionadas');
    if (activos.any((i) => i['tipo'] == 'chat' && (i['fuentes'] as List? ?? const []).isNotEmpty)) out.add('Fuentes consultadas y páginas');
    if (out.isEmpty) out.add('Contenido del documento');
    return out;
  }

  Widget _acciones(BuildContext context, AppState st, bool haySeleccion) {
    if (_paso == 0) {
      return GgButton('Continuar a verificación', icon: Icons.arrow_forward, expand: true,
          onTap: haySeleccion ? () => setState(() => _paso = 1) : null);
    }
    if (_paso == 1) {
      return Row(children: [
        Expanded(child: GgButton('Volver', icon: Icons.arrow_back, ghost: true, onTap: () => setState(() => _paso = 0))),
        const SizedBox(width: 8),
        Expanded(child: GgButton('Vista previa', icon: Icons.arrow_forward, onTap: haySeleccion ? () => setState(() => _paso = 2) : null)),
      ]);
    }
    return Row(children: [
      Expanded(child: GgButton('Verificación', icon: Icons.arrow_back, ghost: true, onTap: () => setState(() => _paso = 1))),
      const SizedBox(width: 8),
      Expanded(child: GgButton(st.generandoPdf ? 'Generando…' : 'Descargar PDF', icon: Icons.picture_as_pdf_outlined,
          loading: st.generandoPdf, onTap: haySeleccion && !st.generandoPdf ? () => _pdf(context, st) : null)),
    ]);
  }
}

class _PasoInforme extends StatelessWidget {
  const _PasoInforme({required this.paso});
  final int paso;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const labels = ['Contenido', 'Verificación', 'Vista previa'];
    return GgCard(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), child: Row(children: [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) Expanded(child: Container(height: 2, color: i <= paso ? Brand.accent : c.border)),
        Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 13, backgroundColor: i <= paso ? Brand.accent : c.surface3,
            child: Text(i < paso ? '✓' : '${i + 1}', style: TextStyle(fontSize: Fs.xs, fontWeight: FontWeight.w700, color: i <= paso ? Brand.onAccent : c.text3))),
          const SizedBox(height: 5),
          Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: Fs.xs, fontWeight: i == paso ? FontWeight.w700 : FontWeight.w500,
            color: i == paso ? c.accentText : c.text3)),
        ])),
      ],
    ]));
  }
}

class _AvisoInforme extends StatelessWidget {
  const _AvisoInforme({required this.icon, required this.color, required this.title, required this.text});
  final IconData icon;
  final Color color;
  final String title, text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11), border: Border.all(color: color.withValues(alpha: 0.45))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 19), const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: color, fontSize: Fs.md, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3), Text(text, style: TextStyle(color: context.c.text2, fontSize: Fs.sm, height: 1.4)),
      ])),
    ]),
  );
}

class _ResumenVerif extends StatelessWidget {
  const _ResumenVerif({required this.valor, required this.titulo, required this.color});
  final String valor, titulo;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(valor, style: TextStyle(color: color, fontSize: Fs.xxl, fontWeight: FontWeight.w700)),
      Text(titulo, style: TextStyle(color: context.c.text2, fontSize: Fs.xs, height: 1.25)),
    ]),
  );
}

class _DatoVista extends StatelessWidget {
  const _DatoVista({required this.valor, required this.titulo, required this.detalle});
  final String valor, titulo, detalle;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(color: const Color(0xFFF1F5F8), borderRadius: BorderRadius.circular(6)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(valor, style: const TextStyle(fontSize: Fs.reading, fontWeight: FontWeight.w800, color: Color(0xFF23354A))),
      Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: Fs.xxs, color: Color(0xFF405266))),
      Text(detalle, style: const TextStyle(fontSize: Fs.xxs, color: Color(0xFF687586))),
    ]),
  );
}

class _ChecklistInforme extends StatelessWidget {
  const _ChecklistInforme({required this.texto, required this.ok});
  final String texto;
  final bool ok;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(ok ? Icons.check_circle_outline : Icons.info_outline, size: 17, color: ok ? context.c.low : context.c.med),
      const SizedBox(width: 7), Expanded(child: Text(texto, style: TextStyle(fontSize: Fs.sm, color: context.c.text2))),
    ]),
  );
}
