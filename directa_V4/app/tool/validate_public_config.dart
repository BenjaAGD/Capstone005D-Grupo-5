import 'dart:convert';
import 'dart:io';

/// Impide compilar una credencial de servidor en el JavaScript del cliente.
void main(List<String> args) {
  if (args.length != 4) throw ArgumentError('Se requieren cuatro variables públicas.');
  final [url, key, api, redirect] = args;
  if (url.isEmpty && key.isEmpty) {
    stdout.writeln('Sin configuración de Auth: el login permanecerá bloqueado.');
    return;
  }
  void invalid() => throw ArgumentError('Configuración pública inválida. Usa HTTPS y la clave anon/publicable de Supabase.');
  bool https(String value) {
    final parsed = Uri.tryParse(value);
    return parsed != null && parsed.scheme == 'https' && parsed.hasAuthority &&
        parsed.host.isNotEmpty && parsed.userInfo.isEmpty && !parsed.hasQuery && !parsed.hasFragment;
  }
  if (!https(url) || key.isEmpty || key.startsWith('sb_secret_') || (api.isNotEmpty && !https(api))) invalid();
  if (redirect.isNotEmpty && !https(redirect)) invalid();
  if (key.split('.').length == 3) {
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(key.split('.')[1]))));
      if (payload is! Map || payload['role'] != 'anon') invalid();
    } catch (_) { invalid(); }
  } else if (!key.startsWith('sb_publishable_')) { invalid(); }
}
