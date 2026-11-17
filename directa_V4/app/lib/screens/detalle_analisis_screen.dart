import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class DetalleAnalisisScreen extends StatefulWidget {
  const DetalleAnalisisScreen({super.key});

  @override
  State<DetalleAnalisisScreen> createState() => _DetalleAnalisisScreenState();
}

class _DetalleAnalisisScreenState extends State<DetalleAnalisisScreen> {
  bool soloProblemas = false;
  Timer? _poll;
  String? _documentoCargado;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted) return;
      final st = context.read<AppState>();
      await st.cargarDiagnosticos();
      if (!['analisis', 'embeddings', 'iniciando'].contains(st.diagnosticoFase)) return;
      await st.cargarDocumentos(silencioso: true);
      final doc = st.docActivoMap;
      if (doc != null && !estadosProcesando.contains(doc['estado'])) {
        await st.cargarAnalisis('${doc['id']}');
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c = context.c;
    if (_documentoCargado != st.docActivo) {
      _documentoCargado = st.docActivo;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) st.cargarDiagnosticos();
      });
    }
    final agentes = [...st.agentes]..sort((a, b) => a.ola.compareTo(b.ola));
    final porAgente = {for (final item in st.diagnosticosAgentes) '${item['agente']}': item};
    final filas = <Map<String, dynamic>>[];
    for (final agente in agentes) {
      final registro = porAgente[agente.key] ?? const <String, dynamic>{};
      final exito = st.analisis?.containsKey(agente.key) == true || registro['estado'] == 'listo';
      final estado = exito ? 'listo' : '${registro['estado'] ?? 'pendiente'}';
      if (soloProblemas && (estado == 'listo' || estado == 'pendiente')) continue;
      filas.add({'agente': agente, 'registro': registro, 'estado': estado});
    }
    final ok = st.agentes.where((a) => st.analisis?.containsKey(a.key) == true || porAgente[a.key]?['estado'] == 'listo').length;
    final errores = filas.where((f) => f['estado'] == 'error' || f['estado'] == 'sin_detalle').length;
    final evidencia = filas.where((f) => f['estado'] == 'sin_evidencia').length;
    final pendientes = math.max(0, st.totalAgentes - ok - errores - evidencia);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead(
        title: 'Detalle del análisis',
        subtitle: 'Revisa qué ocurrió con cada agente y reintenta los errores técnicos.',
      ),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nombreDoc(st.docActivoMap).isEmpty ? 'Documento activo' : nombreDoc(st.docActivoMap),
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: st.totalAgentes == 0 ? 0 : ok / st.totalAgentes,
              minHeight: 8,
              backgroundColor: c.track,
              color: c.low,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Conteo(texto: '$ok listos', color: c.low),
            if (errores > 0) _Conteo(texto: '$errores con error', color: c.high),
            if (evidencia > 0) _Conteo(texto: '$evidencia sin fragmentos', color: c.med),
            if (pendientes > 0) _Conteo(texto: '$pendientes pendientes', color: c.text3),
          ]),
          const SizedBox(height: 10),
          Text('Un agente sin fragmentos significa que no recuperó texto útil para analizar. No necesariamente indica un error del servidor.',
              style: TextStyle(fontSize: 12, color: c.text2, height: 1.4)),
        ]),
      ),
      GgCard(
        padding: const EdgeInsets.all(5),
        child: Row(children: [
          Expanded(child: _Filtro(text: 'Todos (${st.totalAgentes})', active: !soloProblemas,
              onTap: () => setState(() => soloProblemas = false))),
          Expanded(child: _Filtro(text: 'Con problemas (${errores + evidencia})', active: soloProblemas,
              onTap: () => setState(() => soloProblemas = true))),
        ]),
      ),
      if (st.docActivo == null)
        const GgCard(child: Text('Selecciona primero un documento en la barra superior.'))
      else if (st.cargandoDiagnosticos && st.diagnosticosAgentes.isEmpty)
        const GgCard(child: Center(child: CircularProgressIndicator()))
      else if (filas.isEmpty)
        GgCard(child: Text(soloProblemas ? 'No hay agentes con problemas registrados.' : 'No hay agentes para mostrar.',
            style: TextStyle(color: c.text2)))
      else
        for (final fila in filas)
          _AgenteCard(
            nombre: (fila['agente'] as Agente).name,
            estado: '${fila['estado']}',
            registro: Map<String, dynamic>.from(fila['registro'] as Map),
            onRetry: () => st.reintentarAgentes(),
          ),
      if (soloProblemas && errores > 0)
        Align(alignment: Alignment.centerLeft, child: GgButton(
          'Reintentar agentes con error', icon: Icons.refresh,
          onTap: st.reintentarAgentes,
        )),
    ]);
  }
}

class _Conteo extends StatelessWidget {
  const _Conteo({required this.texto, required this.color});
  final String texto;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
        child: Text(texto, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}

class _Filtro extends StatelessWidget {
  const _Filtro({required this.text, required this.active, required this.onTap});
  final String text;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
        decoration: BoxDecoration(color: active ? c.accentSoft : Colors.transparent, borderRadius: BorderRadius.circular(10)),
        child: Center(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: active ? c.accentText : c.text2))),
      ),
    );
  }
}

class _AgenteCard extends StatelessWidget {
  const _AgenteCard({required this.nombre, required this.estado, required this.registro, required this.onRetry});
  final String nombre, estado;
  final Map<String, dynamic> registro;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = switch (estado) {
      'sin_evidencia' => c.med,
      'listo' => c.low,
      'pendiente' => c.info,
      _ => c.high,
    };
    final etiqueta = switch (estado) {
      'sin_evidencia' => 'Sin fragmentos',
      'listo' => 'Análisis listo',
      'pendiente' => 'Pendiente',
      'sin_detalle' => 'Sin diagnóstico guardado',
      _ => 'Error de análisis',
    };
    return GgCard(
      borderColor: color.withValues(alpha: .55),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
          _Conteo(texto: etiqueta, color: color),
        ]),
        if (registro['codigo_error'] != null) ...[
          const SizedBox(height: 10),
          Text('Código: ${registro['codigo_error']}', style: TextStyle(color: c.accentText, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
        if (registro['mensaje'] != null && '${registro['mensaje']}'.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text('${registro['mensaje']}', style: TextStyle(fontSize: 12, color: c.text2, height: 1.4)),
        ],
        if (registro['intentos'] != null && (registro['intentos'] as num).toInt() > 0) ...[
          const SizedBox(height: 6),
          Text('Intentos: ${registro['intentos']}', style: TextStyle(fontSize: 11, color: c.text3)),
        ],
        if (registro['reintentable'] == true) ...[
          const SizedBox(height: 8),
          TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 17), label: const Text('Reintentar análisis')),
        ],
      ]),
    );
  }
}
