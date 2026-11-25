import 'dart:async';
import 'dart:convert';
import 'dart:math' show max;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/saver.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../state/trabajo_memoria.dart';
import '../widgets/common.dart';
import '../widgets/demo_offline.dart';
import 'visor_pdf_screen.dart';

const _kMarca = 'directa_marca_memoria_v1';
const _coloresMarca = ['#1B2F4B', '#0E5A8A', '#0E7490', '#12AFC6', '#237AA8', '#4664A8'];

Color _hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));

const _tiposLocal = <Map<String, dynamic>>[
  {'id': 'integrada', 'nombre': 'Memoria integrada (NCG 461)', 'descripcion': 'Completa, con todos los capítulos que pide la norma de la CMF.', 'kicker': 'MEMORIA ANUAL INTEGRADA', 'titular': 'Un año de gestión responsable', 'capitulos': null},
  {'id': 'ejecutiva', 'nombre': 'Memoria ejecutiva', 'descripcion': 'Corta: carta, perfil, estrategia, negocio y cifras clave del año.', 'kicker': 'MEMORIA EJECUTIVA', 'titular': 'Lo esencial del año', 'capitulos': ['perfil', 'estrategia', 'negocios', 'financieros']},
  {'id': 'sostenibilidad', 'nombre': 'Sostenibilidad y ESG', 'descripcion': 'Personas, proveedores, estrategia climática e indicadores.', 'kicker': 'INFORME DE SOSTENIBILIDAD', 'titular': 'Impacto y sostenibilidad', 'capitulos': ['estrategia', 'personas', 'proveedores', 'indicadores', 'gobierno']},
  {'id': 'financiera', 'nombre': 'Memoria financiera', 'descripcion': 'Resultados, hechos relevantes, negocio e informes financieros.', 'kicker': 'MEMORIA FINANCIERA', 'titular': 'Resultados del ejercicio', 'capitulos': ['financieros', 'hechos', 'negocios', 'estrategia', 'comentarios']},
  {'id': 'gobierno', 'nombre': 'Gobierno corporativo y riesgos', 'descripcion': 'Directorio, comités, gestión de riesgos y cumplimiento.', 'kicker': 'GOBIERNO CORPORATIVO', 'titular': 'Gobierno y gestión de riesgos', 'capitulos': ['perfil', 'gobierno', 'comentarios', 'hechos']},
  {'id': 'directorio', 'nombre': 'Informe para el directorio', 'descripcion': 'Breve, con decisiones pendientes: gobierno, finanzas y hechos relevantes.', 'kicker': 'INFORME PARA EL DIRECTORIO', 'titular': 'Lo que el directorio debe saber', 'capitulos': ['gobierno', 'financieros', 'hechos']},
];

const _disenos = <Map<String, String>>[
  {'id': 'navy', 'nombre': 'Navy editorial', 'descripcion': 'Portada azul profundo, tipografía serif y trazo dorado.'},
  {'id': 'claro', 'nombre': 'Papel claro', 'descripcion': 'Fondo crema, título grande y año destacado.'},
  {'id': 'foto', 'nombre': 'Foto + bandas', 'descripcion': 'Foto arriba, banda cian y bloque de color de marca.'},
  {'id': 'minimal', 'nombre': 'Blanco minimal', 'descripcion': 'Blanco, líneas finas y año grande en el color de la marca.'},
  {'id': 'bloque', 'nombre': 'Bloque de color', 'descripcion': 'Franja vertical del color de la marca con el año; título a la derecha.'},
  {'id': 'gradiente', 'nombre': 'Degradado', 'descripcion': 'Degradado del color de la marca al cian, letras blancas.'},
];

IconData _iconoTipo(String id) => switch (id) {
      'ejecutiva' => Icons.bolt_outlined,
      'sostenibilidad' => Icons.eco_outlined,
      'financiera' => Icons.show_chart,
      'gobierno' => Icons.account_balance_outlined,
      'directorio' => Icons.groups_outlined,
      _ => Icons.menu_book_outlined,
    };

/// Vista previa de portada (A4) para los tres diseños.
class _PortadaMini extends StatelessWidget {
  const _PortadaMini({required this.diseno, required this.color, required this.titulo, required this.empresa, required this.anio, required this.kicker, this.logo});
  final String diseno, titulo, empresa, kicker;
  final Color color;
  final int anio;
  final String? logo;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.707,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LayoutBuilder(builder: (context, box) {
          final s = box.maxWidth / 220;
          TextStyle serif(double size, Color col) => TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold, fontSize: size * s, height: 1.08, color: col);
          TextStyle sans(double size, Color col, {bool b = false}) => TextStyle(fontSize: size * s, color: col, fontWeight: b ? FontWeight.w700 : FontWeight.w400, letterSpacing: .4 * s);
          final nombre = empresa.trim().isEmpty ? 'NOMBRE DE LA EMPRESA' : empresa.trim().toUpperCase();
          final logoW = logo == null
              ? const SizedBox.shrink()
              : Image.memory(base64Decode(logo!.split(',').last), width: 38 * s, height: 20 * s, fit: BoxFit.contain);
          if (diseno == 'claro') {
            return Container(
              color: const Color(0xFFFAF8F3),
              padding: EdgeInsets.all(16 * s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(child: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(6.5, color, b: true))),
                  logoW,
                ]),
                const Spacer(flex: 3),
                Text(kicker, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(5.5, const Color(0xFF0E7490), b: true)),
                SizedBox(height: 6 * s),
                Text(titulo, maxLines: 3, overflow: TextOverflow.ellipsis, style: serif(21, color)),
                SizedBox(height: 8 * s),
                Container(width: 30 * s, height: 2 * s, color: const Color(0xFFC9A24A)),
                const Spacer(flex: 4),
                Text('$anio', style: serif(40, const Color(0xFF0E7490))),
              ]),
            );
          }
          if (diseno == 'minimal') {
            return Container(
              color: Colors.white,
              padding: EdgeInsets.all(16 * s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 1 * s, color: color),
                SizedBox(height: 5 * s),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(child: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(6.5, color, b: true))),
                  logoW,
                ]),
                Align(alignment: Alignment.centerRight, child: Text('$anio', style: TextStyle(fontSize: 44 * s, color: color, height: 1.1))),
                const Spacer(flex: 2),
                Text(kicker, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(5.5, const Color(0xFF5F6877), b: true)),
                SizedBox(height: 5 * s),
                Text(titulo, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17 * s, fontWeight: FontWeight.w800, height: 1.1, color: const Color(0xFF1F2733))),
                const Spacer(flex: 3),
                Container(height: 1 * s, color: color),
              ]),
            );
          }
          if (diseno == 'bloque') {
            return Row(children: [
              Container(
                width: box.maxWidth * .36,
                color: color,
                alignment: Alignment.bottomCenter,
                padding: EdgeInsets.only(bottom: 12 * s),
                child: RotatedBox(quarterTurns: 3, child: Text('$anio', style: serif(30, Colors.white))),
              ),
              Container(width: 3 * s, color: const Color(0xFF18B9D2)),
              Expanded(child: Container(
                color: Colors.white,
                padding: EdgeInsets.all(10 * s),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(5.5, color, b: true)),
                  const Spacer(flex: 3),
                  Text(kicker, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(4.8, const Color(0xFF0E7490), b: true)),
                  SizedBox(height: 4 * s),
                  Text(titulo, maxLines: 4, overflow: TextOverflow.ellipsis, style: serif(14, const Color(0xFF1B2F4B))),
                  SizedBox(height: 5 * s),
                  Container(width: 22 * s, height: 2 * s, color: const Color(0xFFC9A24A)),
                  const Spacer(flex: 4),
                ]),
              )),
            ]);
          }
          if (diseno == 'gradiente') {
            return Container(
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [const Color(0xFF18B9D2), color])),
              padding: EdgeInsets.all(16 * s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(child: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(6.5, Colors.white, b: true))),
                  logoW,
                ]),
                const Spacer(flex: 3),
                Text(kicker, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(5.5, Colors.white, b: true)),
                SizedBox(height: 6 * s),
                Text(titulo, maxLines: 3, overflow: TextOverflow.ellipsis, style: serif(21, Colors.white)),
                const Spacer(flex: 3),
                Align(alignment: Alignment.bottomRight, child: Text('$anio', style: serif(26, Colors.white))),
              ]),
            );
          }
          if (diseno == 'foto') {
            return Column(children: [
              Expanded(flex: 5, child: SizedBox(width: double.infinity, child: Image.asset('assets/memoria_portada.jpg', fit: BoxFit.cover))),
              Container(height: 4 * s, color: const Color(0xFF18B9D2)),
              Expanded(flex: 5, child: Container(
                width: double.infinity,
                color: color,
                padding: EdgeInsets.all(14 * s),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(kicker, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(5.5, const Color(0xFF8DE4F0), b: true)),
                  SizedBox(height: 5 * s),
                  Text(titulo, maxLines: 3, overflow: TextOverflow.ellipsis, style: serif(17, Colors.white)),
                  SizedBox(height: 4 * s),
                  Text('$anio', style: serif(15, const Color(0xFF6DD7E8))),
                ]),
              )),
            ]);
          }
          return Container(
            color: color,
            padding: EdgeInsets.fromLTRB(16 * s, 16 * s, 14 * s, 14 * s),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 3 * s, height: 70 * s, margin: EdgeInsets.only(top: 60 * s, right: 10 * s), color: const Color(0xFF18B9D2)),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(child: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(6.5, Colors.white, b: true))),
                  logoW,
                ]),
                const Spacer(flex: 3),
                Text(kicker, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(5.5, const Color(0xFF8DE4F0), b: true)),
                SizedBox(height: 6 * s),
                Text(titulo, maxLines: 3, overflow: TextOverflow.ellipsis, style: serif(23, Colors.white)),
                SizedBox(height: 8 * s),
                Container(width: 30 * s, height: 2 * s, color: const Color(0xFFC9A24A)),
                SizedBox(height: 8 * s),
                Text('$anio', style: serif(16, const Color(0xFF6DD7E8))),
                const Spacer(flex: 4),
              ])),
            ]),
          );
        }),
      ),
    );
  }
}

/// "Borrador de memoria" en pasos: tipo, diseño, datos y generación del PDF.
class BorradorMemoria extends StatefulWidget {
  const BorradorMemoria({super.key, required this.caps});
  final Map<String, dynamic> Function() caps;
  @override
  State<BorradorMemoria> createState() => _BorradorMemoriaState();
}

class _BorradorMemoriaState extends State<BorradorMemoria> {
  List<Map<String, dynamic>> anios = [];
  int? anio;
  bool cargando = true, generando = false;
  String? error, logo;
  String color = _coloresMarca.first;
  String tipo = 'integrada', diseno = 'navy';
  int paso = 0;
  List<Map<String, dynamic>> tipos = List<Map<String, dynamic>>.from(_tiposLocal);
  final _hexCtrl = TextEditingController();
  final _nombre = TextEditingController();
  final _titulo = TextEditingController(text: 'Memoria anual');
  final _destinatario = TextEditingController(text: 'Gerencia General');
  final _firmante = TextEditingController(text: 'Gerente General');
  Map<String, dynamic>? progreso, resultado;
  Timer? _poll;

  AppState get st => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    final m = st.store.getJson<Map>(_kMarca, {});
    _nombre.text = '${m['nombre'] ?? ''}';
    _titulo.text = '${m['titulo'] ?? 'Memoria anual'}';
    _destinatario.text = '${m['destinatario'] ?? 'Gerencia General'}';
    _firmante.text = '${m['firmante'] ?? 'Gerente General'}';
    if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch('${m['color']}')) color = '${m['color']}'.toUpperCase();
    _hexCtrl.text = color;
    if (_tiposLocal.any((t) => t['id'] == m['tipo'])) tipo = '${m['tipo']}';
    if (_disenos.any((d) => d['id'] == m['diseno'])) diseno = '${m['diseno']}';
    logo = m['logo'] as String?;
    TrabajoMemoria.instance.addListener(_sincronizar);
    if (TrabajoMemoria.instance.corriendo || TrabajoMemoria.instance.resultado != null) paso = 3;
    _aplicarTrabajo(); // en initState no se puede usar setState
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  /// Copia el estado del trabajo de fondo (sigue corriendo aunque se salga de esta pantalla).
  void _aplicarTrabajo() {
    final t = TrabajoMemoria.instance;
    generando = t.corriendo;
    progreso = t.progreso;
    resultado = t.resultado;
    if (t.error != null) error = t.error;
  }

  void _sincronizar() {
    if (mounted) setState(_aplicarTrabajo);
  }

  @override
  void dispose() {
    _poll?.cancel();
    TrabajoMemoria.instance.removeListener(_sincronizar);
    _nombre.dispose();
    _titulo.dispose();
    _destinatario.dispose();
    _firmante.dispose();
    _hexCtrl.dispose();
    super.dispose();
  }

  void _guardarMarca() => st.store.setJson(_kMarca, {
    'nombre': _nombre.text.trim(), 'titulo': _titulo.text.trim(),
    'destinatario': _destinatario.text.trim(), 'firmante': _firmante.text.trim(),
    'color': color, 'tipo': tipo, 'diseno': diseno, if (logo != null) 'logo': logo,
  });

  Future<void> _cargar() async {
    try {
      final t = await st.api.getJson('/api/memoria/tipos', timeout: const Duration(seconds: 6));
      final lista = [for (final x in (t['tipos'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
      if (lista.isNotEmpty) {
        // El servidor define los capítulos; los textos de portada se completan con los locales.
        tipos = [
          for (final x in lista)
            {
              ...(_tiposLocal.firstWhere((l) => l['id'] == x['id'], orElse: () => const <String, dynamic>{})),
              ...x,
            }
        ];
      }
    } catch (_) {}
    try {
      final r = await st.api.getJson('/api/memoria/anios', timeout: const Duration(seconds: 6));
      anios = [for (final a in (r['anios'] as List? ?? const [])) if (a is Map) Map<String, dynamic>.from(a)];
      if (anios.isEmpty) {
        anio = null;
      } else if (anio == null || !anios.any((a) => (a['anio'] as num?)?.toInt() == anio)) {
        anio = (anios.first['anio'] as num).toInt();
      }
      error = null;
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => cargando = false);
  }

  Future<void> _elegirLogo() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg']);
    if (f == null) return;
    final bytes = await f.xFile.readAsBytes();
    if (bytes.length > 1500000) {
      st.toast('El logo debe pesar menos de 1,5 MB', err: true);
      return;
    }
    final tipo = f.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
    setState(() => logo = 'data:image/$tipo;base64,${base64Encode(bytes)}');
    _guardarMarca();
  }

  Future<void> _generar() async {
    if (anio == null || generando) return;
    _guardarMarca();
    setState(() => error = null);
    final propios = st.store.getJson<List>(Store.kIndPropios, const []);
    await TrabajoMemoria.instance.iniciar(st, {
      'anio': anio,
      'marca': {'nombre': _nombre.text.trim(), 'titulo': _titulo.text.trim(),
        'destinatario': _destinatario.text.trim(), 'firmante': _firmante.text.trim(),
        'color': color, if (logo != null) 'logo': logo},
      'tipo': tipo,
      'diseno': diseno,
      'caps': widget.caps(),
      'propios': propios,
    });
  }

  Map<String, dynamic> get _tipoSel => tipos.firstWhere((t) => t['id'] == tipo, orElse: () => tipos.first);

  Widget _stepper() {
    final c = context.c;
    const nombres = ['Tipo', 'Diseño', 'Datos', 'Generar'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < nombres.length; i++) ...[
          if (i > 0) Expanded(child: Padding(padding: const EdgeInsets.only(top: 12), child: Container(height: 2, color: i <= paso ? Brand.accent : c.border))),
          InkWell(
            onTap: () => setState(() => paso = i),
            child: Column(children: [
              Container(
                width: 26, height: 26, alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: i <= paso ? Brand.accent : c.surface2, border: Border.all(color: i <= paso ? Brand.accent : c.border2)),
                child: i < paso
                    ? const Icon(Icons.check, size: 15, color: Brand.onAccent)
                    : Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: i <= paso ? Brand.onAccent : c.text3)),
              ),
              const SizedBox(height: 4),
              Text(nombres[i], style: TextStyle(fontSize: 11, color: i == paso ? c.text : c.text3, fontWeight: i == paso ? FontWeight.w700 : FontWeight.w500)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _pasoTipo() {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SecTitle('¿Qué memoria quieres preparar?'),
      Text('Cada tipo usa capítulos, largo y tono distintos. Puedes cambiarlo cuando quieras.', style: TextStyle(color: c.text2, fontSize: 12.5, height: 1.4)),
      const SizedBox(height: 10),
      for (final t in tipos)
        GgCard(
          borderColor: tipo == t['id'] ? Brand.accent : null,
          onTap: () { setState(() { tipo = '${t['id']}'; resultado = null; }); _guardarMarca(); },
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(color: tipo == t['id'] ? Brand.accent : c.accentSoft, borderRadius: BorderRadius.circular(11)),
              child: Icon(_iconoTipo('${t['id']}'), color: tipo == t['id'] ? Brand.onAccent : c.accentText, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t['nombre']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 3),
              Text('${t['descripcion'] ?? ''}', style: TextStyle(color: c.text2, fontSize: 12, height: 1.35)),
              const SizedBox(height: 6),
              Text(t['capitulos'] == null ? 'Todos los capítulos de la norma' : '${(t['capitulos'] as List).length} capítulos', style: TextStyle(color: c.text3, fontSize: 11)),
            ])),
            if (tipo == t['id']) Icon(Icons.check_circle, color: c.accentText),
          ]),
        ),
    ]);
  }

  Widget _pasoDiseno(int anioPortada) {
    final c = context.c;
    final t = _tipoSel;
    final titulo = _titulo.text.trim().isEmpty || _titulo.text.trim() == 'Memoria anual' ? '${t['titular'] ?? 'Memoria anual'}' : _titulo.text.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Elige el diseño de tu memoria'),
        Text('Se aplica a la portada y a todos los capítulos.', style: TextStyle(color: c.text2, fontSize: 12.5)),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, box) {
          final ancho = (box.maxWidth - 16) / 3;
          return Wrap(spacing: 8, runSpacing: 12, children: [
            for (final d in _disenos)
              SizedBox(width: ancho, child: InkWell(
                onTap: () { setState(() => diseno = d['id']!); _guardarMarca(); },
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: diseno == d['id'] ? Brand.accent : c.border, width: diseno == d['id'] ? 2.5 : 1)),
                    child: _PortadaMini(diseno: d['id']!, color: _hex(color), titulo: titulo, empresa: _nombre.text, anio: anioPortada, kicker: '${t['kicker'] ?? 'MEMORIA ANUAL'}', logo: logo),
                  ),
                  const SizedBox(height: 6),
                  Text(d['nombre']!, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 11.5, fontWeight: diseno == d['id'] ? FontWeight.w700 : FontWeight.w500, color: diseno == d['id'] ? c.text : c.text2)),
                ]),
              )),
          ]);
        }),
        const SizedBox(height: 6),
        Text(_disenos.firstWhere((d) => d['id'] == diseno)['descripcion']!, style: TextStyle(color: c.text3, fontSize: 11.5)),
      ])),
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Color de marca y logo'),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final h in _coloresMarca)
            InkWell(
              onTap: () { setState(() { color = h; _hexCtrl.text = h; }); _guardarMarca(); },
              child: Container(width: 30, height: 30, decoration: BoxDecoration(color: _hex(h), shape: BoxShape.circle, border: Border.all(color: color == h ? c.text : c.border2, width: color == h ? 2.5 : 1))),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _hexCtrl,
          decoration: const InputDecoration(labelText: 'O pega el código del color de tu empresa', hintText: '#1B2F4B', prefixIcon: Icon(Icons.palette_outlined)),
          onChanged: (v) {
            final limpio = v.trim().toUpperCase();
            if (RegExp(r'^#[0-9A-F]{6}$').hasMatch(limpio)) {
              setState(() => color = limpio);
              _guardarMarca();
            }
          },
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          GgButton(logo == null ? 'Agregar logo' : 'Cambiar logo', icon: Icons.image_outlined, ghost: true, small: true, onTap: _elegirLogo),
          if (logo != null) TextButton(onPressed: () { setState(() => logo = null); _guardarMarca(); }, child: const Text('Quitar logo')),
        ]),
        const SizedBox(height: 4),
        Text('PNG o JPG, hasta 1,5 MB. Con fondo transparente se ve mejor.', style: TextStyle(color: c.text3, fontSize: 11.5)),
      ])),
    ]);
  }

  Widget _pasoDatos(int anioPortada, List docsAnio, List<int> opcionesAnio, Set<int> aniosDisponibles) {
    final c = context.c;
    return GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: SecTitle('Datos de la memoria')),
        if (cargando) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        if (!cargando && error != null) IconButton(tooltip: 'Reintentar conexión', onPressed: _cargar, icon: Icon(Icons.refresh, color: c.accentText)),
      ]),
      Text('Completa los datos editoriales. La empresa, el título y el destinatario se muestran en lugares distintos del libro.', style: TextStyle(color: c.text2, fontSize: 12.5, height: 1.4)),
      const SizedBox(height: 14),
      TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Empresa u organización', prefixIcon: Icon(Icons.business_outlined)), onChanged: (_) { _guardarMarca(); setState(() {}); }),
      const SizedBox(height: 10),
      TextField(controller: _titulo, decoration: InputDecoration(labelText: 'Título de portada', helperText: 'Si lo dejas como "Memoria anual", se usa el título del tipo elegido.', prefixIcon: const Icon(Icons.title)), onChanged: (_) { _guardarMarca(); setState(() {}); }),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, box) => Wrap(spacing: 10, runSpacing: 10, children: [
        SizedBox(width: box.maxWidth > 520 ? (box.maxWidth - 10) / 2 : box.maxWidth, child: DropdownButtonFormField<int>(
          value: opcionesAnio.contains(anioPortada) ? anioPortada : opcionesAnio.first,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Año del informe', prefixIcon: Icon(Icons.calendar_today_outlined)),
          items: opcionesAnio.map((a) => DropdownMenuItem(value: a, child: Text('$a${aniosDisponibles.contains(a) ? '' : ' · sin documentos'}', maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() { anio = v; resultado = null; error = null; }),
        )),
        SizedBox(width: box.maxWidth > 520 ? (box.maxWidth - 10) / 2 : box.maxWidth, child: TextField(controller: _destinatario, decoration: const InputDecoration(labelText: 'Preparada para', prefixIcon: Icon(Icons.person_outline)), onChanged: (_) { _guardarMarca(); setState(() {}); })),
      ])),
      const SizedBox(height: 6),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 16, color: c.text3),
        const SizedBox(width: 7),
        Expanded(child: Text(
          docsAnio.isEmpty
              ? 'Puedes elegir el año de portada. Para generar el borrador, debe haber al menos un documento procesado de ese período.'
              : 'Se incluirán solo documentos procesados de $anio. El documento activo de la barra superior no cambia.',
          style: TextStyle(color: c.text3, fontSize: 11.5, height: 1.35),
        )),
      ]),
      const SizedBox(height: 10),
      TextField(controller: _firmante, decoration: const InputDecoration(labelText: 'Nombre o cargo de quien firma', prefixIcon: Icon(Icons.draw_outlined)), onChanged: (_) => _guardarMarca()),
      if (error != null || anios.isEmpty) ...[
        const SizedBox(height: 12),
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(error == null ? Icons.info_outline : Icons.cloud_off_outlined, color: c.accentText, size: 19), const SizedBox(width: 8),
          Expanded(child: Text(error == null ? 'Aún no hay documentos procesados con un año identificable. Puedes preparar los datos y revisar la portada; la generación se activa cuando haya documentos.' : 'No hay conexión con el servidor. Tus datos de portada se guardan en este dispositivo y puedes seguir editándolos.', style: TextStyle(color: c.text2, fontSize: 12.5, height: 1.35))),
        ])),
      ],
    ]));
  }

  Widget _pasoGenerar(int anioPortada, List docsAnio, int terminados, int totalCaps) {
    final c = context.c;
    final t = _tipoSel;
    final dis = _disenos.firstWhere((d) => d['id'] == diseno);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Revisión antes de generar'),
        Row(children: [Icon(_iconoTipo(tipo), color: c.accentText), const SizedBox(width: 8), Expanded(child: Text('${t['nombre']} $anioPortada', style: const TextStyle(fontWeight: FontWeight.w700))), Pill(anios.isEmpty ? 'SIN DOCUMENTOS' : '${docsAnio.length} DOCUMENTOS', fg: anios.isEmpty ? c.med : c.low)]),
        const SizedBox(height: 8),
        Text('Diseño: ${dis['nombre']} · Empresa: ${_nombre.text.trim().isEmpty ? 'sin nombre' : _nombre.text.trim()}', style: TextStyle(color: c.text2, fontSize: 12.5)),
        const SizedBox(height: 10),
        // Solo un dato informativo (sin barra, para no confundirlo con el progreso de generación).
        if (totalCaps > 0) Text('Capítulos revisados en «Fuentes y avance»: $terminados de $totalCaps. Los no revisados salen con [COMPLETAR].', style: TextStyle(color: c.text3, fontSize: 12, height: 1.35)),
        const SizedBox(height: 8),
        Text(docsAnio.isEmpty ? 'No hay documentos procesados de $anio. Agrega documentos de este período para generar el borrador.' : 'Documentos incluidos: ${docsAnio.map((d) => d['nombre']).join(', ')}', style: TextStyle(color: c.text3, fontSize: 12, height: 1.35)),
        const SizedBox(height: 14),
        GgButton(generando ? 'Generando memoria…' : 'Generar borrador PDF', icon: Icons.picture_as_pdf_outlined, expand: true, loading: generando, onTap: anio == null || docsAnio.isEmpty ? null : _generar),
        const SizedBox(height: 8),
        Text('Puedes salir de esta pantalla: la memoria se sigue generando y te avisamos con una notificación. El PDF se guarda en Documentos/Directa Gerente General.', style: TextStyle(fontSize: 11.5, color: c.text3, height: 1.35)),
      ])),
      if (generando && progreso != null) GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${progreso!['paso'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 8), GgBar(value: ((progreso!['hechos'] as num?)?.toDouble() ?? 0) / max(1, (progreso!['total'] as num?)?.toDouble() ?? 1)), const SizedBox(height: 4), Text('${progreso!['hechos'] ?? 0} de ${progreso!['total'] ?? 1} pasos', style: TextStyle(fontSize: 11.5, color: c.text3))])),
      if (error != null && !cargando) GgCard(borderColor: c.crit, child: Text(error!, style: TextStyle(color: c.crit))),
      if (resultado != null) GgCard(borderColor: c.low, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.check_circle_outline, color: c.low), const SizedBox(width: 8), const Expanded(child: Text('Borrador PDF listo', style: TextStyle(fontWeight: FontWeight.w700)))]),
        const SizedBox(height: 6),
        Text('${resultado!['nombre'] ?? 'Memoria_borrador.pdf'} · ${(resultado!['revision'] as List? ?? const []).length} alertas de cifras. Revisa el archivo antes de aprobarlo.', style: TextStyle(fontSize: 12.5, color: c.text2)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          GgButton('Abrir PDF', icon: Icons.picture_as_pdf_outlined, small: true, onTap: () async {
            final a = ultimoArchivoGuardado();
            if (a == null) {
              st.go('archivos');
            } else {
              await VisorPdfScreen.abrir(context, a);
            }
          }),
          GgButton('Ver mis archivos', icon: Icons.folder_open_outlined, ghost: true, small: true, onTap: () => st.go('archivos')),
        ]),
      ])),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final anioPortada = anio ?? DateTime.now().year;
    final docsAnio = [for (final g in anios) if ((g['anio'] as num?)?.toInt() == anio) ...(g['documentos'] as List? ?? const [])];
    final aniosDisponibles = anios.map((x) => (x['anio'] as num).toInt()).toSet();
    final opcionesAnio = {...List.generate(DateTime.now().year - 2014, (i) => 2015 + i), ...aniosDisponibles}.toList()..sort((a, b) => b.compareTo(a));
    final caps = widget.caps();
    final terminados = caps.values.where((v) => v is Map && ['listo', 'completo', 'hecho'].contains('${v['estado']}'.toLowerCase())).length;
    final totalCaps = caps.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stepper(),
      if (paso == 0) _pasoTipo(),
      if (paso == 1) _pasoDiseno(anioPortada),
      if (paso == 2) _pasoDatos(anioPortada, docsAnio, opcionesAnio, aniosDisponibles),
      if (paso == 3) _pasoGenerar(anioPortada, docsAnio, terminados, totalCaps),
      const SizedBox(height: 4),
      Row(children: [
        if (paso > 0) TextButton.icon(onPressed: () => setState(() => paso -= 1), icon: const Icon(Icons.arrow_back, size: 18), label: const Text('Atrás')),
        const Spacer(),
        if (paso < 3) GgButton('Continuar', icon: Icons.arrow_forward, small: true, onTap: () => setState(() => paso += 1)),
      ]),
    ]);
  }
}

/// Perfil de tono (Frente D1): el Redactor lo extrae de memorias anteriores; el gerente lo corrige y aprueba.
class PerfilTono extends StatefulWidget {
  const PerfilTono({super.key});
  @override
  State<PerfilTono> createState() => _PerfilTonoState();
}

class _PerfilTonoState extends State<PerfilTono> {
  static const _textos = [
    ('persona', 'Persona y a quién se dirige'),
    ('formalidad', 'Formalidad'),
    ('largo_capitulos', 'Largo típico'),
    ('cifras', 'Cómo presenta las cifras'),
    ('cierres', 'Cómo cierra las secciones'),
  ];
  static const _listas = [
    ('vocabulario_frecuente', 'Vocabulario típico (separado por comas)'),
    ('vocabulario_evitar', 'Vocabulario a evitar (separado por comas)'),
    ('rasgos', 'Otros rasgos (separados por comas)'),
  ];
  Map<String, dynamic>? perfil;
  int minimo = 3;
  bool cargando = true, trabajando = false;
  final Set<String> seleccion = {};
  final Map<String, TextEditingController> ctrl = {};
  String? error;

  AppState get st => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    for (final (k, _) in [..._textos, ..._listas]) {
      ctrl[k] = TextEditingController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  @override
  void dispose() {
    for (final c in ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _llenar() {
    final p = (perfil?['perfil'] as Map?) ?? {};
    for (final (k, _) in _textos) {
      ctrl[k]!.text = '${p[k] ?? ''}';
    }
    for (final (k, _) in _listas) {
      ctrl[k]!.text = [for (final x in (p[k] as List? ?? const [])) '$x'].join(', ');
    }
  }

  Future<void> _cargar() async {
    try {
      final r = await st.api.getJson('/api/memoria/perfil-tono', timeout: const Duration(seconds: 6));
      if (r['ok'] != true) throw Exception(r['error']);
      perfil = r['perfil'] is Map ? Map<String, dynamic>.from(r['perfil'] as Map) : null;
      minimo = (r['minimo_memorias'] as num?)?.toInt() ?? 3;
      _llenar();
      error = null;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => cargando = false);
  }

  Map<String, dynamic> _editado() => {
        for (final (k, _) in _textos) k: ctrl[k]!.text.trim(),
        for (final (k, _) in _listas) k: [for (final x in ctrl[k]!.text.split(',')) if (x.trim().isNotEmpty) x.trim()],
      };

  Future<void> _accion(Future<dynamic> Function() f, String ok) async {
    setState(() => trabajando = true);
    try {
      final r = await f();
      if (r['ok'] != true) throw Exception(r['error'] ?? 'error');
      perfil = Map<String, dynamic>.from(r['perfil'] as Map);
      _llenar();
      st.toast(ok);
    } catch (e) {
      st.toast(e.toString().replaceFirst('Exception: ', ''), err: true);
    }
    if (mounted) setState(() => trabajando = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = context.watch<AppState>();
    if (cargando) return const GgCard(child: EmptyState(icon: Icons.hourglass_empty, title: 'Cargando…', loading: true));
    final docs = app.documentos.where((d) => !estadosProcesando.contains(d['estado'])).toList();
    final corpus = [for (final x in (perfil?['corpus'] as List? ?? const [])) if (x is Map) x];
    final medidas = (perfil?['medidas'] as Map?) ?? {};
    final aprobado = perfil?['estado'] == 'aprobado';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (perfil == null && docs.isEmpty) const DemoAviso(text: 'Ejemplo del perfil editorial. Para extraer un tono real necesitas memorias anteriores cargadas y conexión al servidor.'),
      if (perfil == null && docs.isEmpty) const GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SecTitle('Ejemplo de tono corporativo'),
        DemoFila(titulo: 'Formalidad', detalle: 'Profesional, directa y orientada a decisiones.'),
        DemoFila(titulo: 'Estilo', detalle: 'Frases claras, cifras acompañadas de contexto y próximos pasos explícitos.'),
        DemoFila(titulo: 'Regla editorial', detalle: 'Distinguir hechos, proyecciones y asuntos pendientes de validación.'),
      ])),
      if (error != null) GgCard(borderColor: c.crit, child: Text(error!, style: TextStyle(color: c.crit))),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Memorias anteriores para aprender el tono'),
          Text('Elige al menos $minimo memorias de años anteriores ya subidas. El Redactor describe su estilo sin copiar frases ni cifras.',
              style: TextStyle(fontSize: 12.5, color: c.text2)),
          const SizedBox(height: 8),
          for (final d in docs)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: seleccion.contains('${d['id']}'),
              onChanged: (v) => setState(() => v == true ? seleccion.add('${d['id']}') : seleccion.remove('${d['id']}')),
              title: Text(nombreDoc(d), style: const TextStyle(fontSize: 13)),
            ),
          const SizedBox(height: 8),
          GgButton(perfil == null ? 'Extraer perfil de tono' : 'Volver a extraer con estas memorias', icon: Icons.auto_awesome,
              loading: trabajando, onTap: seleccion.isEmpty ? null : () => _accion(
                  () => st.api.postJson('/api/memoria/perfil-tono/extraer', {'documentos': seleccion.toList()}),
                  'Perfil extraído: revísalo y apruébalo')),
        ]),
      ),
      if (perfil != null)
        GgCard(
          borderColor: aprobado ? c.low : c.med,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Perfil de tono v${perfil!['version']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              Pill(aprobado ? 'APROBADO' : 'BORRADOR', fg: aprobado ? c.low : c.med),
            ]),
            const SizedBox(height: 4),
            Text('Corpus: ${corpus.map((x) => '${x['nombre']}${x['anio'] != null ? ' (${x['anio']})' : ''}').join(', ')}',
                style: TextStyle(fontSize: 12, color: c.text3)),
            if ('${perfil!['aviso'] ?? ''}'.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('${perfil!['aviso']}', style: TextStyle(fontSize: 12, color: c.med))),
            const SizedBox(height: 12),
            KpiStrip(items: [
              (valor: '${medidas['palabras_por_oracion'] ?? '-'}', etiqueta: 'Palabras por oración', color: null, onTap: null),
              (valor: '${medidas['primera_persona_pct'] ?? '-'}%', etiqueta: 'Primera persona', color: null, onTap: null),
              (valor: '${medidas['tercera_persona_pct'] ?? '-'}%', etiqueta: '«La Compañía»', color: null, onTap: null),
            ]),
            for (final (k, l) in _textos) ...[
              TextField(controller: ctrl[k], minLines: 1, maxLines: 3, decoration: InputDecoration(labelText: l)),
              const SizedBox(height: 12),
            ],
            for (final (k, l) in _listas) ...[
              TextField(controller: ctrl[k], minLines: 1, maxLines: 3, decoration: InputDecoration(labelText: l)),
              const SizedBox(height: 12),
            ],
            if ((medidas['terminos_frecuentes'] as List? ?? const []).isNotEmpty)
              Text('Términos más frecuentes (medidos): ${(medidas['terminos_frecuentes'] as List).take(10).join(', ')}',
                  style: TextStyle(fontSize: 11.5, color: c.text3)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              GgButton('Guardar cambios', icon: Icons.save_outlined, ghost: true, small: true, loading: trabajando,
                  onTap: () => _accion(() => st.api.putJson('/api/memoria/perfil-tono/${perfil!['id']}', {'perfil': _editado()}),
                      'Cambios guardados')),
              GgButton(aprobado ? 'Aprobado' : 'Aprobar perfil', icon: Icons.verified_outlined, small: true, loading: trabajando,
                  onTap: aprobado ? null : () => _accion(
                      () => st.api.putJson('/api/memoria/perfil-tono/${perfil!['id']}', {'perfil': _editado(), 'aprobar': true}),
                      'Perfil aprobado: los borradores lo usarán')),
            ]),
            const SizedBox(height: 16),
            const SecTitle('Sumar una memoria aprobada al corpus'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in docs.where((d) => !corpus.any((x) => x['document_id'] == d['id'])))
                ChipBtn(nombreDoc(d), on: false, maxWidth: 260, onTap: () => _accion(
                    () => st.api.postJson('/api/memoria/perfil-tono/corpus', {'document_id': d['id']}),
                    'Memoria sumada: el perfil nuevo queda en borrador para aprobar')),
            ]),
          ]),
        ),
    ]);
  }
}
