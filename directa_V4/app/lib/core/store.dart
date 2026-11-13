import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Guardado local en el teléfono (equivale al localStorage del index.html).
/// Mismas claves que el MVP para que se reconozca qué se guarda.
class Store {
  Store._(this._p, this._scope, this._lease, this._publicOnly, this._leases);
  final SharedPreferences _p;
  final String? _scope;
  final _StoreLease? _lease;
  final Map<String, _StoreLease> _leases;
  final bool _publicOnly;

  static Future<Store> open() async => Store._(await SharedPreferences.getInstance(), null, null, false, {});

  Store publicOnly() => Store._(_p, null, null, true, _leases);

  /// Los datos anteriores sin identidad no se adjudican a la primera cuenta.
  Store scoped(String userId, String tenantId) {
    final scope = '${userId}_$tenantId';
    var lease = _leases[scope];
    if (lease == null || !lease.active) { lease = _StoreLease(); _leases[scope] = lease; }
    return Store._(_p, scope, lease, false, _leases);
  }

  bool _public(String key) => key == kApi || key == kTheme || key == kFont;
  bool _canUse(String key) => _public(key) || (!_publicOnly && (_lease?.active ?? true));
  String _key(String key) => _scope == null || _public(key) ? key : 'directa_session_${_scope}__$key';

  Future<void> clearSession(String userId, String tenantId) async {
    final scope = '${userId}_$tenantId';
    final lease = _leases[scope];
    if (lease != null) { lease.active = false; await Future.wait(lease.pending.toList()); }
    final prefix = 'directa_session_${scope}__';
    for (final key in _p.getKeys().where((key) => key.startsWith(prefix)).toList()) { await _p.remove(key); }
  }

  Future<void> _write(String key, Future<bool> Function(String actualKey) operation) async {
    if (!_canUse(key)) return;
    final pending = operation(_key(key));
    if (!_public(key)) _lease?.pending.add(pending);
    try { await pending; } finally { _lease?.pending.remove(pending); }
  }

  static const kApi = 'directa_api';
  static const kTheme = 'directa_theme';
  static const kFont = 'directa_font_scale';
  static const kDoc = 'directa_doc_activo';
  static const kInforme = 'directa_informe_v2';
  static const kChats = 'directa_chats_v2';
  static const kAcciones = 'directa_dashboard_acciones_v1';
  static const kMemoria = 'directa_memoria_v1';
  static const kIndPropios = 'directa_indicadores_propios_v1';
  static const kIndAjustes = 'directa_indicadores_ajustes_v1';
  static const kAgente = 'directa_agente_actual';
  static const kRuta = 'directa_ruta_preguntas_v1';
  static const kPrep = 'directa_preparar_reunion_v1';
  static const kValoraciones = 'directa_valoraciones_v1';

  String? getString(String k) => _canUse(k) ? _p.getString(_key(k)) : null;
  Future<void> setString(String k, String? v) async {
    if (v == null) {
      await _write(k, _p.remove);
    } else {
      await _write(k, (key) => _p.setString(key, v));
    }
  }

  double? getDouble(String k) => _canUse(k) ? _p.getDouble(_key(k)) : null;
  Future<void> setDouble(String k, double v) => _write(k, (key) => _p.setDouble(key, v));

  T getJson<T>(String k, T def) {
    final s = getString(k);
    if (s == null) return def;
    try {
      final v = jsonDecode(s);
      return v is T ? v : def;
    } catch (_) {
      return def;
    }
  }

  Future<void> setJson(String k, Object? v) => setString(k, jsonEncode(v));
}

class _StoreLease {
  bool active = true;
  final pending = <Future<bool>>{};
}
