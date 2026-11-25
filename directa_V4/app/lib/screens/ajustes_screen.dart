import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../core/servidor_estado.dart';
import '../core/theme.dart';
import '../core/bloqueo.dart';
import '../core/rut.dart';
import '../core/usuario.dart';
import 'bloqueo_screen.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key});
  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  late final TextEditingController _url;
  String? estado;
  bool probando = false;
  bool revisando = false;
  Map<String, dynamic>? servidor;
  Duration? latencia;
  DateTime? revisado;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: context.read<AppState>().apiUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) => _estadoServidor());
    _cargarBloqueo();
  }

  Future<void> _estadoServidor() async {
    if (!mounted) return;
    setState(() => revisando = true);
    final reloj = Stopwatch()..start();
    try {
      final r = await context.read<AppState>().api.getJson('/api/estado', timeout: const Duration(seconds: 8));
      reloj.stop();
      if (!mounted) return;
      setState(() {
        servidor = r is Map ? Map<String, dynamic>.from(r) : null;
        latencia = reloj.elapsed;
        revisado = DateTime.now();
        revisando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        servidor = null;
        latencia = null;
        revisado = DateTime.now();
        revisando = false;
      });
    }
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() {
      probando = true;
      estado = null;
    });
    final st = context.read<AppState>();
    final err = await st.setApi(_url.text);
    ServidorEstado.instance.actualizarBase(st.apiUrl);
    if (!mounted) return;
    setState(() {
      probando = false;
      _url.text = st.apiUrl;
      estado = err == null ? '✓ Conectado. El servidor respondió correctamente.' : '✗ $err';
    });
    _estadoServidor();
  }

  /// Correo de la sesión actual (null si Supabase aún no está listo).
  String? _correoActual() {
    try {
      return Supabase.instance.client.auth.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  Future<void> _cerrarSesion() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cerrar sesión. Inténtalo nuevamente.')),
        );
      }
    }
  }

  String _hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  /// Qué hace cada proveedor, según lo que informa el servidor (no se supone: se lee de /api/estado).
  String _rolProveedor(String clave) {
    final ver = servidor?['verificador'];
    final escribe = ver is Map ? '${ver['modelo_escritor']}' : '';
    final verifica = ver is Map ? '${ver['modelo_verificador']}' : '';
    final roles = <String>[
      if (clave == escribe) 'Análisis y chat',
      if (clave == verifica) 'Verifica las respuestas',
      if (clave == 'nvidia') 'Búsqueda en documentos',
    ];
    return roles.isEmpty ? 'Respaldo' : roles.join(' · ');
  }

  Widget _fila(BuildContext context, {required IconData icon, required String titulo, required String detalle, required Widget estado, bool ultimo = false}) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: ultimo ? null : Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: c.accentText),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(fontSize: Fs.body, fontWeight: FontWeight.w600)),
            const SizedBox(height: 1),
            Text(detalle, style: TextStyle(fontSize: Fs.sm, color: c.text3)),
          ]),
        ),
        const SizedBox(width: 8),
        estado,
      ]),
    );
  }

  /// Cambiar contraseña: se manda un enlace al correo para confirmar que es la persona.
  Future<void> _cambiarClave() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Cambiar contraseña', style: TextStyle(fontSize: Fs.xl, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text.rich(TextSpan(style: TextStyle(fontSize: Fs.md, height: 1.5, color: context.c.text2), children: [
              const TextSpan(text: 'Por seguridad te enviaremos un enlace a '),
              TextSpan(text: UsuarioActual.correoOculto, style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: '. Ábrelo desde este celular y elige tu nueva contraseña.'),
            ])),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12), child: Text('Enviar enlace a mi correo'))),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final st = context.read<AppState>();
    try {
      await UsuarioActual.enviarEnlaceClave();
      st.toast('Enlace enviado. Revisa tu correo (y la carpeta spam).');
    } on AuthException catch (e) {
      st.toast(e.statusCode == '429' || (e.code ?? '').startsWith('over_')
          ? 'Ya enviamos un enlace hace poco. Espera un minuto y vuelve a intentar.'
          : 'No se pudo enviar el enlace: ${e.message}', err: true);
    } catch (_) {
      st.toast('No se pudo enviar el enlace. Revisa tu conexión.', err: true);
    }
  }

  // ---------- Bloqueo: PIN o huella (una sola forma) ----------
  ModoBloqueo? _modo;
  bool _bioDisponible = false;

  Future<void> _cargarBloqueo() async {
    final uid = UsuarioActual.id;
    if (uid == null) return;
    final m = await Bloqueo.modo(uid);
    final disp = await Bloqueo.biometriaDisponible();
    if (mounted) {
      setState(() {
        _modo = m;
        _bioDisponible = disp;
      });
    }
  }

  /// Antes de quitar o cambiar el bloqueo, confirma con la forma actual.
  Future<bool> _confirmarActual(String uid) async {
    switch (_modo) {
      case ModoBloqueo.pin:
        return await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ConfirmarPinScreen(uid: uid))) == true;
      case ModoBloqueo.huella:
        if (await Bloqueo.pedirBiometria(motivo: 'Confirma que eres tú para cambiar el bloqueo')) return true;
        if (!mounted) return false;
        // Si la huella falla, sirve el PIN de respaldo.
        return await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ConfirmarPinScreen(uid: uid))) == true;
      default:
        return true;
    }
  }

  Future<void> _elegirModo(ModoBloqueo nuevo) async {
    final uid = UsuarioActual.id;
    if (uid == null || nuevo == _modo) return;
    final st = context.read<AppState>();
    if (!await _confirmarActual(uid) || !mounted) return;
    switch (nuevo) {
      case ModoBloqueo.pin:
        if (_modo == ModoBloqueo.huella) {
          // Ya tiene PIN de respaldo: solo deja de usar la huella.
          await Bloqueo.usarSoloPin(uid);
        } else {
          final pin = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const CrearPinScreen()));
          if (pin == null) return;
          await Bloqueo.definirPin(uid, pin);
        }
        st.toast('Listo: pediremos tu PIN al abrir DIRECTA.');
      case ModoBloqueo.huella:
        if (!_bioDisponible) {
          st.toast('Este celular no tiene huella o rostro registrado.', err: true);
          return;
        }
        // La huella siempre tiene un PIN de respaldo por si no te reconoce.
        if (!await Bloqueo.tienePin(uid)) {
          if (!mounted) return;
          final pin = await Navigator.of(context).push<String>(
              MaterialPageRoute(builder: (_) => const CrearPinScreen(titulo: 'PIN de respaldo')));
          if (pin == null) return;
          await Bloqueo.definirPin(uid, pin);
        }
        if (!await Bloqueo.pedirBiometria(motivo: 'Confirma tu huella o rostro para activarlo')) {
          st.toast('No se activó la huella. Quedó activo tu PIN.', err: true);
          await _cargarBloqueo();
          return;
        }
        await Bloqueo.usarHuella(uid);
        st.toast('Listo: entrarás con tu huella. Si no te reconoce, te pediremos el PIN.');
      case ModoBloqueo.ninguno:
        await Bloqueo.quitar(uid);
        st.toast('Bloqueo desactivado');
    }
    await _cargarBloqueo();
  }

  Widget _seguridad(BuildContext context) {
    final c = context.c;
    final modo = _modo;
    Widget opcion(ModoBloqueo m, IconData icon, String titulo, String detalle, {bool activa = true}) {
      final sel = modo == m;
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          color: sel ? c.accentSoft : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: sel ? c.accentText : c.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: modo == null || !activa ? null : () => _elegirModo(m),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(children: [
                Icon(icon, size: 24, color: activa ? c.accentText : c.text3),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titulo, style: TextStyle(fontWeight: FontWeight.w700, fontSize: Fs.md, color: activa ? null : c.text3)),
                  const SizedBox(height: 1),
                  Text(detalle, style: TextStyle(fontSize: Fs.sm, color: c.text3)),
                ])),
                Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: sel ? c.accentText : c.text3, size: 20),
              ]),
            ),
          ),
        ),
      );
    }
    return GgCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Seguridad de la app', bottom: 2),
        Text('Elige cómo desbloquear DIRECTA al abrirla.', style: TextStyle(fontSize: Fs.sm, color: c.text3)),
        opcion(ModoBloqueo.huella, Icons.fingerprint_rounded, 'Huella o rostro',
            _bioDisponible ? 'Principal, con tu PIN de respaldo si no te reconoce' : 'Este celular no tiene huella registrada',
            activa: _bioDisponible),
        opcion(ModoBloqueo.pin, Icons.dialpad_rounded, 'PIN de 4 dígitos', 'Como en las apps de bancos'),
        opcion(ModoBloqueo.ninguno, Icons.lock_open_rounded, 'Sin bloqueo', 'Solo la contraseña al iniciar sesión'),
      ]),
    );
  }

  Future<void> _editarPerfil() async {
    final nombre = TextEditingController(text: UsuarioActual.tieneNombre ? UsuarioActual.nombre : '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(22, 0, 22, 18 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Tu nombre', style: TextStyle(fontSize: Fs.xl, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: nombre,
              textCapitalization: TextCapitalization.words,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.name],
              scrollPadding: const EdgeInsets.only(bottom: 120),
              onSubmitted: (_) => Navigator.pop(ctx, true),
              decoration: const InputDecoration(labelText: 'Nombre y apellido'),
            ),
            const SizedBox(height: 16),
            GgButton('Guardar', expand: true, onTap: () => Navigator.pop(ctx, true)),
            const SizedBox(height: 8),
            GgButton('Cancelar', ghost: true, expand: true, onTap: () => Navigator.pop(ctx, false)),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final st = context.read<AppState>();
    if (nombre.text.trim().isEmpty) {
      st.toast('Escribe tu nombre', err: true);
      return;
    }
    try {
      await UsuarioActual.guardar(nombre: nombre.text);
      if (mounted) setState(() {});
      st.toast('Perfil actualizado');
    } catch (_) {
      st.toast('No se pudo guardar el perfil. Revisa tu conexión.', err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final correo = _correoActual();
    final enLinea = servidor != null;
    final proveedores = servidor?['proveedores'];
    final persistencia = (servidor?['persistencia'] as Map?) ?? const {};
    final guardado = [
      for (final e in persistencia.entries)
        if (e.key != 'aviso' && e.key != 'error') e.value == 'supabase' ? 'Supabase' : 'archivo local'
    ].toSet();
    final aviso = '${persistencia['aviso'] ?? ''}';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: c.accentSoft,
              child: UsuarioActual.iniciales.isEmpty
                  ? Icon(Icons.person_outline_rounded, color: c.accentText)
                  : Text(UsuarioActual.iniciales, style: TextStyle(fontWeight: FontWeight.w800, fontSize: Fs.reading, color: c.accentText)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(UsuarioActual.nombre,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: Fs.lg)),
                if (UsuarioActual.cargo.isNotEmpty || UsuarioActual.empresa.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text([UsuarioActual.cargo, UsuarioActual.empresa].where((x) => x.isNotEmpty).join(' · '),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: Fs.md, color: c.text2, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 2),
                Text(correo ?? 'Sesión iniciada', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: Fs.sm, color: c.text3)),
              ]),
            ),
          ]),
          if (UsuarioActual.rut.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.badge_outlined, size: 18, color: c.text3),
                const SizedBox(width: 8),
                Text('RUT ${UsuarioActual.rut}', style: const TextStyle(fontSize: Fs.md, fontWeight: FontWeight.w600)),
              ]),
              if (Rut.esValido(UsuarioActual.rut))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E9E5B).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF2E9E5B)),
                    SizedBox(width: 4),
                    // Solo significa que el dígito verificador del RUT cuadra; no prueba que sea de la persona.
                    Text('RUT válido', style: TextStyle(fontSize: Fs.sm, fontWeight: FontWeight.w700, color: Color(0xFF2E9E5B))),
                  ]),
                ),
            ]),
            if (UsuarioActual.rutEmpresa.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.business_outlined, size: 18, color: c.text3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${UsuarioActual.empresa.isEmpty ? 'Empresa' : UsuarioActual.empresa} · RUT ${UsuarioActual.rutEmpresa}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: Fs.md, color: c.text2)),
                ),
              ]),
            ],
          ],
          const SizedBox(height: 16),
          GgButton(UsuarioActual.tieneNombre ? 'Editar nombre' : 'Agregar mi nombre', ghost: true, expand: true, icon: Icons.edit_outlined, onTap: _editarPerfil),
          const SizedBox(height: 8),
          GgButton('Cambiar contraseña', ghost: true, expand: true, icon: Icons.lock_outline_rounded, onTap: _cambiarClave),
          const SizedBox(height: 8),
          GgButton('Cerrar sesión', ghost: true, expand: true, icon: Icons.logout, onTap: _cerrarSesion),
        ]),
      ),
      if (UsuarioActual.id != null) _seguridad(context),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SecTitle('Estado del sistema', bottom: 0),
                if (revisado != null) Text('Actualizado ${_hora(revisado!)}', style: TextStyle(fontSize: Fs.xs, color: c.text3)),
              ]),
            ),
            IconButton(
              tooltip: 'Revisar de nuevo',
              onPressed: revisando ? null : _estadoServidor,
              icon: revisando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.refresh, size: 19, color: c.text2),
            ),
          ]),
          const SizedBox(height: 4),
          _fila(
            context,
            icon: Icons.dns_outlined,
            titulo: enLinea ? 'Servidor conectado' : (revisado == null ? 'Revisando el servidor…' : 'Servidor sin conexión'),
            detalle: enLinea
                ? 'Responde en ${((latencia?.inMilliseconds ?? 0) / 1000).toStringAsFixed(1)} s · versión ${servidor!['version'] ?? '?'}'
                : (revisado == null ? 'Un momento…' : 'Si es la primera vez en un rato, puede estar despertando.'),
            estado: Pill(enLinea ? 'EN LÍNEA' : (revisado == null ? 'REVISANDO' : 'SIN CONEXIÓN'),
                fg: enLinea ? c.low : (revisado == null ? c.text3 : c.crit), dot: true),
          ),
          if (enLinea && proveedores is Map) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text('INTELIGENCIA ARTIFICIAL',
                  style: TextStyle(fontSize: Fs.xs, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: c.text3)),
            ),
            for (final (clave, nombre) in const [('gemini', 'Gemini'), ('groq', 'Groq'), ('nvidia', 'NVIDIA')])
              _fila(
                context,
                icon: clave == 'nvidia' ? Icons.storage_outlined : Icons.auto_awesome_outlined,
                titulo: nombre,
                detalle: proveedores[clave] == true ? _rolProveedor(clave) : 'Sin llave configurada en el servidor',
                estado: Pill(proveedores[clave] == true ? 'CONECTADA' : 'NO CONFIGURADA',
                    fg: proveedores[clave] == true ? c.low : c.text3, dot: true),
              ),
          ] else if (enLinea) ...[
            _fila(
              context,
              icon: Icons.auto_awesome_outlined,
              titulo: 'Inteligencia artificial',
              detalle: 'Escribe: ${(servidor!['verificador'] as Map?)?['modelo_escritor'] ?? '?'} · '
                  'Verifica: ${(servidor!['verificador'] as Map?)?['modelo_verificador'] ?? '?'}',
              estado: Pill('ACTIVA', fg: c.low, dot: true),
            ),
          ],
          if (enLinea)
            _fila(
              context,
              icon: Icons.cloud_done_outlined,
              titulo: 'Guardado',
              detalle: guardado.isEmpty ? 'Sin información' : guardado.join(' · '),
              estado: Pill(guardado.contains('archivo local') ? 'LOCAL' : 'OK',
                  fg: guardado.contains('archivo local') ? c.med : c.low, dot: true),
              ultimo: true,
            ),
          if (aviso.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(aviso, style: TextStyle(fontSize: Fs.sm, color: c.med)),
          ],
        ]),
      ),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Apariencia'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: st.themeMode == ThemeMode.dark,
            onChanged: (_) => st.toggleTheme(),
            title: const Text('Tema oscuro'),
          ),
          Text('Tamaño de letra: ${(st.textScale * 100).round()}%', style: TextStyle(color: c.text2)),
          Slider(value: st.textScale, min: 0.8, max: 1.4, divisions: 6, activeColor: Brand.accent, onChanged: st.setTextScale),
        ]),
      ),
      GgCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(Icons.tune, color: c.text2, size: 20),
            title: Text('Avanzado · dirección del servidor', style: TextStyle(fontSize: Fs.md, color: c.text2)),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                onSubmitted: (_) => probando ? null : _guardar(),
                scrollPadding: const EdgeInsets.only(bottom: 160), // deja ver los botones con el teclado abierto
                decoration: const InputDecoration(labelText: 'URL del servidor', hintText: 'https://mi-servidor.onrender.com'),
              ),
              const SizedBox(height: 16),
              GgButton('Guardar y probar', icon: Icons.wifi_tethering, expand: true, loading: probando, onTap: _guardar),
              const SizedBox(height: 8),
              GgButton('Valor por defecto', ghost: true, expand: true, onTap: () => _url.text = Config.apiPorDefecto()),
              if (estado != null) ...[
                const SizedBox(height: 10),
                Text(estado!, style: TextStyle(color: estado!.startsWith('✓') ? c.low : c.crit, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 12),
              MarkdownLite(
                  '**¿Qué dirección uso?**\n'
                  '- Emulador de Android con Docker en el mismo computador: `http://10.0.2.2:8000`\n'
                  '- Teléfono real en la misma red WiFi: `http://IP-DEL-COMPUTADOR:8000` (por ejemplo 192.168.1.10)\n'
                  '- Servidor publicado en internet: su dirección `https://…`',
                  size: Fs.md, color: c.text2),
            ],
          ),
        ),
      ),
    ]);
  }
}
