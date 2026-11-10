import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Aprendizaje de los agentes (Frente C2): valoraciones del gerente y lecciones por agente.
/// Ninguna lección se aplica sin que una persona la pruebe y la apruebe; todas se pueden revertir.
class AprendizajeScreen extends StatefulWidget {
  const AprendizajeScreen({super.key});
  @override
  State<AprendizajeScreen> createState() => _AprendizajeScreenState();
}

class _AprendizajeScreenState extends State<AprendizajeScreen> {
  Map<String, dynamic>? resumen, estado;
  List<Map<String, dynamic>> lecciones = [];
  bool cargando = true, generando = false;
  final Set<String> ocupadas = {};
  final Map<String, String> progresoPrueba = {};
  String? error;

  AppState get st => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    try {
      final r = await st.api.getJson('/api/valoraciones/resumen');
      final l = await st.api.getJson('/api/lecciones');
      final e = await st.api.getJson('/api/estado');
      resumen = r['ok'] == true ? Map<String, dynamic>.from(r) : null;
      lecciones = [for (final x in (l['lecciones'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
      estado = e is Map ? Map<String, dynamic>.from(e) : null;
      error = r['ok'] == true ? null : '${r['error']}';
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => cargando = false);
  }

  Future<void> _generar([String? agente]) async {
    setState(() => generando = true);
    try {
      final r = await st.api.postJson('/api/lecciones/generar', {'agente': ?agente});
      if (r['ok'] != true) throw Exception(r['error']);
      final n = (r['creadas'] as List? ?? const []).length;
      final om = [for (final o in (r['omitidas'] as List? ?? const [])) if (o is Map) '${st.nombreAgente('${o['agente']}')}: ${o['motivo']}'];
      st.toast(n > 0 ? '$n lecciones nuevas para revisar' : (om.isEmpty ? 'No hay valoraciones suficientes' : om.first), err: n == 0);
      await _cargar();
    } catch (e) {
      st.toast('No se pudieron generar: ${e.toString().replaceFirst('Exception: ', '')}', err: true);
    }
    if (mounted) setState(() => generando = false);
  }

  Future<void> _accion(Map<String, dynamic> l, String accion, {Map<String, dynamic>? cuerpo}) async {
    final id = '${l['id']}';
    setState(() => ocupadas.add(id));
    try {
      final r = await st.api.postJson('/api/lecciones/$id/$accion', cuerpo ?? {});
      if (r['ok'] != true) throw Exception(r['error']);
      if (accion == 'probar') {
        await _seguirPrueba(id, '${r['job_id']}');
      } else {
        st.toast(switch (accion) {
          'aprobar' => 'Lección aprobada: el agente la usará desde ahora',
          'rechazar' => 'Lección rechazada',
          'revertir' => 'Lección revertida: el agente deja de usarla',
          _ => 'Lección actualizada',
        });
      }
      await _cargar();
    } catch (e) {
      st.toast(e.toString().replaceFirst('Exception: ', ''), err: true);
    }
    if (mounted) setState(() => ocupadas.remove(id));
  }

  Future<void> _seguirPrueba(String id, String job) async {
    for (var i = 0; i < 240; i++) {
      await Future.delayed(const Duration(seconds: 2));
      final e = await st.api.getJson('/api/lecciones-prueba/$job');
      if (!mounted) return;
      setState(() => progresoPrueba[id] = 'Probando ${e['hechas'] ?? 0} de ${e['total'] ?? '?'} preguntas…');
      if (e['corriendo'] != true) {
        progresoPrueba.remove(id);
        if (e['error'] != null) throw Exception(e['error']);
        st.toast('${(e['resultado'] as Map?)?['conclusion'] ?? 'Prueba terminada'}', err: (e['resultado'] as Map?)?['empeora'] == true);
        return;
      }
    }
  }

  Future<void> _editar(Map<String, dynamic> l) async {
    final ctrl = TextEditingController(text: '${l['texto']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar lección'),
        content: TextField(controller: ctrl, minLines: 2, maxLines: 5, decoration: const InputDecoration(hintText: 'Criterio de estilo o de método, sin cifras')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) await _accion(l, 'editar', cuerpo: {'texto': ctrl.text});
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = context.watch<AppState>();
    if (cargando) return const GgCard(child: EmptyState(icon: Icons.hourglass_empty, title: 'Cargando…', loading: true));
    final porAgente = Map<String, dynamic>.from((resumen?['por_agente'] as Map?) ?? {});
    final motivos = Map<String, dynamic>.from((resumen?['motivos'] as Map?) ?? {});
    final pendientes = lecciones.where((l) => l['estado'] == 'pendiente').toList();
    final aprobadas = lecciones.where((l) => l['estado'] == 'aprobada').toList();
    final historial = lecciones.where((l) => l['estado'] == 'rechazada' || l['estado'] == 'revertida').toList();
    final aviso = '${(estado?['persistencia'] as Map?)?['aviso'] ?? ''}';
    final positivas = porAgente.values.fold<int>(0, (s, a) => s + ((a as Map)['positivas'] as num? ?? 0).toInt());
    final negativas = porAgente.values.fold<int>(0, (s, a) => s + ((a as Map)['negativas'] as num? ?? 0).toInt());

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead(
        title: 'Aprendizaje de los agentes',
        subtitle: 'Tus valoraciones se convierten en lecciones cortas. Ninguna se aplica sin que la pruebes y la apruebes.',
      ),
      if (error != null) GgCard(borderColor: c.crit, child: Text(error!, style: TextStyle(color: c.crit))),
      if (aviso.isNotEmpty)
        GgCard(borderColor: c.med, color: c.med.withValues(alpha: 0.08), child: Text(aviso, style: TextStyle(fontSize: 12.5, color: c.text2))),
      KpiStrip(items: [
        (valor: '$positivas', etiqueta: 'Buenas respuestas', color: positivas > 0 ? c.low : null, onTap: null),
        (valor: '$negativas', etiqueta: 'Malas respuestas', color: negativas > 0 ? c.high : null, onTap: null),
        (valor: '${pendientes.length}', etiqueta: 'Lecciones por revisar', color: pendientes.isNotEmpty ? c.med : null, onTap: null),
        (valor: '${aprobadas.length}', etiqueta: 'Lecciones activas', color: null, onTap: null),
      ]),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Valoraciones por agente'),
          if (porAgente.isEmpty)
            Text('Todavía no hay valoraciones. Usa los pulgares bajo cada respuesta del chat.', style: TextStyle(fontSize: 12.5, color: c.text3)),
          for (final e in porAgente.entries)
            Builder(builder: (context) {
              final a = Map<String, dynamic>.from(e.value as Map);
              final mot = Map<String, dynamic>.from((a['motivos'] as Map?) ?? {});
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  AgentBadge(app.badgeAgente(e.key)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(app.nombreAgente(e.key), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text('${a['positivas']} buenas · ${a['negativas']} malas (${a['negativas_nuevas']} nuevas)'
                          '${mot.isEmpty ? '' : ' · ${mot.entries.map((m) => '${motivos[m.key] ?? m.key}: ${m.value}').join(', ')}'}',
                          style: TextStyle(fontSize: 11.8, color: c.text3)),
                    ]),
                  ),
                  if (a['puede_generar'] == true)
                    GgButton('Proponer', small: true, icon: Icons.auto_awesome, loading: generando, onTap: () => _generar(e.key)),
                ]),
              );
            }),
          Text('Se proponen lecciones cuando un agente junta ${resumen?['minimo_para_lecciones'] ?? 3} valoraciones negativas nuevas.',
              style: TextStyle(fontSize: 11.5, color: c.text3)),
        ]),
      ),
      if (pendientes.isNotEmpty) const SecTitle('Por revisar'),
      for (final l in pendientes) _tarjeta(context, app, l, pendiente: true),
      if (aprobadas.isNotEmpty) const SecTitle('Activas'),
      for (final l in aprobadas) _tarjeta(context, app, l),
      if (historial.isNotEmpty)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Historial (${historial.length} rechazadas o revertidas)', style: TextStyle(fontSize: 13, color: c.text2)),
            children: [for (final l in historial) _tarjeta(context, app, l)],
          ),
        ),
    ]);
  }

  Widget _tarjeta(BuildContext context, AppState app, Map<String, dynamic> l, {bool pendiente = false}) {
    final c = context.c;
    final id = '${l['id']}';
    final ocupada = ocupadas.contains(id);
    final prueba = l['prueba'] as Map?;
    final estadoL = '${l['estado']}';
    return GgCard(
      borderColor: pendiente ? c.med : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AgentBadge(app.badgeAgente('${l['agente']}')),
          const SizedBox(width: 8),
          Expanded(child: Text(app.nombreAgente('${l['agente']}'), style: TextStyle(fontSize: 12, color: c.text3))),
          Text('v${l['version'] ?? 1}', style: TextStyle(fontSize: 11, color: c.text3)),
          const SizedBox(width: 8),
          Pill(estadoL.toUpperCase(), fg: switch (estadoL) {
            'aprobada' => c.low,
            'pendiente' => c.med,
            _ => c.text3,
          }),
        ]),
        const SizedBox(height: 8),
        Text('${l['texto']}', style: const TextStyle(fontSize: 13.5, height: 1.4)),
        if (progresoPrueba[id] != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(progresoPrueba[id]!, style: TextStyle(fontSize: 12, color: c.text3))),
        if (prueba != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(prueba['empeora'] == true ? Icons.trending_down : Icons.check_circle_outline, size: 16,
                  color: prueba['empeora'] == true ? c.high : c.low),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${prueba['conclusion']} Sin la lección: ${(prueba['sin_leccion'] as Map?)?['aciertos']} cifras clave y '
                  '${(prueba['sin_leccion'] as Map?)?['alertas']} alertas; con la lección: ${(prueba['con_leccion'] as Map?)?['aciertos']} y '
                  '${(prueba['con_leccion'] as Map?)?['alertas']}.',
                  style: TextStyle(fontSize: 12, color: c.text2),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (pendiente) ...[
            GgButton('Probar', icon: Icons.science_outlined, small: true, ghost: true, loading: ocupada && progresoPrueba[id] != null,
                onTap: ocupada || app.docActivo == null ? null : () => _accion(l, 'probar', cuerpo: {'document_id': app.docActivo})),
            GgButton('Aprobar', icon: Icons.check, small: true, loading: ocupada && progresoPrueba[id] == null,
                onTap: ocupada ? null : () => _accion(l, 'aprobar')),
            GgButton('Editar', icon: Icons.edit_outlined, small: true, ghost: true, onTap: ocupada ? null : () => _editar(l)),
            GgButton('Rechazar', small: true, ghost: true, danger: true, onTap: ocupada ? null : () => _accion(l, 'rechazar')),
          ],
          if (estadoL == 'aprobada')
            GgButton('Revertir', icon: Icons.undo, small: true, ghost: true, loading: ocupada, onTap: ocupada ? null : () => _accion(l, 'revertir')),
          if (estadoL == 'revertida' || estadoL == 'rechazada')
            GgButton('Volver a revisar', icon: Icons.edit_outlined, small: true, ghost: true, onTap: ocupada ? null : () => _editar(l)),
        ]),
        if (pendiente && app.docActivo != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('«Probar» responde las preguntas de este agente con y sin la lección sobre el documento activo.',
                style: TextStyle(fontSize: 11, color: c.text3)),
          ),
      ]),
    );
  }
}
