import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../core/demo_modo.dart';
import '../core/servidor_estado.dart';
import '../core/theme.dart';
import '../core/bloqueo.dart';
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

  Future<void> _cerrarSesion() async {
    if (DemoModo.instance.activo) {
      DemoModo.instance.salir();
      return;
    }
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
            Text(titulo, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 1),
            Text(detalle, style: TextStyle(fontSize: 11.5, color: c.text3)),
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
            const Text('Cambiar contraseña', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text.rich(TextSpan(style: TextStyle(fontSize: 13.5, height: 1.5, color: context.c.text2), children: [
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

  // ---------- Bloqueo con PIN y huella ----------
  bool? _tienePin;
  bool _usaBio = false;
  bool _bioDisponible = false;

  Future<void> _cargarBloqueo() async {
    final uid = UsuarioActual.id;
    if (uid == null) return;
    final pin = await Bloqueo.tienePin(uid);
    final bio = await Bloqueo.usaBiometria(uid);
    final disp = await Bloqueo.biometriaDisponible();
    if (mounted) setState(() {
      _tienePin = pin;
      _usaBio = bio;
      _bioDisponible = disp;
    });
  }

  Future<void> _cambiarPin(bool activar) async {
    final uid = UsuarioActual.id;
    if (uid == null) return;
    final st = context.read<AppState>();
    if (activar) {
      final pin = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const CrearPinScreen()));
      if (pin == null) return;
      await Bloqueo.definirPin(uid, pin);
      st.toast('PIN activado. Lo pediremos al abrir DIRECTA.');
    } else {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ConfirmarPinScreen(uid: uid)));
      if (ok != true) return;
      await Bloqueo.quitar(uid);
      st.toast('Bloqueo desactivado');
    }
    await _cargarBloqueo();
  }

  Future<void> _cambiarBio(bool activar) async {
    final uid = UsuarioActual.id;
    if (uid == null) return;
    if (activar) {
      final ok = await Bloqueo.pedirBiometria(motivo: 'Confirma tu huella o rostro para activarlo');
      if (!ok) return;
    }
    await Bloqueo.setBiometria(uid, activar);
    await _cargarBloqueo();
  }

  Widget _seguridad(BuildContext context) {
    final c = context.c;
    final pin = _tienePin ?? false;
    Widget opcion({required IconData icon, required String titulo, required String detalle, required bool valor, ValueChanged<bool>? cambiar}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 21, color: c.accentText),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 1),
              Text(detalle, style: TextStyle(fontSize: 11.5, color: c.text3)),
            ])),
            Switch(value: valor, onChanged: cambiar),
          ]),
        );
    return GgCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Seguridad de la app'),
        opcion(
          icon: Icons.pin_outlined,
          titulo: 'PIN de acceso',
          detalle: 'Pide un PIN de 4 dígitos al abrir la app',
          valor: pin,
          cambiar: _tienePin == null ? null : _cambiarPin,
        ),
        opcion(
          icon: Icons.fingerprint_rounded,
          titulo: 'Huella o rostro',
          detalle: !_bioDisponible
              ? 'Este celular no tiene huella o rostro registrado'
              : pin ? 'Entrar con tu huella en vez del PIN' : 'Primero activa el PIN',
          valor: pin && _usaBio,
          cambiar: pin && _bioDisponible ? _cambiarBio : null,
        ),
      ]),
    );
  }

  Future<void> _editarPerfil() async {
    final nombre = TextEditingController(text: UsuarioActual.tieneNombre ? UsuarioActual.nombre : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tu nombre'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nombre, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nombre y apellido')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
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

  Widget _dato(BuildContext context, String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(fontSize: 10.5, color: context.c.text3)),
        Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final correo = Supabase.instance.client.auth.currentUser?.email;
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: c.accentSoft,
              child: DemoModo.instance.activo || UsuarioActual.iniciales.isEmpty
                  ? Icon(Icons.person_outline_rounded, color: c.accentText)
                  : Text(UsuarioActual.iniciales, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: c.accentText)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(DemoModo.instance.activo ? 'Modo demo' : UsuarioActual.nombre,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                if (!DemoModo.instance.activo && (UsuarioActual.cargo.isNotEmpty || UsuarioActual.empresa.isNotEmpty)) ...[
                  const SizedBox(height: 2),
                  Text([UsuarioActual.cargo, UsuarioActual.empresa].where((x) => x.isNotEmpty).join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.text2, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 2),
                Text(DemoModo.instance.activo ? 'Acceso demo · sin cuenta' : (correo ?? 'Sesión iniciada'), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.text3)),
              ]),
            ),
          ]),
          if (!DemoModo.instance.activo && (UsuarioActual.rut.isNotEmpty || UsuarioActual.rutEmpresa.isNotEmpty)) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 18, runSpacing: 6, children: [
              if (UsuarioActual.rut.isNotEmpty) _dato(context, 'RUT', UsuarioActual.rut),
              if (UsuarioActual.rutEmpresa.isNotEmpty) _dato(context, 'RUT empresa', UsuarioActual.rutEmpresa),
            ]),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (!DemoModo.instance.activo)
              GgButton(UsuarioActual.tieneNombre ? 'Editar nombre' : 'Agregar mi nombre', ghost: true, small: true, icon: Icons.edit_outlined, onTap: _editarPerfil),
            if (!DemoModo.instance.activo)
              GgButton('Cambiar contraseña', ghost: true, small: true, icon: Icons.lock_outline_rounded, onTap: _cambiarClave),
            GgButton(DemoModo.instance.activo ? 'Salir de la demo' : 'Cerrar sesión', ghost: true, small: true, icon: Icons.logout, onTap: _cerrarSesion),
          ]),
        ]),
      ),
      if (!DemoModo.instance.activo && UsuarioActual.id != null) _seguridad(context),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: SecTitle('Estado del sistema', bottom: 0)),
            if (revisado != null) Text('Actualizado ${_hora(revisado!)}', style: TextStyle(fontSize: 10.5, color: c.text3)),
            IconButton(
              tooltip: 'Revisar de nuevo',
              visualDensity: VisualDensity.compact,
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
                  style: TextStyle(fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: c.text3)),
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
            Text(aviso, style: TextStyle(fontSize: 12, color: c.med)),
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
            title: Text('Avanzado · dirección del servidor', style: TextStyle(fontSize: 13, color: c.text2)),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'URL del servidor', hintText: 'https://mi-servidor.onrender.com'),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                GgButton('Guardar y probar', icon: Icons.wifi_tethering, loading: probando, onTap: _guardar),
                GgButton('Valor por defecto', ghost: true, onTap: () => _url.text = Config.apiPorDefecto()),
              ]),
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
                  size: 12.5, color: c.text2),
            ],
          ),
        ),
      ),
    ]);
  }
}
