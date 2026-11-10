import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/saver.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Inicio con una sola acción principal (Frente E): según el estado, subir un documento o preparar la reunión.
/// Las cifras clave van en una franja compacta arriba y lo demás son atajos de un toque.
class InicioScreen extends StatelessWidget {
  const InicioScreen({super.key});

  Future<void> _pdfDirecto(BuildContext context, AppState st) async {
    final bytes = await st.informeDirecto();
    if (bytes == null) return;
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    st.toast(await guardarArchivo('Directa_Informe_$hoy.pdf', bytes, 'application/pdf'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final doc = st.docActivoMap;
    final nDocs = st.documentos.length;
    final nAnalisis = st.analisis?.length ?? 0;
    final t = st.totalAgentes;
    final cont = st.analisis == null ? null : st.conteoSeveridad(st.analisis!);
    final graves = cont == null ? 0 : (cont['crítica'] ?? 0) + (cont['alta'] ?? 0);
    final procesando = doc != null && estadosProcesando.contains(doc['estado']);
    final nInforme = st.itemsInforme.length;

    // Acción principal según el estado
    final ({String titulo, String texto, IconData icono, VoidCallback onTap, String boton}) principal;
    if (nDocs == 0) {
      principal = (titulo: 'Sube el primer documento', texto: 'PDF, Word o Excel. Se indexa y los $t agentes lo analizan solos.',
          icono: Icons.upload_file, onTap: () => st.go('docs'), boton: 'Subir documento');
    } else if (procesando || st.subiendo) {
      principal = (titulo: 'Analizando el documento…', texto: 'Los agentes están trabajando. Puedes seguir el avance en Documentos.',
          icono: Icons.hourglass_top, onTap: () => st.go('docs'), boton: 'Ver avance');
    } else if (nAnalisis == 0) {
      principal = (titulo: 'Este documento no tiene análisis', texto: 'Elige otro documento o vuelve a subirlo para analizarlo.',
          icono: Icons.description_outlined, onTap: () => st.go('docs'), boton: 'Ir a Documentos');
    } else {
      principal = (titulo: 'Preparar mi reunión', texto: graves > 0
              ? 'Hay $graves señal${graves == 1 ? '' : 'es'} grave${graves == 1 ? '' : 's'}. Revisa lo que te preguntará el directorio y cómo responder.'
              : 'Revisa las preguntas probables del directorio y cómo responderlas.',
          icono: Icons.event_note_outlined, onTap: () => st.go('preparar'), boton: 'Preparar mi reunión');
    }

    final pasos = [
      ('Cargar', nDocs > 0),
      ('Analizar', nAnalisis > 0),
      ('Preguntar', st.mensajes.isNotEmpty),
      ('Informe', nInforme > 0),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Gerencia General', style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w600, color: c.text3)),
      const SizedBox(height: 4),
      const Text('Bienvenido al módulo de Gerencia General', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
      const SizedBox(height: 4),
      Text(doc == null ? 'Sin documento activo' : 'Documento activo: ${nombreDoc(doc)}',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.text2)),
      const SizedBox(height: 16),
      const BackendAviso(),
      KpiStrip(items: [
        (valor: '$nDocs', etiqueta: 'Documentos', color: null, onTap: () => st.go('docs')),
        (valor: '$nAnalisis/$t', etiqueta: 'Agentes con resultado', color: null, onTap: () => st.go('resultados')),
        (valor: '$graves', etiqueta: 'Señales graves', color: graves > 0 ? c.high : null, onTap: () => st.go('resultados')),
        (valor: '$nInforme', etiqueta: 'En el informe', color: null, onTap: () => st.go('informe')),
      ]),
      // Acción principal (una sola por pantalla)
      GgCard(
        borderColor: Brand.accent,
        gradient: LinearGradient(colors: [c.accentSoft, c.surface], stops: const [0, 0.75]),
        onTap: principal.onTap,
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: Brand.accent, borderRadius: BorderRadius.circular(14)),
            child: Icon(principal.icono, color: Brand.onAccent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(principal.titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(principal.texto, style: TextStyle(fontSize: 12.5, color: c.text2, height: 1.4)),
              const SizedBox(height: 8),
              Text('${principal.boton} →', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.accentText)),
            ]),
          ),
        ]),
      ),
      const SecTitle('Atajos'),
      GridCols(cols: 2, gap: 8, minItemWidth: 150, children: [
        _Atajo(icono: Icons.picture_as_pdf_outlined, texto: 'Informe PDF directo', detalle: 'Todo el análisis, en un toque',
            cargando: st.generandoPdf, onTap: nAnalisis == 0 ? null : () => _pdfDirecto(context, st)),
        _Atajo(icono: Icons.chat_bubble_outline, texto: 'Preguntar a un agente',
            detalle: st.agenteActual == 'general' ? 'Asistente general' : st.nombreAgente(st.agenteActual),
            onTap: () => st.go('chat')),
        _Atajo(icono: Icons.insights_outlined, texto: 'Resultados', detalle: 'Señales y puntaje por área', onTap: () => st.go('resultados')),
        _Atajo(icono: Icons.menu_book_outlined, texto: 'Memoria anual', detalle: 'Borrador con el tono de la empresa', onTap: () => st.go('memoria')),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        for (var i = 0; i < pasos.length; i++) ...[
          if (i > 0) Expanded(child: Container(height: 2, color: pasos[i - 1].$2 ? c.low : c.border)),
          Column(children: [
            Container(
              width: 24, height: 24, alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: pasos[i].$2 ? c.low : c.surface3),
              child: pasos[i].$2
                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                  : Text('${i + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.text2)),
            ),
            const SizedBox(height: 4),
            Text(pasos[i].$1, style: TextStyle(fontSize: 10.5, color: c.text3)),
          ]),
        ],
      ]),
    ]);
  }
}

class _Atajo extends StatelessWidget {
  const _Atajo({required this.icono, required this.texto, required this.detalle, this.onTap, this.cargando = false});
  final IconData icono;
  final String texto, detalle;
  final VoidCallback? onTap;
  final bool cargando;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: GgCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(12),
        onTap: cargando ? null : onTap,
        child: Row(children: [
          cargando
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icono, size: 20, color: c.accentText),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Text(detalle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.text3)),
            ]),
          ),
        ]),
      ),
    );
  }
}
