import 'package:flutter/material.dart';
import 'registro_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  bool _entrando = false;

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
    const navy = Color(0xFF12324B);
    const ink = Color(0xFF173348);
    const muted = Color(0xFF748391);
    const pale = Color(0xFFF5F8FA);
    const line = Color(0xFFDCE4E9);
    const cyan = Color(0xFF12AFC6);

    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.light,
        scaffoldBackgroundColor: navy,
        colorScheme: const ColorScheme.light(primary: navy, secondary: cyan),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: pale,
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(11)), borderSide: BorderSide(color: line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(11)), borderSide: BorderSide(color: line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(11)), borderSide: BorderSide(color: cyan, width: 1.5)),
        ),
      ),
      child: Scaffold(
        backgroundColor: navy,
        body: SafeArea(
          child: LayoutBuilder(builder: (context, box) {
            final compact = box.maxWidth < 520;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: compact ? 22 : 36, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 22),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.grid_view_rounded, color: cyan, size: 28),
                        SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('DIRECTA', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 3)),
                          Text('INTELIGENCIA DIRECTIVA', style: TextStyle(color: Color(0xFFB7C7D1), fontSize: 8, letterSpacing: 2)),
                        ]),
                      ]),
                    ),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(compact ? 20 : 28),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(color: const Color(0xFFE9F7FA), borderRadius: BorderRadius.circular(11)),
                          child: const Icon(Icons.lock_outline, color: cyan, size: 20),
                        ),
                        const SizedBox(height: 18),
                        const Text('Bienvenido a DIRECTA', style: TextStyle(color: ink, fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
                        const SizedBox(height: 5),
                        const Text('Ingresa a tu espacio de gestión.', style: TextStyle(color: muted, fontSize: 14)),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFFEAF7FA), borderRadius: BorderRadius.circular(10)),
                          child: const Row(children: [
                            Icon(Icons.info_outline, color: Color(0xFF16859A), size: 18),
                            SizedBox(width: 8),
                            Expanded(child: Text('Ingresa con tu cuenta de DIRECTA.', style: TextStyle(color: ink, fontSize: 12.5))),
                          ]),
                        ),
                        const SizedBox(height: 18),
                        const Text('Correo electrónico', style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _correo,
                          enabled: !_entrando,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(hintText: 'Escribe tu correo electrónico', prefixIcon: Icon(Icons.alternate_email, size: 19)),
                        ),
                        const SizedBox(height: 14),
                        const Text('Contraseña', style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _clave,
                          enabled: !_entrando,
                          onSubmitted: (_) => _iniciarSesion(),
                          obscureText: true,
                          decoration: const InputDecoration(hintText: 'Escribe tu contraseña', prefixIcon: Icon(Icons.lock_outline, size: 19)),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _entrando ? null : _iniciarSesion,
                            icon: const Icon(Icons.arrow_forward, size: 18),
                            label: Text(_entrando ? 'Verificando…' : 'Iniciar sesión'),
                            style: FilledButton.styleFrom(
                              backgroundColor: cyan,
                              foregroundColor: const Color(0xFF062B31),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              textStyle: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _entrando
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const RegistroScreen(),
                                    ),
                                  ),
                          child: const Text('¿No tienes cuenta? Regístrate'),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _entrando
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => RecuperarClaveScreen(
                                          correo: _correo.text.trim(),
                                        ),
                                      ),
                                    ),
                            child: const Text('¿Olvidaste tu contraseña?'),
                          ),
                        ),
                        const Divider(height: 26, color: line),
                        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.verified_user_outlined, size: 16, color: muted),
                          SizedBox(width: 8),
                          Expanded(child: Text('Utiliza el correo y la contraseña de tu cuenta de Supabase Auth.',
                              style: TextStyle(color: muted, fontSize: 11.5, height: 1.4))),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    const Text('DIRECTA · Gerencia General', style: TextStyle(color: Color(0xFFB7C7D1), fontSize: 11)),
                  ]),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
