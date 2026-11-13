import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keychain/almacén del SO en móvil. En web la sesión solo vive en memoria;
/// nunca se guarda el access/refresh token en localStorage ni SharedPreferences.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage(this.projectKey);
  final String projectKey;
  final _storage = const FlutterSecureStorage();
  String? _memory;
  String get _key => 'directa.auth.$projectKey';
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => kIsWeb ? _memory : _storage.read(key: _key);
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<void> persistSession(String persistSessionString) async {
    if (kIsWeb) { _memory = persistSessionString; return; }
    await _storage.write(key: _key, value: persistSessionString);
  }
  @override
  Future<void> removePersistedSession() async {
    _memory = null;
    if (!kIsWeb) await _storage.delete(key: _key);
  }
}
