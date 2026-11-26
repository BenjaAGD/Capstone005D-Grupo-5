import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/servidor_estado.dart';
import '../core/theme.dart';
import 'registro_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  bool _entrando = false;
  bool _verClave = false;

  /// true cuando el último intento falló por falta de conexión (no por una clave incorrecta).
  bool _sinConexion = false;

  @override
  void dispose() {
    _correo.dispose();
    _clave.dispose();
    super.dispose();
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje)),
    );
  }

  Future<void> _iniciarSesion() async {
    if (_entrando) return;

    if (!_correo.text.trim().contains('@') || _clave.text.isEmpty) {
      _avisar('Escribe tu correo y contraseña.');
      return;
    }

    setState(() {
      _entrando = true;
      _sinConexion = false;
    });

    try {
      final respuesta =
          await Supabase.instance.client.auth.signInWithPassword(
        email: _correo.text.trim(),
        password: _clave.text,
      );

      if (respuesta.session == null) {
        _avisar('No se pudo iniciar sesión.');
      } else if (respuesta.user?.emailConfirmedAt == null) {
        _avisar('Confirma tu correo antes de ingresar.');
        await Supabase.instance.client.auth.signOut();
      }
    } on AuthRetryableFetchException {
      if (mounted) setState(() => _sinConexion = true);
    } on AuthException catch (e) {
      _avisar(
        authErrorMessage(
          e,
          fallback:
              'No se pudo ingresar. Revisa el correo y la contraseña.',
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _sinConexion = true);
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  void _reintentar() {
    ServidorEstado.instance.reintentarAhora();
    _iniciarSesion();
  }

  @override
  Widget build(BuildContext context) {
    // El login usa siempre el tema oscuro de la marca, sin depender del tema elegido dentro de la app.
    return Theme(
      data: AppTheme.build(Brightness.dark),
      child: Builder(builder: (context) {
        final c = context.c;
        final t = Theme.of(context).textTheme;
        return Scaffold(
          backgroundColor: c.bg,
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                            colors: [Brand.accent2, Brand.accent], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      ),
                      child: const Icon(Icons.check_circle_outline, size: 32, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('DIRECTA', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: Fs.xl, fontWeight: FontWeight.w700, letterSpacing: 5)),
                  const SizedBox(height: 4),
                  Text('GERENCIA GENERAL', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: Fs.xs, letterSpacing: 2.2, color: c.text3)),
                  const SizedBox(height: 32),
                  Text('Bienvenido', style: t.titleLarge),
                  const SizedBox(height: 4),
                  Text('Ingresa a tu espacio de gestión.', style: t.bodyMedium!.copyWith(color: c.text2)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _correo,
                    enabled: !_entrando,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      hintText: 'nombre@empresa.cl',
                      prefixIcon: Icon(Icons.mail_outline, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _clave,
                    enabled: !_entrando,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _iniciarSesion(),
                    obscureText: !_verClave,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      hintText: 'Escribe tu contraseña',
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: IconButton(
                        tooltip: _verClave ? 'Ocultar contraseña' : 'Mostrar contraseña',
                        onPressed: () => setState(() => _verClave = !_verClave),
                        icon: Icon(_verClave ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _entrando
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => RecuperarClaveScreen(correo: _correo.text.trim()),
                                ),
                              ),
                      child: Text('¿Olvidaste tu contraseña?',
                          style: TextStyle(color: c.accentText, fontSize: Fs.md, fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_sinConexion) ...[
                    _SinConexion(onReintentar: _entrando ? null : _reintentar),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    onPressed: _entrando ? null : _iniciarSesion,
                    icon: _entrando
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.arrow_forward, size: 18),
                    label: Text(_entrando ? 'Verificando…' : 'Iniciar sesión'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Brand.accent,
                      foregroundColor: Brand.onAccent,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: Fs.lg),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _entrando
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => const RegistroScreen()),
                            ),
                    child: Text.rich(TextSpan(
                      text: '¿No tienes cuenta? ',
                      style: TextStyle(color: c.text2, fontSize: Fs.body),
                      children: [
                        TextSpan(text: 'Regístrate', style: TextStyle(color: c.accentText, fontWeight: FontWeight.w600)),
                      ],
                    )),
                  ),
                  const SizedBox(height: 16),
                  const _EstadoServidorLogin(),
                ]),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Error de conexión al iniciar sesión, con botón para reintentar.
class _SinConexion extends StatelessWidget {
  const _SinConexion({required this.onReintentar});
  final VoidCallback? onReintentar;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.crit.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.crit.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.cloud_off, color: c.crit, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(mensajeSinConexion, style: TextStyle(fontSize: Fs.body, height: 1.4, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onReintentar,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Reintentar'),
          style: OutlinedButton.styleFrom(
            foregroundColor: c.text,
            side: BorderSide(color: c.border2),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ]),
    );
  }
}

/// Estado del servidor bajo el formulario. Solo informa: el login habla con Supabase, no con el servidor.
class _EstadoServidorLogin extends StatelessWidget {
  const _EstadoServidorLogin();
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedBuilder(
      animation: ServidorEstado.instance,
      builder: (context, _) {
        final (color, texto) = switch (ServidorEstado.instance.estado) {
          EstadoServidor.enLinea => (c.low, 'Servidor listo'),
          EstadoServidor.despertando => (c.info, 'Despertando el servidor… ya puedes iniciar sesión'),
          EstadoServidor.sinConexion => (c.med, 'El servidor no responde por ahora'),
          EstadoServidor.desconocido => (c.text3, ''),
        };
        if (texto.isEmpty) return const SizedBox.shrink();
        return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Flexible(child: Text(texto, style: TextStyle(color: c.text2, fontSize: Fs.sm))),
        ]);
      },
    );
  }
}
