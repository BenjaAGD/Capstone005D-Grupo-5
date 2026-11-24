import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/notificaciones.dart';
import '../core/saver.dart';
import 'app_state.dart';

/// Generación de la memoria en segundo plano.
/// Vive fuera de la pantalla: si la persona sale de Memoria, el trabajo sigue,
/// la notificación muestra el avance y al volver se ve el estado actual.
class TrabajoMemoria extends ChangeNotifier {
  TrabajoMemoria._();
  static final TrabajoMemoria instance = TrabajoMemoria._();

  bool corriendo = false;
  Map<String, dynamic>? progreso;
  Map<String, dynamic>? resultado;
  String? error;
  Timer? _poll;

  Future<void> iniciar(AppState st, Map<String, dynamic> cuerpo) async {
    if (corriendo) return;
    corriendo = true;
    progreso = {'paso': 'Iniciando…', 'hechos': 0, 'total': 1};
    resultado = null;
    error = null;
    notifyListeners();
    unawaited(Notificaciones.pedirPermiso());
    unawaited(Notificaciones.progreso(Notificaciones.idMemoria, 'Generando memoria', 'Iniciando…'));
    try {
      final r = await st.api.postJson('/api/memoria/borrador', cuerpo);
      if (r['ok'] != true) throw Exception(r['error'] ?? 'No se pudo iniciar');
      final id = '${r['job_id']}';
      final listo = Completer<Map<String, dynamic>>();
      var fallos = 0;
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(milliseconds: 1500), (t) async {
        try {
          final e = Map<String, dynamic>.from(await st.api.getJson('/api/memoria/borrador/$id') as Map);
          fallos = 0;
          progreso = e;
          notifyListeners();
          final hechos = (e['hechos'] as num?)?.toInt() ?? 0;
          final total = (e['total'] as num?)?.toInt() ?? 1;
          unawaited(Notificaciones.progreso(Notificaciones.idMemoria, 'Generando memoria',
              '${e['paso'] ?? ''} · $hechos de $total', valor: (100 * hechos / (total < 1 ? 1 : total)).round()));
          if (e['corriendo'] != true && !listo.isCompleted) {
            t.cancel();
            listo.complete(e);
          }
        } catch (err) {
          // Un corte de red puntual no cancela el trabajo; tras varios seguidos, sí.
          fallos++;
          if (fallos >= 8 && !listo.isCompleted) {
            t.cancel();
            listo.completeError(err);
          }
        }
      });
      final e = await listo.future;
      if (e['listo'] != true) throw Exception(e['error'] ?? 'El borrador no se pudo generar');
      final bytes = await st.api.getBytes('/api/memoria/borrador/$id/pdf');
      final nombre = '${e['nombre'] ?? 'Memoria_borrador.pdf'}';
      st.toast(await guardarArchivo(nombre, bytes, 'application/pdf'));
      resultado = e;
      unawaited(Notificaciones.listo(Notificaciones.idMemoria, 'Memoria lista', '$nombre · guardada en Documentos/Directa Gerente General'));
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      unawaited(Notificaciones.listo(Notificaciones.idMemoria, 'No se pudo generar la memoria', error!));
    }
    _poll?.cancel();
    corriendo = false;
    notifyListeners();
  }
}
