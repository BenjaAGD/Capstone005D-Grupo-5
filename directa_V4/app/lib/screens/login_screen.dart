import 'package:flutter/material.dart';

import 'shell.dart';

/// Acceso visual de DIRECTA. La autenticación real queda pendiente de Supabase.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  void _entrarSinLogin(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const Shell()),
    );
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
                            Expanded(child: Text('El acceso real aún no está configurado.', style: TextStyle(color: ink, fontSize: 12.5))),
                          ]),
                        ),
                        const SizedBox(height: 18),
                        const Text('Correo electrónico', style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        const TextField(
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(hintText: 'Escribe tu correo electrónico', prefixIcon: Icon(Icons.alternate_email, size: 19)),
                        ),
                        const SizedBox(height: 14),
                        const Text('Contraseña', style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        const TextField(
                          obscureText: true,
                          decoration: InputDecoration(hintText: 'Escribe tu contraseña', prefixIcon: Icon(Icons.lock_outline, size: 19)),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: null,
                            child: Text('Olvidé mi contraseña', style: TextStyle(color: muted, fontSize: 12)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _entrarSinLogin(context),
                            icon: const Icon(Icons.arrow_forward, size: 18),
                            label: const Text('Entrar en modo de prueba'),
                            style: FilledButton.styleFrom(
                              backgroundColor: cyan,
                              foregroundColor: const Color(0xFF062B31),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              textStyle: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: null,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: line),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Iniciar sesión · pendiente de Supabase'),
                          ),
                        ),
                        const Divider(height: 26, color: line),
                        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.science_outlined, size: 16, color: muted),
                          SizedBox(width: 8),
                          Expanded(child: Text('En modo de prueba no se valida identidad. El acceso real estará disponible cuando Supabase esté conectado.',
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
