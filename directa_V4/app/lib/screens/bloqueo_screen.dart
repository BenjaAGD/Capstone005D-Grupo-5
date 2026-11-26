import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/bloqueo.dart';
import '../core/theme.dart';
import '../core/usuario.dart';

const _navy = Color(0xFF12324B);
const _cyan = Color(0xFF12AFC6);

/// Envuelve la app: si el usuario activó el PIN, la tapa al abrir
/// y cuando vuelve después de [Bloqueo.volverABloquear] en segundo plano.
class BloqueoGate extends StatefulWidget {
  const BloqueoGate({super.key, required this.uid, required this.child});
  final String? uid;
  final Widget child;

  @override
  State<BloqueoGate> createState() => _BloqueoGateState();
}

class _BloqueoGateState extends State<BloqueoGate> with WidgetsBindingObserver {
  bool _bloqueada = false;
  bool _revisado = false;
  DateTime? _salio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _revisar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _revisar() async {
    final uid = widget.uid;
    final activo = uid != null && await Bloqueo.modo(uid) != ModoBloqueo.ninguno;
    if (mounted) {
      setState(() {
        _bloqueada = activo;
        _revisado = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _salio ??= DateTime.now();
    } else if (s == AppLifecycleState.resumed) {
      final salio = _salio;
      _salio = null;
      if (salio != null && DateTime.now().difference(salio) >= Bloqueo.volverABloquear && !_bloqueada) {
        _revisar();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mientras revisa (milisegundos) no muestra nada para no dejar ver los datos.
    if (!_revisado && widget.uid != null) return const ColoredBox(color: _navy);
    return Stack(children: [
      widget.child,
      if (_bloqueada && widget.uid != null)
        Positioned.fill(
          child: PantallaBloqueo(uid: widget.uid!, onAbierta: () => setState(() => _bloqueada = false)),
        ),
    ]);
  }
}

/// Pantalla que pide PIN o huella.
class PantallaBloqueo extends StatefulWidget {
  const PantallaBloqueo({super.key, required this.uid, required this.onAbierta});
  final String uid;
  final VoidCallback onAbierta;

  @override
  State<PantallaBloqueo> createState() => _PantallaBloqueoState();
}

class _PantallaBloqueoState extends State<PantallaBloqueo> {
  String _pin = '';
  String? _error;
  bool _bio = false;
  bool _listo = false;
  bool _tieneHuella = false;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final usa = await Bloqueo.modo(widget.uid) == ModoBloqueo.huella;
    if (!mounted) return;
    setState(() {
      _bio = usa;
      _tieneHuella = usa;
      _listo = true;
    });
  }

  Future<void> _huella() async {
    if (_ocupado) return;
    _ocupado = true;
    final ok = await Bloqueo.pedirBiometria();
    _ocupado = false;
    if (!mounted) return;
    if (ok) {
      widget.onAbierta();
    } else {
      // No se reconoció (o se canceló): pasa al PIN de respaldo.
      setState(() {
        _bio = false;
        _error = 'No pudimos verificar tu huella. Ingresa tu PIN.';
      });
    }
  }

  Future<void> _tecla(String t) async {
    if (_ocupado) return;
    HapticFeedback.selectionClick();
    if (t == '<') {
      if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
      return;
    }
    if (_pin.length >= Bloqueo.largoPin) return;
    setState(() {
      _pin += t;
      _error = null;
    });
    if (_pin.length < Bloqueo.largoPin) return;
    _ocupado = true;
    final ok = await Bloqueo.verificarPin(widget.uid, _pin);
    _ocupado = false;
    if (!mounted) return;
    if (ok) {
      widget.onAbierta();
      return;
    }
    final quedan = await Bloqueo.intentosRestantes(widget.uid);
    if (quedan <= 0) {
      // Primero se cierra la sesión; el PIN solo se borra cuando ya no hay sesión. Si el cierre falla
      // (por ejemplo sin internet), el PIN se conserva y la app sigue bloqueada: nunca queda abierta.
      if (await _salir()) await Bloqueo.quitar(widget.uid);
      if (mounted) {
        setState(() {
          _pin = '';
          _error = 'Demasiados intentos. Cierra la sesión e inicia de nuevo con tu contraseña.';
        });
      }
      return;
    }
    HapticFeedback.heavyImpact();
    if (mounted) {
      setState(() {
        _pin = '';
        _error = 'PIN incorrecto · te quedan $quedan ${quedan == 1 ? 'intento' : 'intentos'}';
      });
    }
  }

  /// Cierra la sesión: para volver hay que entrar con correo y contraseña.
  /// Devuelve true si ya no queda sesión guardada en el celular.
  Future<bool> _salir() async {
    final auth = Supabase.instance.client.auth;
    try {
      // scope local: borra la sesión del celular sin depender de la red.
      await auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
    return auth.currentSession == null;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _navy,
      child: SafeArea(
        // Con letra grande o teclado abierto la pantalla se desplaza en vez de desbordar.
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(height: 18),
                const _Logo(),
                const SizedBox(height: 8),
                Text('Hola, ${UsuarioActual.primerNombre}', style: const TextStyle(color: Color(0xFFA9C1D6), fontSize: Fs.body)),
                const SizedBox(height: 24),
                if (!_listo)
                  const SizedBox.shrink()
                else if (_bio) ...[
                  // Modo huella: un solo botón grande, sin teclado.
                  Material(
                    color: _cyan.withValues(alpha: .12),
                    shape: const CircleBorder(side: BorderSide(color: _cyan, width: 2)),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _huella,
                      child: const SizedBox(
                        width: 104,
                        height: 104,
                        child: Icon(Icons.fingerprint_rounded, size: 58, color: _cyan),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('Toca para desbloquear', style: TextStyle(color: Colors.white, fontSize: Fs.xl, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('Usa tu huella o tu rostro', style: TextStyle(color: Color(0xFFA9C1D6), fontSize: Fs.md)),
                  const SizedBox(height: 26),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => setState(() => _bio = false),
                    icon: const Icon(Icons.dialpad_rounded, size: 18),
                    label: const Text('Usar mi PIN'),
                  ),
                ] else ...[
                  Icon(Icons.lock_outline_rounded, color: _cyan.withValues(alpha: .9), size: 26),
                  const SizedBox(height: 10),
                  const Text('Ingresa tu PIN', style: TextStyle(color: Colors.white, fontSize: Fs.xl, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 18),
                  PuntosPin(largo: _pin.length, claro: true),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 34),
                    child: Center(
                      child: Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFB4A8), fontSize: Fs.md)),
                    ),
                  ),
                  TecladoPin(
                    claro: true,
                    onTecla: _tecla,
                    extra: _tieneHuella
                        ? IconButton(
                            iconSize: 30,
                            onPressed: () {
                              setState(() {
                                _bio = true;
                                _error = null;
                              });
                              _huella();
                            },
                            icon: const Icon(Icons.fingerprint_rounded, color: _cyan),
                          )
                        : null,
                  ),
                ],
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _salir,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text('¿Olvidaste tu PIN? Entrar con mi contraseña',
                      textAlign: TextAlign.center, style: TextStyle(color: _cyan, fontWeight: FontWeight.w700, fontSize: Fs.md)),
                ),
              ]),
            ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => RichText(
        text: const TextSpan(
          style: TextStyle(fontSize: Fs.display, fontWeight: FontWeight.w800, letterSpacing: 4, color: Colors.white),
          children: [TextSpan(text: 'DIREC'), TextSpan(text: 'TA', style: TextStyle(color: _cyan))],
        ),
      );
}

/// Los 4 círculos del PIN.
class PuntosPin extends StatelessWidget {
  const PuntosPin({super.key, required this.largo, this.claro = false});
  final int largo;
  final bool claro;
  @override
  Widget build(BuildContext context) {
    final borde = claro ? Colors.white70 : Theme.of(context).colorScheme.outline;
    final lleno = claro ? _cyan : Theme.of(context).colorScheme.primary;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < Bloqueo.largoPin; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 9),
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < largo ? lleno : Colors.transparent,
            border: Border.all(color: i < largo ? lleno : borde, width: 1.6),
          ),
        ),
    ]);
  }
}

/// Teclado numérico grande, como en las apps de bancos.
class TecladoPin extends StatelessWidget {
  const TecladoPin({super.key, required this.onTecla, this.extra, this.claro = false});
  final void Function(String) onTecla;
  final Widget? extra;
  final bool claro;

  @override
  Widget build(BuildContext context) {
    final color = claro ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final fondo = claro ? Colors.white.withValues(alpha: .08) : Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget tecla(String t) => Padding(
          padding: const EdgeInsets.all(6),
          child: Material(
            color: fondo,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onTecla(t),
              child: SizedBox(
                width: 64,
                height: 64,
                child: Center(child: Text(t, style: TextStyle(fontSize: Fs.display, fontWeight: FontWeight.w600, color: color))),
              ),
            ),
          ),
        );
    Widget hueco(Widget? w) => SizedBox(width: 76, height: 76, child: Center(child: w));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final fila in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
        Row(mainAxisSize: MainAxisSize.min, children: [for (final t in fila) tecla(t)]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        hueco(extra),
        tecla('0'),
        hueco(IconButton(
          onPressed: () => onTecla('<'),
          icon: Icon(Icons.backspace_outlined, color: color.withValues(alpha: .8)),
        )),
      ]),
    ]);
  }
}

/// Crear (o confirmar) un PIN nuevo. Devuelve el PIN con Navigator.pop.
class CrearPinScreen extends StatefulWidget {
  const CrearPinScreen({super.key, this.titulo = 'Crea tu PIN'});
  final String titulo;
  @override
  State<CrearPinScreen> createState() => _CrearPinScreenState();
}

class _CrearPinScreenState extends State<CrearPinScreen> {
  String _pin = '';
  String? _primero;
  String? _error;

  static bool _debil(String p) => RegExp(r'^(\d)\1{3}$').hasMatch(p) || '0123456789'.contains(p) || '9876543210'.contains(p);

  void _tecla(String t) {
    HapticFeedback.selectionClick();
    if (t == '<') {
      if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
      return;
    }
    if (_pin.length >= Bloqueo.largoPin) return;
    setState(() {
      _pin += t;
      _error = null;
    });
    if (_pin.length < Bloqueo.largoPin) return;
    if (_primero == null) {
      if (_debil(_pin)) {
        setState(() {
          _pin = '';
          _error = 'Ese PIN es muy fácil de adivinar. Prueba otro.';
        });
        return;
      }
      setState(() {
        _primero = _pin;
        _pin = '';
      });
    } else if (_pin == _primero) {
      Navigator.of(context).pop(_pin);
    } else {
      setState(() {
        _primero = null;
        _pin = '';
        _error = 'Los PIN no coinciden. Empecemos de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.pin_outlined, size: 30, color: t.colorScheme.primary),
                const SizedBox(height: 10),
                Text(_primero == null ? 'Elige un PIN de ${Bloqueo.largoPin} dígitos' : 'Repite tu PIN',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: Fs.xl, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text('Lo pediremos cada vez que abras DIRECTA.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: Fs.md, color: t.colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(height: 20),
                PuntosPin(largo: _pin.length),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Center(child: Text(_error ?? '', textAlign: TextAlign.center, style: TextStyle(color: t.colorScheme.error, fontSize: Fs.md))),
                  ),
                ),
                TecladoPin(onTecla: _tecla),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pide el PIN actual (para desactivar el bloqueo). Devuelve true si es correcto.
class ConfirmarPinScreen extends StatefulWidget {
  const ConfirmarPinScreen({super.key, required this.uid});
  final String uid;
  @override
  State<ConfirmarPinScreen> createState() => _ConfirmarPinScreenState();
}

class _ConfirmarPinScreenState extends State<ConfirmarPinScreen> {
  String _pin = '';
  String? _error;

  Future<void> _tecla(String t) async {
    if (t == '<') {
      if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
      return;
    }
    if (_pin.length >= Bloqueo.largoPin) return;
    setState(() => _pin += t);
    if (_pin.length < Bloqueo.largoPin) return;
    final ok = await Bloqueo.verificarPin(widget.uid, _pin);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _pin = '';
        _error = 'PIN incorrecto';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Confirma tu PIN')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Ingresa tu PIN actual', style: TextStyle(fontSize: Fs.xl, fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                PuntosPin(largo: _pin.length),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Center(child: Text(_error ?? '', textAlign: TextAlign.center, style: TextStyle(color: t.colorScheme.error, fontSize: Fs.md))),
                ),
                TecladoPin(onTecla: _tecla),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
