import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_repository.dart';
import '../core/theme.dart';

const _navy = Color(0xFF102D48);
const _ink = Color(0xFF142D43);
const _muted = Color(0xFF6B7D8E);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  bool _showPassword = false, _showSecret = false;

  @override
  void dispose() {
    _email.dispose(); _password.dispose(); _confirm.dispose(); _code.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthController auth) async {
    if (auth.busy || !(_form.currentState?.validate() ?? false)) return;
    final phase = auth.phase;
    if (phase == AuthPhase.mfaSetup || phase == AuthPhase.mfaChallenge) {
      await auth.verifyMfa(_code.text.trim());
      if (mounted) _code.clear();
    } else if (phase == AuthPhase.recovery) {
      if (auth.passwordRecoveryActive) {
        await auth.changePassword(_password.text);
        if (mounted) { _password.clear(); _confirm.clear(); }
      } else {
        await auth.requestPasswordReset(_email.text);
      }
    } else {
      await auth.signIn(_email.text.trim(), _password.text);
      if (mounted) _password.clear();
    }
  }

  InputDecoration _input(String label, String hint, IconData icon, {Widget? suffix}) => InputDecoration(
    labelText: label, hintText: hint, floatingLabelBehavior: FloatingLabelBehavior.always,
    prefixIcon: Icon(icon, size: 20, color: _muted), suffixIcon: suffix,
    filled: true, fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 19),
    labelStyle: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w600),
    hintStyle: const TextStyle(color: Color(0xFF95A2AE), fontSize: 14),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFDCE5ED))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Brand.accent, width: 1.5)),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Theme(
      data: AppTheme.build(Brightness.light),
      child: Scaffold(
        backgroundColor: _navy,
        body: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          if (wide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Expanded(flex: 11, child: _BrandPanel()),
              Expanded(flex: 10, child: ColoredBox(color: Colors.white,
                child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 44),
                  child: ConstrainedBox(constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - 88)),
                    child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: _content(auth))),
                  ),
                ),
              )),
            ]);
          }
          return SafeArea(child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(18, 28, 18, 24),
            child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 540),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: _BrandMark()),
                const SizedBox(height: 25),
                Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(25, 30, 25, 24),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
                    boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 28, offset: Offset(0, 12))]),
                  child: _content(auth)),
                const SizedBox(height: 22),
                const Center(child: Text('DIRECTA · Gerencia General', style: TextStyle(color: Color(0xFFA6BDCE), fontSize: 11))),
              ]),
            )),
          ));
        }),
      ),
    );
  }

  Widget _content(AuthController auth) {
    final phase = auth.phase;
    final mfa = phase == AuthPhase.mfaSetup || phase == AuthPhase.mfaChallenge;
    final recovery = phase == AuthPhase.recovery;
    final checking = phase == AuthPhase.checking;
    final blocked = phase == AuthPhase.noMembership || phase == AuthPhase.emailVerification ||
        phase == AuthPhase.chooseOrganization || phase == AuthPhase.connectionError;
    final title = checking ? 'Verificando tu acceso' : mfa ? 'Verifica tu identidad' :
      recovery ? (auth.passwordRecoveryActive ? 'Crea tu nueva contraseña' : 'Recupera tu acceso') :
      phase == AuthPhase.noMembership ? 'Tu cuenta está verificada' :
      phase == AuthPhase.emailVerification ? 'Confirma tu correo' :
      phase == AuthPhase.chooseOrganization ? 'Elige tu organización' :
      phase == AuthPhase.connectionError ? 'Completemos la conexión' : 'Bienvenido a DIRECTA';
    final subtitle = checking ? 'Estamos comprobando tu sesión y tus permisos.' :
      phase == AuthPhase.mfaSetup ? 'Configura tu autenticador para proteger el acceso a tu información.' :
      phase == AuthPhase.mfaChallenge ? 'Escribe el código de tu aplicación de autenticación para continuar.' :
      recovery ? (auth.passwordRecoveryActive ? 'Elige una contraseña única de al menos 12 caracteres.' : 'Te enviaremos las instrucciones a tu correo.') :
      phase == AuthPhase.noMembership ? 'Falta asignarte una organización activa. Contacta al administrador para continuar.' :
      phase == AuthPhase.emailVerification ? 'Abre el mensaje de confirmación que enviamos a tu correo antes de continuar.' :
      phase == AuthPhase.chooseOrganization ? 'Accederás únicamente al espacio que selecciones.' :
      phase == AuthPhase.connectionError ? 'Necesitamos verificar el servidor antes de abrir tu espacio.' :
      'Ingresa a tu espacio de gestión.';

    return AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Container(width: 39, height: 39, decoration: BoxDecoration(color: const Color(0xFFEDF8FC), borderRadius: BorderRadius.circular(11)),
          child: Icon(mfa ? Icons.verified_user_outlined : Icons.lock_outline_rounded, color: const Color(0xFF187E9D), size: 21)),
        const Spacer(),
        if (auth.config.testAccount) Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xFFF1F6FA), borderRadius: BorderRadius.circular(6)),
          child: const Text('ENTORNO LOCAL', style: TextStyle(color: _muted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1))),
      ]),
      const SizedBox(height: 28),
      Text(title, style: const TextStyle(color: _ink, fontSize: 28, fontWeight: FontWeight.w700, height: 1.22, letterSpacing: -.7)),
      const SizedBox(height: 11),
      Text(subtitle, style: const TextStyle(color: _muted, fontSize: 14, height: 1.65)),
      const SizedBox(height: 32),
      if (auth.error != null) _notice(auth.error!, error: true),
      if (auth.notice != null) _notice(auth.notice!),
      if (checking) const Padding(padding: EdgeInsets.symmetric(vertical: 26), child: Center(child: CircularProgressIndicator(color: Brand.accent))),
      if (!checking && !blocked) Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (mfa) ...[
          if (phase == AuthPhase.mfaSetup && auth.enrollment != null) ...[
            Center(child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(
              color: Colors.white, border: Border.all(color: const Color(0xFFE0E8EF)), borderRadius: BorderRadius.circular(14)),
              child: QrImageView(data: auth.enrollment!.uri, size: 160, backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _ink)))),
            const SizedBox(height: 12),
            const Text('Escanea el código con tu autenticador.', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 12)),
            TextButton(onPressed: () => setState(() => _showSecret = !_showSecret),
              child: Text(_showSecret ? 'Ocultar clave de configuración' : 'Configurar manualmente', style: const TextStyle(fontSize: 12))),
            if (_showSecret) Padding(padding: const EdgeInsets.only(bottom: 18), child: SelectableText(auth.enrollment!.secret,
              textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontFamily: 'monospace', fontSize: 12))),
            const SizedBox(height: 12),
          ],
          TextFormField(key: const ValueKey('verification-code'), controller: _code,
            enabled: !auth.busy, keyboardType: TextInputType.number, textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode], maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _input('Código de verificación', '000000', Icons.password_rounded).copyWith(counterText: ''),
            style: const TextStyle(color: _ink, fontSize: 21, letterSpacing: 7, fontWeight: FontWeight.w600),
            validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '') ? null : 'Escribe los seis dígitos del código.',
            onFieldSubmitted: (_) => _submit(auth)),
        ] else ...[
          if (!recovery || !auth.passwordRecoveryActive) TextFormField(
            key: const ValueKey('login-identifier'), controller: _email, enabled: !auth.busy,
            keyboardType: TextInputType.emailAddress, textInputAction: recovery ? TextInputAction.done : TextInputAction.next,
            autofillHints: const [AutofillHints.username], autocorrect: false,
            style: const TextStyle(color: _ink, fontSize: 14),
            decoration: _input(auth.config.testAccount && !recovery ? 'Usuario o correo' : 'Correo electrónico',
                'nombre@empresa.cl', Icons.alternate_email_rounded),
            validator: (v) {
              final value = (v ?? '').trim();
              if (!recovery && auth.config.isTestIdentifier(value)) return null;
              return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value) ? null : 'Escribe un correo válido.';
            },
            onFieldSubmitted: (_) { if (recovery) _submit(auth); }),
          if (!recovery || auth.passwordRecoveryActive) ...[
            if (!recovery) const SizedBox(height: 25),
            TextFormField(key: const ValueKey('login-password'), controller: _password, enabled: !auth.busy,
              obscureText: !_showPassword, enableSuggestions: false, autocorrect: false,
              autofillHints: [recovery ? AutofillHints.newPassword : AutofillHints.password],
              textInputAction: recovery ? TextInputAction.next : TextInputAction.done,
              style: const TextStyle(color: _ink, fontSize: 14),
              decoration: _input(recovery ? 'Nueva contraseña' : 'Contraseña', 'Escribe tu contraseña', Icons.lock_outline_rounded,
                suffix: IconButton(tooltip: _showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _muted, size: 20))),
              validator: (v) => (v ?? '').isEmpty ? 'Escribe tu contraseña.' :
                recovery && v!.length < 12 ? 'Usa al menos 12 caracteres.' : null,
              onFieldSubmitted: (_) { if (!recovery) _submit(auth); }),
            if (recovery) ...[
              const SizedBox(height: 24),
              TextFormField(controller: _confirm, enabled: !auth.busy, obscureText: true,
                enableSuggestions: false, autocorrect: false, autofillHints: const [AutofillHints.newPassword],
                decoration: _input('Confirma la contraseña', 'Repite tu nueva contraseña', Icons.lock_outline_rounded),
                validator: (v) => v == _password.text ? null : 'Las contraseñas deben coincidir.',
                onFieldSubmitted: (_) => _submit(auth)),
            ],
          ],
          if (!recovery) Align(alignment: Alignment.centerRight, child: TextButton(
            onPressed: auth.busy ? null : auth.showReset,
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF237B99), padding: const EdgeInsets.symmetric(vertical: 13)),
            child: const Text('Olvidé mi contraseña', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)))),
        ],
        SizedBox(height: mfa || recovery ? 26 : 8),
        SizedBox(height: 51, child: FilledButton(
          key: const ValueKey('login-submit'), onPressed: auth.busy ? null : () => _submit(auth),
          style: FilledButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF71889B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
          child: auth.busy ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 11), Text('Verificando…'),
          ]) : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(mfa ? 'Verificar y continuar' : recovery ? (auth.passwordRecoveryActive ? 'Guardar contraseña' : 'Enviar instrucciones') : 'Continuar',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 13), const Icon(Icons.arrow_forward_rounded, size: 18),
          ]))),
        if (mfa || recovery) TextButton(onPressed: auth.busy ? null : auth.backToLogin,
          child: const Text('Volver al inicio de sesión', style: TextStyle(color: _muted, fontSize: 12))),
      ])),
      if (phase == AuthPhase.chooseOrganization) ...[
        for (final org in auth.identity?.organizations ?? <OrganizationAccess>[]) Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton(onPressed: auth.busy ? null : () => auth.chooseOrganization(org),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(18), foregroundColor: _ink),
            child: Row(children: [const Icon(Icons.domain_outlined), const SizedBox(width: 12), Expanded(child: Text(org.name)), const Icon(Icons.arrow_forward, size: 17)]))),
      ],
      if (phase == AuthPhase.noMembership || phase == AuthPhase.connectionError) FilledButton(
        onPressed: auth.busy ? null : auth.checkSession,
        style: FilledButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
        child: Text(auth.busy ? 'Verificando…' : 'Volver a verificar')),
      if (phase == AuthPhase.emailVerification) OutlinedButton(onPressed: auth.busy ? null : auth.resendConfirmation,
        child: const Text('Reenviar confirmación')),
      if (blocked) TextButton(onPressed: auth.busy ? null : auth.signOut,
        child: const Text('Volver al inicio de sesión', style: TextStyle(color: _muted, fontSize: 12))),
      const SizedBox(height: 30),
      const Divider(height: 1, color: Color(0xFFE8EDF2)),
      const SizedBox(height: 20),
      const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.verified_user_outlined, size: 15, color: Color(0xFF7D95A8)), SizedBox(width: 9),
        Expanded(child: Text('Verificamos tu identidad antes de abrir tu información.',
          style: TextStyle(color: _muted, fontSize: 11, height: 1.6))),
      ]),
      const SizedBox(height: 20),
      const Text('¿Necesitas acceso? Contacta al administrador.', textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 11, height: 1.5)),
    ]));
  }

  Widget _notice(String value, {bool error = false}) => Container(
    key: ValueKey(error ? 'login-error' : 'login-notice'), margin: const EdgeInsets.only(bottom: 22),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: error ? const Color(0xFFFFF3F1) : const Color(0xFFEFF8FA), borderRadius: BorderRadius.circular(10)),
    child: Semantics(liveRegion: true, child: Text(value,
      style: TextStyle(color: error ? const Color(0xFF9E3535) : const Color(0xFF286B80), fontSize: 12, height: 1.55))),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 40, height: 40, decoration: BoxDecoration(border: Border.all(color: const Color(0xFF4D9AB8)), borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.auto_awesome_mosaic_outlined, color: Brand.accent2, size: 23)),
    const SizedBox(width: 13),
    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('DIRECTA', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: 4.5)),
      SizedBox(height: 4),
      Text('INTELIGENCIA DIRECTIVA', style: TextStyle(color: Color(0xFFA4C3D7), fontSize: 8, letterSpacing: 2.2)),
    ]),
  ]);
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) => DecoratedBox(
    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF102F4C), Color(0xFF081D32)])),
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _BrandLines())),
      Positioned.fill(child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(58, 48, 55, 35),
        child: ConstrainedBox(constraints: BoxConstraints(minHeight: math.max(0, size.maxHeight - 83)),
          child: IntrinsicHeight(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _BrandMark(),
            SizedBox(height: math.max(55, size.maxHeight * .12)),
            Container(width: 39, height: 3, color: Brand.accent2),
            const SizedBox(height: 26),
            const Text('Una visión clara.\nMejores decisiones.', style: TextStyle(color: Colors.white,
              fontSize: 43, fontWeight: FontWeight.w600, height: 1.18, letterSpacing: -1.4)),
            const SizedBox(height: 23),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 350), child: const Text(
              'Informes, análisis y memorias para acompañar la gestión y preparar cada decisión.',
              style: TextStyle(color: Color(0xFFB5C9D9), fontSize: 15, height: 1.8))),
            const SizedBox(height: 38),
            const _Feature(Icons.description_outlined, 'Información organizada'),
            const _Feature(Icons.insights_outlined, 'Análisis con perspectiva'),
            const _Feature(Icons.account_balance_outlined, 'Gestión para el directorio'),
            const Spacer(),
            const SizedBox(height: 50),
            const Text('GERENCIA GENERAL', style: TextStyle(color: Color(0xFF7FA3BD), fontSize: 9, letterSpacing: 2.3, fontWeight: FontWeight.w600)),
          ])),
        ),
      )),
    ]),
  ));
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 18),
    child: Row(children: [Icon(icon, color: const Color(0xFF6CC8E0), size: 18), const SizedBox(width: 13),
      Flexible(child: Text(text, style: const TextStyle(color: Color(0xFFD9E6EF), fontSize: 12, height: 1.5)))]));
}

class _BrandLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF8BB7D0).withValues(alpha: .07)..style = PaintingStyle.stroke..strokeWidth = 1;
    final center = Offset(size.width + 25, size.height * .78);
    for (final radius in [160.0, 240.0, 320.0, 400.0]) { canvas.drawCircle(center, radius, p); }
    p.color = const Color(0xFF6CC8E0).withValues(alpha: .09);
    canvas.drawLine(Offset(size.width * .7, size.height), Offset(size.width, size.height * .50), p);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
