import 'package:supabase_flutter/supabase_flutter.dart';

import 'rut.dart';

/// Datos de la persona con sesión iniciada (nombre, cargo y empresa vienen del registro).
/// Nunca lanza errores: en modo demo o en pruebas sin Supabase devuelve valores vacíos.
class UsuarioActual {
  UsuarioActual._();

  static User? get _user {
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  static String? get correo => _user?.email;

  static String _meta(String k) => '${_user?.userMetadata?[k] ?? ''}'.trim();

  /// Nombre guardado en el registro; si no hay, se arma desde el correo ("javiera.villalobos" → "Javiera Villalobos").
  static String get nombre {
    final n = _meta('nombre');
    if (n.isNotEmpty) return n;
    final local = (correo ?? '').split('@').first.replaceAll(RegExp(r'[0-9]+'), '');
    final partes = local.split(RegExp(r'[._\-]+')).where((p) => p.isNotEmpty);
    final armado = partes.map((p) => p[0].toUpperCase() + p.substring(1)).join(' ');
    return armado.isEmpty ? 'Gerencia General' : armado;
  }

  /// "Javiera Villalobos" → "Javiera".
  static String get primerNombre {
    final n = nombre.split(' ').where((x) => x.isNotEmpty);
    return n.isEmpty ? 'bienvenido' : n.first;
  }

  static String? get id => _user?.id;

  /// Envía al correo de la cuenta un enlace para elegir una contraseña nueva.
  /// El enlace abre la app y muestra la pantalla "Elige una nueva contraseña".
  static Future<void> enviarEnlaceClave() async {
    final c = correo;
    if (c == null || c.isEmpty) throw StateError('Sin correo');
    await Supabase.instance.client.auth.resetPasswordForEmail(c, redirectTo: 'cl.directa.directa://login-callback');
  }

  /// "javiera@gmail.com" → "j•••••a@gmail.com".
  static String get correoOculto {
    final c = correo ?? '';
    final i = c.indexOf('@');
    if (i < 2) return c;
    final u = c.substring(0, i);
    return '${u[0]}${'•' * (u.length - 2).clamp(1, 6).toInt()}${u[u.length - 1]}${c.substring(i)}';
  }

  static bool get tieneNombre => _meta('nombre').isNotEmpty;
  /// DIRECTA es para la gerencia general: el cargo es fijo.
  static String get cargo => 'Gerente General';
  static String get rut => _meta('rut').isEmpty ? '' : Rut.formatear(_meta('rut'));
  static String get rutEmpresa => _meta('rut_empresa').isEmpty ? '' : Rut.formatear(_meta('rut_empresa'));
  static String get empresa => _meta('empresa_solicitada');

  static String get iniciales {
    final p = nombre.split(' ').where((x) => x.isNotEmpty).toList();
    if (p.isEmpty) return '';
    return (p.first[0] + (p.length > 1 ? p[1][0] : '')).toUpperCase();
  }

  /// Guarda el nombre en el perfil de Supabase (el cargo no se edita).
  static Future<void> guardar({required String nombre}) async {
    await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'nombre': nombre.trim()}));
  }
}
