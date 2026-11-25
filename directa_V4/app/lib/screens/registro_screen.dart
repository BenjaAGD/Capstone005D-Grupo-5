import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/rut.dart';
import 'auth_location_stub.dart'
    if (dart.library.js_interop) 'auth_location_web.dart';

bool isRecoveryLocation(Uri uri) {
  if (uri.queryParameters['flow'] == 'recovery') return true;

  try {
    return Uri.splitQueryString(uri.fragment)['type'] == 'recovery';
  } on FormatException {
    return false;
  }
}

String authErrorMessage(AuthException e, {String? fallback}) {
  // Mensajes del control de registro en Supabase (empresas autorizadas / RUT).
  final m = e.message;
  final i = m.indexOf('DIRECTA:');
  if (i >= 0) return m.substring(i + 8).trim();

  if (e.statusCode == '429' || (e.code ?? '').startsWith('over_')) {
    return 'Se alcanzó el límite de solicitudes. '
        'Espera antes de volver a intentarlo.';
  }

  return switch (e.code) {
    'weak_password' => 'Elige una contraseña más segura.',
    'same_password' => 'Elige una contraseña diferente de la anterior.',
    'otp_expired' || 'session_not_found' || 'bad_jwt' =>
      'El enlace venció o ya fue utilizado. Solicita uno nuevo.',
    'email_not_confirmed' => 'Confirma tu correo antes de ingresar.',
    'email_address_invalid' => 'Revisa el correo electrónico.',
    'signup_disabled' =>
      'El registro está deshabilitado. Contacta al administrador.',
    'email_address_not_authorized' =>
      'El envío a este correo no está habilitado. Contacta al administrador.',
    _ => fallback ??
        'No se pudo completar la solicitud. '
            'Revisa tus datos e inténtalo nuevamente.',
  };
}

// Pausa local compartida por correo.
// Los límites del servidor siguen aplicándose.
class AuthMailPacing {
  static DateTime Function() now = DateTime.now;

  static String key(String email) {
    final encoded = base64Url.encode(
      utf8.encode(email.trim().toLowerCase()),
    );
    return 'directa.auth.wait.$encoded';
  }

  static Future<DateTime?> until(String email) async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getInt(key(email));

    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value);
  }

  static Future<DateTime> reserve(String email) async {
    final next = now().add(const Duration(seconds: 60));
    final preferences = await SharedPreferences.getInstance();

    await preferences.setInt(
      key(email),
      next.millisecondsSinceEpoch,
    );

    return next;
  }
}

// Atiende los enlaces de recuperación antes de abrir la aplicación.
class AuthRecoveryGate extends StatefulWidget {
  const AuthRecoveryGate({
    super.key,
    required this.child,
    this.initialRecovery = false,
  });

  final Widget child;
  final bool initialRecovery;

  @override
  State<AuthRecoveryGate> createState() => _AuthRecoveryGateState();
}

class _AuthRecoveryGateState extends State<AuthRecoveryGate> {
  late bool _recovery;
  late final StreamSubscription<AuthState> _subscription;

  @override
  void initState() {
    super.initState();
    _recovery = widget.initialRecovery;

    _subscription =
        Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (mounted &&
            state.event == AuthChangeEvent.passwordRecovery) {
          setState(() => _recovery = true);
        }
      },
      onError: (Object error, StackTrace stack) {},
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_recovery) return widget.child;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CambiarClaveScreen(
        onDone: () async {
          try {
            await Supabase.instance.client.auth.signOut();
          } catch (_) {}

          if (!mounted) return;

          clearRecoveryLocation();
          setState(() => _recovery = false);
        },
      ),
    );
  }
}

class RegistroScreen extends StatelessWidget {
  const RegistroScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _CuentaScreen(mode: _Mode.signup);
}

class RecuperarClaveScreen extends StatelessWidget {
  const RecuperarClaveScreen({
    super.key,
    this.correo = '',
  });

  final String correo;

  @override
  Widget build(BuildContext context) => _CuentaScreen(
        mode: _Mode.recover,
        email: correo,
      );
}

class CambiarClaveScreen extends StatelessWidget {
  const CambiarClaveScreen({
    super.key,
    required this.onDone,
  });

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => _CuentaScreen(
        mode: _Mode.reset,
        onDone: onDone,
      );
}

enum _Mode { signup, recover, reset }

class _CuentaScreen extends StatefulWidget {
  const _CuentaScreen({
    required this.mode,
    this.email = '',
    this.onDone,
  });

  final _Mode mode;
  final String email;
  final VoidCallback? onDone;

  @override
  State<_CuentaScreen> createState() => _CuentaScreenState();
}

class _CuentaScreenState extends State<_CuentaScreen> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _empresa = TextEditingController();
  final _rut = TextEditingController();
  final _rutEmpresa = TextEditingController();
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  final _confirmacion = TextEditingController();

  bool _busy = false;
  bool _sent = false;
  bool _visible = false;

  String? _error;
  DateTime? _until;
  late final Timer _timer;

  bool get _signup => widget.mode == _Mode.signup;
  bool get _reset => widget.mode == _Mode.reset;

  int get _seconds {
    final ms =
        _until?.difference(AuthMailPacing.now()).inMilliseconds ?? 0;
    return ms <= 0 ? 0 : (ms + 999) ~/ 1000;
  }

  @override
  void initState() {
    super.initState();

    _correo.text = widget.email;
    _correo.addListener(_loadWait);
    _loadWait();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _until != null) {
        setState(() {
          if (_seconds == 0) _until = null;
        });
      }
    });
  }

  Future<void> _loadWait() async {
    if (_reset) return;

    final email = _correo.text;
    final until = await AuthMailPacing.until(email);

    if (mounted && email == _correo.text) {
      setState(() => _until = until);
    }
  }

  @override
  void dispose() {
    _timer.cancel();

    for (final c in [
      _nombre,
      _empresa,
      _rut,
      _rutEmpresa,
      _correo,
      _clave,
      _confirmacion,
    ]) {
      c.dispose();
    }

    super.dispose();
  }

  void _back() {
    if (_reset) {
      widget.onDone?.call();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _submit({bool resend = false}) async {
    if (_busy || (!_reset && _seconds > 0)) return;
    if (!resend && !_form.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = Supabase.instance.client.auth;

    try {
      if (_reset) {
        final session = auth.currentSession;

        if (session == null || session.isExpired) {
          setState(() => _error =
              'El enlace venció o ya fue utilizado. Solicita uno nuevo.');
          return;
        }

        await auth.updateUser(
          UserAttributes(password: _clave.text),
        );

        try {
          await auth.signOut();
        } catch (_) {
          // La sesión local ya se cerró.
        }
      } else {
        final pending = await AuthMailPacing.until(_correo.text);

        if (pending != null &&
            pending.isAfter(AuthMailPacing.now())) {
          if (mounted) setState(() => _until = pending);
          return;
        }

        final until = await AuthMailPacing.reserve(_correo.text);
        if (!mounted) return;

        setState(() => _until = until);

        final redirect = kIsWeb
            ? '${Uri.base.origin}/${_signup ? '' : '?flow=recovery'}'
            : 'cl.directa.directa://login-callback';

        if (!_signup) {
          await auth.resetPasswordForEmail(
            _correo.text.trim(),
            redirectTo: redirect,
          );
        } else if (resend) {
          await auth.resend(
            type: OtpType.signup,
            email: _correo.text.trim(),
            emailRedirectTo: redirect,
          );
        } else {
          final response = await auth.signUp(
            email: _correo.text.trim(),
            password: _clave.text,
            emailRedirectTo: redirect,
            data: {
              'nombre': _nombre.text.trim(),
              'rut': Rut.normalizar(_rut.text),
              'empresa_solicitada': _empresa.text.trim(),
              'rut_empresa': Rut.normalizar(_rutEmpresa.text),
              'cargo': 'Gerente General',
            },
          );

          if (!mounted) return;

          if (response.user == null) {
            throw StateError('Registro incompleto');
          }

          if (response.session != null &&
              response.user!.emailConfirmedAt != null) {
            _back();
            return;
          }
        }
      }

      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = authErrorMessage(e));
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'No se pudo conectar. Inténtalo nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    String? Function(String?)? validate,
    bool secret = false,
    int? limit,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: c,
        enabled: !_busy,
        validator: validate,
        maxLength: limit,
        autocorrect: false,
        enableSuggestions: !secret,
        keyboardType: c == _correo
            ? TextInputType.emailAddress
            : TextInputType.text,
        onChanged: c == _rut || c == _rutEmpresa
            ? (v) {
                // Pone puntos y guion mientras escribe: 123456785 → 12.345.678-5
                final f = Rut.normalizar(v).isEmpty ? v : Rut.formatear(v);
                if (f != v && v.length >= 8) {
                  c.value = TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
                }
              }
            : null,
        autofillHints: c == _correo
            ? const [AutofillHints.email]
            : secret
                ? const [AutofillHints.newPassword]
                : c == _nombre
                    ? const [AutofillHints.name]
                    : null,
        obscureText: secret && !_visible,
        textInputAction:
            c == _confirmacion || (!_signup && !_reset)
                ? TextInputAction.done
                : TextInputAction.next,
        onFieldSubmitted:
            c == _confirmacion || (!_signup && !_reset)
                ? (_) => _submit()
                : null,
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          prefixIcon: Icon(icon, size: 19),
          helperText: c == _clave ? 'Mínimo 8 caracteres.' : null,
          suffixIcon: !secret
              ? null
              : IconButton(
                  tooltip: _visible
                      ? 'Ocultar contraseña'
                      : 'Mostrar contraseña',
                  onPressed: _busy
                      ? null
                      : () => setState(
                            () => _visible = !_visible,
                          ),
                  icon: Icon(
                    _visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 19,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _button(String text, VoidCallback? action) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: action,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Text(text),
        ),
      ),
    );
  }

  Widget _content() {
    final session = Supabase.instance.client.auth.currentSession;
    final expired = _reset &&
        !_sent &&
        (session == null || session.isExpired);

    final title = _sent
        ? (_reset ? 'Contraseña actualizada' : 'Revisa tu correo')
        : expired
            ? 'Solicita un nuevo enlace'
            : _signup
                ? 'Crea tu cuenta'
                : _reset
                    ? 'Elige una nueva contraseña'
                    : 'Recupera tu acceso';

    final subtitle = _sent
        ? (_reset
            ? 'Ya puedes ingresar con tu nueva contraseña.'
            : _signup
                ? 'Confirma tu correo para completar el registro y comenzar.'
                : 'Si existe una cuenta con ese correo, recibirás un enlace para cambiar tu contraseña.')
        : expired
            ? 'El enlace venció, ya fue utilizado o no se pudo verificar.'
            : _signup
                ? 'Un espacio para preparar tus decisiones con claridad.'
                : _reset
                    ? 'Define una contraseña que solo tú conozcas.'
                    : 'Te enviaremos instrucciones para volver a ingresar.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          alignment: Alignment.centerLeft,
          child: CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFE6F6F8),
            child: Icon(
              _sent
                  ? Icons.mark_email_read_outlined
                  : _signup
                      ? Icons.person_add_alt_1_outlined
                      : Icons.lock_reset_rounded,
              color: const Color(0xFF078C9F),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _signup ? 'BIENVENIDO A DIRECTA' : 'TU CUENTA DIRECTA',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            color: Color(0xFF718394),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 27,
            height: 1.15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF12324B),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Color(0xFF647789),
          ),
        ),
        const SizedBox(height: 26),
        if (!_sent && !expired)
          Form(
            key: _form,
            child: AutofillGroup(
              child: Column(
                children: [
                  if (_signup) ...[
                    _field(
                      _nombre,
                      'Nombre completo',
                      Icons.person_outline,
                      limit: 120,
                      validate: (v) =>
                          (v ?? '').trim().isEmpty
                              ? 'Escribe tu nombre.'
                              : null,
                    ),
                    _field(
                      _rut,
                      'Tu RUT',
                      Icons.badge_outlined,
                      limit: 12,
                      validate: (v) => Rut.validar(v),
                    ),
                    _field(
                      _empresa,
                      'Empresa',
                      Icons.business_outlined,
                      limit: 120,
                      validate: (v) => (v ?? '').trim().isEmpty ? 'Escribe el nombre de tu empresa.' : null,
                    ),
                    _field(
                      _rutEmpresa,
                      'RUT de la empresa',
                      Icons.domain_verification_outlined,
                      limit: 12,
                      validate: (v) => Rut.validar(v, que: 'RUT de la empresa'),
                    ),
                    const Text(
                      'Solo pueden crear cuenta las personas de empresas habilitadas en DIRECTA.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF7D8B98)),
                    ),
                    const Divider(height: 24),
                  ],
                  if (!_reset)
                    _field(
                      _correo,
                      'Correo electrónico',
                      Icons.alternate_email,
                      limit: 254,
                      validate: (v) => RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                      ).hasMatch((v ?? '').trim())
                          ? null
                          : 'Escribe un correo válido.',
                    ),
                  if (_signup || _reset) ...[
                    _field(
                      _clave,
                      'Contraseña',
                      Icons.lock_outline,
                      secret: true,
                      validate: (v) =>
                          (v ?? '').trim().length < 8
                              ? 'Usa al menos 8 caracteres.'
                              : null,
                    ),
                    _field(
                      _confirmacion,
                      'Confirmar contraseña',
                      Icons.verified_user_outlined,
                      secret: true,
                      validate: (v) =>
                          (v ?? '').isEmpty || v != _clave.text
                              ? 'Las contraseñas deben coincidir.'
                              : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (_error != null) ...[
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1ED),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFA43C26),
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (!expired && !_sent)
          _button(
            _busy
                ? 'Procesando…'
                : _seconds > 0 && !_reset
                    ? 'Reintentar en ${_seconds}s'
                    : _signup
                        ? 'Crear mi cuenta'
                        : _reset
                            ? 'Guardar nueva contraseña'
                            : 'Enviar enlace',
            _busy || (!_reset && _seconds > 0)
                ? null
                : () => _submit(),
          ),
        if (_sent && !_reset) ...[
          Text(
            _correo.text.trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          const Text(
            'Revisa también la carpeta de spam.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF647789),
            ),
          ),
          const SizedBox(height: 20),
          _button(
            _busy
                ? 'Enviando…'
                : _seconds > 0
                    ? 'Reenviar en ${_seconds}s'
                    : 'Reenviar correo',
            _busy || _seconds > 0
                ? null
                : () => _submit(resend: true),
          ),
        ],
        if (expired)
          _button(
            'Solicitar otro enlace',
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RecuperarClaveScreen(),
              ),
            ),
          ),
        TextButton(
          onPressed: _busy ? null : _back,
          child: Text(
            _signup && !_sent
                ? 'Ya tengo cuenta. Iniciar sesión'
                : 'Volver a iniciar sesión',
          ),
        ),
        if (_signup && !_sent)
          const Text(
            'Al crear tu cuenta te enviaremos un correo para confirmarla.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF7D8B98),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      child: PopScope(
        canPop: !_busy,
        child: _content(),
      ),
    );
  }
}

class AuthFrame extends StatelessWidget {
  const AuthFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF12324B);
    const cyan = Color(0xFF12AFC6);

    final theme = ThemeData.light().copyWith(
      colorScheme: const ColorScheme.light(
        primary: navy,
        secondary: cyan,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cyan,
          foregroundColor: const Color(0xFF062B31),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF7F9FB),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        labelStyle: const TextStyle(
          color: Color(0xFF647789),
          fontSize: 13,
        ),
        prefixIconColor: const Color(0xFF7A8F9F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDE5EC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cyan, width: 1.6),
        ),
      ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF081D31), Color(0xFF123A52)],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= 920;

                final panel = Container(
                  padding: EdgeInsets.all(wide ? 34 : 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 36,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: child,
                );

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 40 : 20,
                    vertical: wide ? 40 : 24,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 1080),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.grid_view_rounded,
                                color: cyan,
                                size: 28,
                              ),
                              SizedBox(width: 12),
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'DIRECTA',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 23,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                  Text(
                                    'INTELIGENCIA DIRECTIVA',
                                    style: TextStyle(
                                      color: Color(0xFFA8BFCE),
                                      fontSize: 8,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          if (wide)
                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.center,
                              children: [
                                const Expanded(
                                  flex: 4,
                                  child: Padding(
                                    padding: EdgeInsets.only(right: 56),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Más claridad.\nMejores decisiones.',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 42,
                                            height: 1.12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(height: 22),
                                        Text(
                                          'Tu información corporativa, '
                                          'organizada para preparar cada '
                                          'sesión con confianza.',
                                          style: TextStyle(
                                            color: Color(0xFFB8CBD7),
                                            fontSize: 16,
                                            height: 1.6,
                                          ),
                                        ),
                                        SizedBox(height: 34),
                                        _Benefit(
                                          Icons.folder_open_outlined,
                                          'Documentos en un solo lugar',
                                        ),
                                        _Benefit(
                                          Icons.manage_search_outlined,
                                          'Hallazgos y preguntas relevantes',
                                        ),
                                        _Benefit(
                                          Icons.insights_outlined,
                                          'Preparación para el directorio',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(flex: 6, child: panel),
                              ],
                            )
                          else
                            panel,
                          const SizedBox(height: 24),
                          const Center(
                            child: Text(
                              'DIRECTA · Gerencia General',
                              style: TextStyle(
                                color: Color(0xFF9CB5C5),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF5BD2DF), size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFCDDBE4),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}