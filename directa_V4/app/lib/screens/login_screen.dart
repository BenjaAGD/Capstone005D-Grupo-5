import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/demo_modo.dart';
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

    setState(() => _entrando = true);

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
    } on AuthException catch (e) {
      _avisar(
        authErrorMessage(
          e,
          fallback:
              'No se pudo ingresar. Revisa el correo y la contraseña.',
        ),
      );
    } catch (_) {
      _avisar('No se pudo conectar con Supabase. Inténtalo nuevamente.');
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // El login usa siempre el tema oscuro de la marca, sin depender del tema elegido dentro de la app.
    return Theme(
      data: AppTheme.build(Brightness.dark),
      child: Builder(builder: (context) {
        final c = context.c;
        return Scaffold(
          backgroundColor: c.bg,
          body: SafeArea(
            child: LayoutBuilder(builder: (context, box) {
              final compact = box.maxWidth < 520;
              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 22 : 36, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: const LinearGradient(
                              colors: [Brand.accent2, Brand.accent], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        ),
                        child: const Icon(Icons.check_circle_outline, size: 30, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      const Text('DIRECTA', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 5)),
                      const SizedBox(height: 4),
                      Text('GERENCIA GENERAL', style: TextStyle(fontSize: 10, letterSpacing: 2.2, color: c.text3)),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(compact ? 20 : 26),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: c.border),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Bienvenido', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
                          const SizedBox(height: 4),
                          Text('Ingresa a tu espacio de gestión.', style: TextStyle(color: c.text2, fontSize: 13.5)),
                          const SizedBox(height: 20),
                          Text('Correo electrónico', style: TextStyle(color: c.text2, fontSize: 12.5)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _correo,
                            enabled: !_entrando,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              hintText: 'nombre@empresa.cl',
                              prefixIcon: Icon(Icons.mail_outline, size: 19),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(children: [
                            Expanded(child: Text('Contraseña', style: TextStyle(color: c.text2, fontSize: 12.5))),
                            GestureDetector(
                              onTap: _entrando
                                  ? null
                                  : () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => RecuperarClaveScreen(correo: _correo.text.trim()),
                                        ),
                                      ),
                              child: Text('¿La olvidaste?',
                                  style: TextStyle(color: c.accentText, fontSize: 12.5, fontWeight: FontWeight.w500)),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _clave,
                            enabled: !_entrando,
                            onSubmitted: (_) => _iniciarSesion(),
                            obscureText: !_verClave,
                            decoration: InputDecoration(
                              hintText: 'Escribe tu contraseña',
                              prefixIcon: const Icon(Icons.lock_outline, size: 19),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                              suffixIcon: IconButton(
                                tooltip: _verClave ? 'Ocultar contraseña' : 'Mostrar contraseña',
                                onPressed: () => setState(() => _verClave = !_verClave),
                                icon: Icon(_verClave ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 19),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _entrando ? null : _iniciarSesion,
                              icon: _entrando
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.arrow_forward, size: 18),
                              label: Text(_entrando ? 'Verificando…' : 'Iniciar sesión'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Brand.accent,
                                foregroundColor: Brand.onAccent,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Center(
                            child: TextButton(
                              onPressed: _entrando
                                  ? null
                                  : () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(builder: (_) => const RegistroScreen()),
                                      ),
                              child: Text.rich(TextSpan(
                                text: '¿No tienes cuenta? ',
                                style: TextStyle(color: c.text2, fontSize: 13),
                                children: [
                                  TextSpan(text: 'Regístrate', style: TextStyle(color: c.accentText, fontWeight: FontWeight.w600)),
                                ],
                              )),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _entrando ? null : () => DemoModo.instance.entrar(),
                          icon: const Icon(Icons.play_circle_outline, size: 19),
                          label: const Text('Abrir demo'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.text,
                            side: BorderSide(color: c.border2),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('Entra sin cuenta si el inicio de sesión o el registro no funcionan. Usa el servidor igual que la app normal.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: c.text3, height: 1.35)),
                      const SizedBox(height: 16),
                      const _EstadoServidorLogin(),
                    ]),
                  ),
                ),
              );
            }),
          ),
        );
      }),
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
        return Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Flexible(child: Text(texto, style: TextStyle(color: c.text2, fontSize: 12))),
        ]);
      },
    );
  }
}
