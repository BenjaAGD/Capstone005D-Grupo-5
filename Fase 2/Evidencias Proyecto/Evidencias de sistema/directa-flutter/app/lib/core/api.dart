import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Error legible para mostrar en pantalla.
class ApiError implements Exception {
  ApiError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cliente HTTP del backend DIRECTA (main.py). Todas las rutas son las mismas que usa el index.html.
class Api {
  Api(this.baseUrl, {http.Client? client}) : _client = client ?? http.Client();

  String baseUrl;
  final http.Client _client;
  static const _timeout = Duration(seconds: 40);

  Uri _u(String path, [Map<String, String>? q]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: q);
  }

  dynamic _decode(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      String msg = 'El servidor respondió ${r.statusCode}';
      try {
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is Map && j['error'] != null) msg = j['error'].toString();
      } catch (_) {}
      throw ApiError(msg);
    }
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<dynamic> getJson(String path, {Map<String, String>? query, Duration? timeout}) async {
    try {
      final r = await _client.get(_u(path, query)).timeout(timeout ?? _timeout);
      return _decode(r);
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw ApiError('El servidor no respondió a tiempo.');
    } catch (e) {
      throw ApiError('No se pudo conectar con el servidor ($baseUrl).');
    }
  }

  Future<dynamic> postForm(String path, Map<String, String> fields) async {
    try {
      final req = http.MultipartRequest('POST', _u(path))..fields.addAll(fields);
      final r = await http.Response.fromStream(await _client.send(req).timeout(const Duration(minutes: 3)));
      return _decode(r);
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError('No se pudo conectar con el servidor ($baseUrl).');
    }
  }

  Future<dynamic> postJson(String path, Object body) async {
    try {
      final r = await _client
          .post(_u(path), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(minutes: 3));
      return _decode(r);
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError('No se pudo conectar con el servidor ($baseUrl).');
    }
  }

  Future<dynamic> delete(String path) async {
    try {
      return _decode(await _client.delete(_u(path)).timeout(_timeout));
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError('No se pudo conectar con el servidor ($baseUrl).');
    }
  }

  /// Sube un archivo (multipart) — POST /api/subir-informe/.
  Future<dynamic> upload(String path, Map<String, String> fields, String fileField, String fileName, Uint8List bytes) async {
    try {
      final req = http.MultipartRequest('POST', _u(path))
        ..fields.addAll(fields)
        ..files.add(http.MultipartFile.fromBytes(fileField, bytes, filename: fileName));
      final r = await http.Response.fromStream(await _client.send(req).timeout(const Duration(minutes: 5)));
      return _decode(r);
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError('No se pudo subir el archivo al servidor ($baseUrl).');
    }
  }

  /// Descarga binaria (PDF / Excel). [form] = multipart; [json] = cuerpo JSON.
  Future<Uint8List> download(String path, {Map<String, String>? form, Object? json}) async {
    http.Response r;
    try {
      if (form != null) {
        final req = http.MultipartRequest('POST', _u(path))..fields.addAll(form);
        r = await http.Response.fromStream(await _client.send(req).timeout(const Duration(minutes: 3)));
      } else {
        r = await _client
            .post(_u(path), headers: {'Content-Type': 'application/json'}, body: jsonEncode(json ?? {}))
            .timeout(const Duration(minutes: 3));
      }
    } catch (e) {
      throw ApiError('No se pudo conectar con el servidor ($baseUrl).');
    }
    if (r.statusCode != 200) {
      String msg = 'El servidor respondió ${r.statusCode}';
      try {
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is Map && j['error'] != null) msg = j['error'].toString();
      } catch (_) {}
      throw ApiError(msg);
    }
    return r.bodyBytes;
  }

  /// Respuesta del chat por Server-Sent Events (POST /api/consultar-stream/).
  /// Emite mapas con "chunk", "fuentes", "agente" o "error".
  Stream<Map<String, dynamic>> sse(String path, Map<String, String> fields) async* {
    final req = http.MultipartRequest('POST', _u(path))..fields.addAll(fields);
    final resp = await _client.send(req).timeout(const Duration(minutes: 4));
    if (resp.statusCode != 200) throw ApiError('El servidor respondió ${resp.statusCode}');
    var buffer = '';
    await for (final parte in resp.stream.transform(utf8.decoder)) {
      buffer += parte;
      final lineas = buffer.split('\n');
      buffer = lineas.removeLast();
      for (final l in lineas) {
        final m = _linea(l);
        if (m != null) yield m;
      }
    }
    final m = _linea(buffer);
    if (m != null) yield m;
  }

  Map<String, dynamic>? _linea(String l) {
    final t = l.trim();
    if (!t.startsWith('data:')) return null;
    final p = t.substring(5).trim();
    if (p.isEmpty || p == '[DONE]') return null;
    try {
      final j = jsonDecode(p);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }
}
