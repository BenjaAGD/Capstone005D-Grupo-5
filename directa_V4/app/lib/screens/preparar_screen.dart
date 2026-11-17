import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/sev.dart';
import '../core/theme.dart';
import '../core/saver.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/demo_offline.dart';

/// Preguntas probables del directorio y respuestas sugeridas para el Gerente General.
class PrepararScreen extends StatefulWidget {
  const PrepararScreen({super.key});
  @override
  State<PrepararScreen> createState() => _PrepararScreenState();
}

class _PrepararScreenState extends State<PrepararScreen> {
  int _tab = 1;
  String? _preguntaAbierta;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().cargarPreparacion());
  }

  Future<void> _exportarRespuestas(AppState st) async {
    st.toast('Generando PDF de respuestas…');
    final bytes = await st.descargarRespuestasPreparacionPdf();
    if (bytes == null || !mounted) return;
    final fecha = DateTime.now().toIso8601String().substring(0, 10);
    try {
      st.toast(await guardarArchivo('DIRECTA_Respuestas_Reunion_$fecha.pdf', bytes, 'application/pdf'));
    } catch (e) {
      st.toast('No se pudo guardar el PDF: $e', err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final items = st.prepPreguntas;
    final sugeridas = items.where((x) => x['sugerida'] is Map).toList();
    final sinSugerir = items.length - sugeridas.length;

    if (st.docActivo == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHead(title: 'Preparar mi reunión', subtitle: 'Revisa las preguntas clave antes de una sesión.'),
        const DemoAviso(text: 'Las preguntas se basarán en los hallazgos de tus documentos cuando cargues uno.'),
        const DemoFila(titulo: 'Rentabilidad', detalle: '¿Qué explica la diferencia entre los resultados y el margen?', icon: Icons.trending_down),
        const DemoFila(titulo: 'Inversión', detalle: '¿Qué hitos y retorno se esperan del CAPEX planificado?', icon: Icons.account_balance),
        const DemoFila(titulo: 'Seguridad operacional', detalle: '¿Qué controles críticos siguen abiertos?', icon: Icons.health_and_safety_outlined),
      ]);
    }
    if (st.analisis == null && !st.cargandoAnalisis) {
      return Column(children: [
        const PageHead(title: 'Preparar mi reunión'),
        GgCard(child: EmptyState(
          icon: Icons.event_note_outlined,
          title: 'Primero sube y analiza un documento',
          text: 'Las preguntas probables del directorio se generan a partir de los hallazgos de los agentes.',
          action: GgButton('Ir a Documentos', icon: Icons.upload_file, onTap: () {
            Navigator.of(context).maybePop();
            st.go('docs');
          }),
        )),
      ]);
    }

    Map<String, dynamic>? abierta;
    if (_preguntaAbierta != null) {
      for (final it in items) {
        if ('${it['id']}' == _preguntaAbierta) abierta = it;
      }
      if (abierta == null) _preguntaAbierta = null;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (abierta != null)
        _detallePregunta(st, abierta)
      else ...[
        const PageHead(
          title: 'Preparar mi reunión',
          subtitle: 'Revisa las preguntas clave y sus respuestas sugeridas.',
        ),
        _documentoActivo(st),
        const SizedBox(height: 4),
        _selectorPestanas(),
        const SizedBox(height: 14),
        if (st.cargandoPrep && items.isEmpty)
          const GgCard(child: EmptyState(icon: Icons.hourglass_empty, title: 'Cargando preguntas…', loading: true))
        else if (items.isEmpty)
          const GgCard(child: EmptyState(icon: Icons.check_circle_outline, title: 'Aún no hay preguntas',
              text: 'Cuando el análisis termine, aquí aparecerán los temas que conviene preparar.'))
        else if (_tab == 0)
          _resumen(st, items, sugeridas.length)
        else if (_tab == 1)
          _listaPreguntas(st, items, sinSugerir)
        else
          _listaRespuestas(st, sugeridas),
      ],
    ]);
  }

  Widget _documentoActivo(AppState st) {
    final c = context.c;
    final nombre = nombreDoc(st.docActivoMap);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
      child: Row(children: [
        Icon(Icons.description_outlined, size: 18, color: c.accentText),
        const SizedBox(width: 8),
        Expanded(child: Text(nombre.isEmpty ? 'Documento activo' : nombre,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.text2))),
      ]),
    );
  }

  Widget _selectorPestanas() {
    final c = context.c;
    const labels = ['Resumen', 'Preguntas', 'Respuestas'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(child: Material(
            color: _tab == i ? c.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => setState(() => _tab = i),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Text(labels[i], textAlign: TextAlign.center, maxLines: 1,
                  style: TextStyle(fontSize: 12.5, fontWeight: _tab == i ? FontWeight.w700 : FontWeight.w500,
                    color: _tab == i ? c.accentText : c.text2))),
            ),
          )),
      ]),
    );
  }

  Widget _resumen(AppState st, List<Map<String, dynamic>> items, int respuestas) {
    final c = context.c;
    final senales = st.prepSenales.take(3).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Tu preparación', bottom: 12),
        Row(children: [
          Expanded(child: _datoResumen('${items.length}', 'preguntas clave')),
          Container(width: 1, height: 42, color: c.border),
          Expanded(child: _datoResumen('$respuestas', 'respuestas sugeridas')),
        ]),
      ])),
      if (senales.isNotEmpty) GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Temas prioritarios', bottom: 10),
        for (var i = 0; i < senales.length; i++) ...[
          if (i > 0) Divider(height: 16, color: c.border),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SevPill(normSev(senales[i]['severidad'])),
            const SizedBox(width: 9),
            Expanded(child: Text('${senales[i]['titulo'] ?? 'Tema por revisar'}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35))),
          ]),
        ],
      ])),
      GgButton('Revisar preguntas', icon: Icons.arrow_forward, expand: true, onTap: () => setState(() => _tab = 1)),
    ]);
  }

  Widget _datoResumen(String valor, String etiqueta) {
    final c = context.c;
    return Column(children: [
      Text(valor, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: c.text)),
      const SizedBox(height: 3),
      Text(etiqueta, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: c.text3)),
    ]);
  }

  Widget _listaPreguntas(AppState st, List<Map<String, dynamic>> items, int sinSugerir) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('${items.length} preguntas · ordenadas por prioridad',
          style: TextStyle(fontSize: 12, color: c.text3))),
        IconButton(tooltip: 'Actualizar preguntas', visualDensity: VisualDensity.compact,
          onPressed: st.cargandoPrep ? null : () => st.cargarPreparacion(forzar: true),
          icon: Icon(Icons.refresh, size: 20, color: c.text2)),
      ]),
      if (sinSugerir > 0) ...[
        GgButton(st.generandoPrep ? 'Generando respuestas…' : 'Sugerir respuestas ($sinSugerir)',
          icon: Icons.auto_awesome, loading: st.generandoPrep, expand: true,
          onTap: st.generandoPrep ? null : st.generarRespuestasSugeridas),
        const SizedBox(height: 10),
      ],
      for (final it in items) _tarjetaLista(it, st),
    ]);
  }

  Widget _listaRespuestas(AppState st, List<Map<String, dynamic>> sugeridas) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (sugeridas.isNotEmpty) ...[
        Text('${sugeridas.length} respuestas disponibles', style: TextStyle(fontSize: 12, color: context.c.text3)),
        const SizedBox(height: 10),
        for (final it in sugeridas) _tarjetaLista(it, st),
        const SizedBox(height: 2),
        GgButton(st.generandoPdf ? 'Generando PDF…' : 'Exportar respuestas a PDF',
          icon: Icons.picture_as_pdf_outlined, loading: st.generandoPdf, expand: true,
          onTap: st.generandoPdf ? null : () => _exportarRespuestas(st)),
      ] else
        GgCard(child: EmptyState(icon: Icons.auto_awesome_outlined, title: 'Todavía no hay respuestas',
          text: 'Genera sugerencias para revisar respuestas basadas en el documento.',
          action: GgButton(st.generandoPrep ? 'Generando…' : 'Sugerir respuestas', icon: Icons.auto_awesome,
            loading: st.generandoPrep, onTap: st.generandoPrep ? null : st.generarRespuestasSugeridas))),
    ]);
  }

  Widget _tarjetaLista(Map<String, dynamic> it, AppState st) {
    final c = context.c;
    final sugerida = it['sugerida'] as Map?;
    final respuesta = '${sugerida?['respuesta'] ?? ''}'.trim();
    return GgCard(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      onTap: () => setState(() => _preguntaAbierta = '${it['id']}'),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SevPill(normSev(it['severidad'])),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(st.nombreAgente('${it['agente']}'), style: TextStyle(fontSize: 11.5, color: c.text3)),
          const SizedBox(height: 4),
          Text('${it['pregunta'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35)),
          if (respuesta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(respuesta, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.text2, height: 1.35)),
          ],
        ])),
        const SizedBox(width: 5),
        Icon(Icons.chevron_right, color: c.text3),
      ]),
    );
  }

  Widget _detallePregunta(AppState st, Map<String, dynamic> it) {
    final c = context.c;
    final sug = it['sugerida'] as Map?;
    final verif = sug?['verificacion'] as Map?;
    final estado = '${verif?['estado'] ?? ''}';
    final verificado = estado == 'cifras_ok' || estado == 'verificada';
    final verifColor = verificado ? c.low : c.med;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextButton.icon(onPressed: () => setState(() => _preguntaAbierta = null),
        icon: const Icon(Icons.arrow_back, size: 18), label: const Text('Volver a preguntas'),
        style: TextButton.styleFrom(foregroundColor: c.accentText, padding: EdgeInsets.zero)),
      const PageHead(title: 'Respuesta sugerida', subtitle: 'Revisa la fuente y confirma los datos antes de usarla.'),
      Row(children: [SevPill(normSev(it['severidad'])), const SizedBox(width: 8),
        Expanded(child: Text(st.nombreAgente('${it['agente']}'), style: TextStyle(fontSize: 12, color: c.text3)))]),
      const SizedBox(height: 10),
      GgCard(padding: const EdgeInsets.all(13), child: Text('${it['pregunta'] ?? ''}',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.4))),
      if (sug == null)
        GgCard(child: EmptyState(icon: Icons.auto_awesome_outlined, title: 'Aún no hay respuesta sugerida',
          text: 'Puedes generar una respuesta a partir del documento y revisarla aquí.',
          action: GgButton(st.generandoPrep ? 'Generando…' : 'Sugerir respuesta', icon: Icons.auto_awesome,
            loading: st.generandoPrep, onTap: st.generandoPrep ? null : st.generarRespuestasSugeridas)))
      else ...[
        GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Respuesta sugerida', bottom: 8),
          MarkdownLite('${sug['respuesta'] ?? ''}', size: 13.5),
          if ('${sug['falta'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Pendiente: ${sug['falta']}', style: TextStyle(fontSize: 12, color: c.med, height: 1.4)),
          ],
        ])),
        GgCard(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(verificado ? Icons.verified_outlined : Icons.rule, size: 19, color: verifColor),
            const SizedBox(width: 7),
            Expanded(child: Text(verif == null ? 'Verificación no disponible' : '${verif['etiqueta'] ?? 'Verificación'}',
              style: TextStyle(fontWeight: FontWeight.w700, color: verifColor))),
          ]),
          if ('${verif?['resumen'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${verif?['resumen']}', style: TextStyle(fontSize: 12.5, color: c.text2, height: 1.4)),
          ] else if (verif == null) ...[
            const SizedBox(height: 6),
            Text('Confirma la respuesta y sus cifras directamente en el documento antes de usarla.',
              style: TextStyle(fontSize: 12.5, color: c.text2, height: 1.4)),
          ],
        ])),
        for (final alerta in (sug['alertas'] as List? ?? const []))
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('• $alerta', style: TextStyle(fontSize: 12, color: c.med))),
      ],
      const SizedBox(height: 4),
      Wrap(spacing: 8, runSpacing: 8, children: [
        GgButton('Preguntar al agente', icon: Icons.chat_bubble_outline, small: true, ghost: true, onTap: () {
          Navigator.of(context).maybePop();
          st.preguntarEnChat('${it['agente']}', '${it['pregunta']}');
        }),
        GgButton('Agregar al informe', icon: Icons.add, small: true, onTap: () => st.prepAlInforme(it)),
      ]),
    ]);
  }
}
