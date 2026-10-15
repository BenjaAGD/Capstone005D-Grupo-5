import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Guardado local en el teléfono (equivale al localStorage del index.html).
/// Mismas claves que el MVP para que se reconozca qué se guarda.
class Store {
  Store._(this._p);
  final SharedPreferences _p;

  static Future<Store> open() async => Store._(await SharedPreferences.getInstance());

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

  String? getString(String k) => _p.getString(k);
  Future<void> setString(String k, String? v) async {
    if (v == null) {
      await _p.remove(k);
    } else {
      await _p.setString(k, v);
    }
  }

  double? getDouble(String k) => _p.getDouble(k);
  Future<void> setDouble(String k, double v) => _p.setDouble(k, v);

  T getJson<T>(String k, T def) {
    final s = _p.getString(k);
    if (s == null) return def;
    try {
      final v = jsonDecode(s);
      return v is T ? v : def;
    } catch (_) {
      return def;
    }
  }

  Future<void> setJson(String k, Object? v) => _p.setString(k, jsonEncode(v));
}
