import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/demo_offline.dart';

/// Comparación con la competencia (PANTALLA DE EJEMPLO).
///
/// El servidor todavía no tiene el módulo que lee la memoria de otra empresa, así que aquí solo se
/// muestra cómo se verá. Todo lo que aparece es ilustrativo y está marcado como "Modo demostración".
/// Cuando exista el módulo, esta pantalla se conecta a él y se quita el aviso.
class CompetenciaScreen extends StatelessWidget {
  const CompetenciaScreen({super.key});

  static const _areas = [
    ('Financiero', 61, 83),
    ('Riesgos', 77, 74),
    ('Ciberseguridad', 96, 70),
    ('Gobierno corporativo', 72, 78),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead(
        title: 'Comparar con competencia',
        subtitle: 'Basado solo en las memorias públicas de ambas empresas. No es una investigación de mercado.',
      ),
      const DemoAviso(text: 'Ejemplo de cómo se verá la comparación. Las cifras y empresas no son reales.'),
      GgCard(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SecTitle('Comparar con', bottom: 4, color: c.text3),
              const Text('Empresa Competidora S.A. · Memoria 2022', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            ]),
          ),
          const SizedBox(width: 8),
          GgButton('Cambiar', ghost: true, small: true, onTap: () {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AgregarCompetidorScreen()));
          }),
        ]),
      ),
      Row(children: [
        Expanded(child: _puntaje(context, 'TÚ', '72', 'Requiere revisión', c.accentText, destacado: true)),
        const SizedBox(width: 10),
        Expanded(child: _puntaje(context, 'COMPETIDOR', '81', 'Menor atención', Brand.purple)),
      ]),
      const SizedBox(height: 12),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: SecTitle('Por área', bottom: 0)),
            Text('● Tú  ', style: TextStyle(fontSize: 11, color: c.accentText)),
            Text('● Ellos', style: TextStyle(fontSize: 11, color: Brand.purple)),
          ]),
          const SizedBox(height: 12),
          for (final (nombre, tu, ellos) in _areas) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
              Text('$tu vs $ellos', style: TextStyle(fontSize: 12, color: c.text3)),
            ]),
            const SizedBox(height: 5),
            _barra(c, tu / 100, c.accentText),
            const SizedBox(height: 3),
            _barra(c, ellos / 100, Brand.purple),
            const SizedBox(height: 12),
          ],
        ]),
      ),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Brechas'),
          Text('Ellos informan y tú no', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.med)),
          const SizedBox(height: 6),
          _brecha(c, 'Medición de huella de carbono', 'su pág. 64'),
          const SizedBox(height: 12),
          Text('Tú informas y ellos no', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.low)),
          const SizedBox(height: 6),
          _brecha(c, 'Plan de continuidad operacional', 'tu pág. 38'),
        ]),
      ),
    ]);
  }

  Widget _puntaje(BuildContext context, String etiqueta, String valor, String estado, Color color, {bool destacado = false}) {
    final c = context.c;
    return GgCard(
      margin: EdgeInsets.zero,
      borderColor: destacado ? c.accentText : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(etiqueta, style: TextStyle(fontSize: 11, color: c.text3)),
        const SizedBox(height: 4),
        Text(valor, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, height: 1.1, color: destacado ? c.text : color)),
        const SizedBox(height: 2),
        Text(estado, style: TextStyle(fontSize: 11.5, color: c.text2)),
      ]),
    );
  }

  Widget _barra(GgColors c, double v, Color color) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(value: v, minHeight: 6, color: color, backgroundColor: c.track),
      );

  Widget _brecha(GgColors c, String texto, String pagina) => Row(children: [
        Expanded(child: Text(texto, style: const TextStyle(fontSize: 12.5, height: 1.35))),
        const SizedBox(width: 8),
        Pill(pagina, fg: c.text2, bg: c.surface2),
      ]);
}

/// Alta de un competidor (PANTALLA DE EJEMPLO): hoy no guarda nada.
class AgregarCompetidorScreen extends StatefulWidget {
  const AgregarCompetidorScreen({super.key});
  @override
  State<AgregarCompetidorScreen> createState() => _AgregarCompetidorScreenState();
}

class _AgregarCompetidorScreenState extends State<AgregarCompetidorScreen> {
  final _nombre = TextEditingController();
  final _enlace = TextEditingController();
  bool _porEnlace = true;

  @override
  void dispose() {
    _nombre.dispose();
    _enlace.dispose();
    super.dispose();
  }

  Widget _opcion(BuildContext context, {required bool activa, required IconData icono, required String titulo, required String detalle, required VoidCallback onTap, Widget? extra}) {
    final c = context.c;
    return GgCard(
      borderColor: activa ? c.accentText : c.border,
      color: activa ? c.accentSoft : null,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: activa ? Brand.accent2 : c.surface2, borderRadius: BorderRadius.circular(10)),
            child: Icon(icono, size: 19, color: activa ? Brand.onAccent : c.accentText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(detalle, style: TextStyle(fontSize: 11.5, color: c.text2)),
            ]),
          ),
        ]),
        if (extra != null) ...[const SizedBox(height: 10), extra],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Agregar competidor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
            const PageHead(
              title: '¿Con quién te comparas?',
              subtitle: 'Necesitas la memoria anual pública de la otra empresa. DIRECTA la analiza igual que la tuya.',
            ),
            const DemoAviso(text: 'Pantalla de ejemplo: todavía no guarda ni analiza documentos de otras empresas.'),
            TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre de la empresa', hintText: 'Empresa Competidora S.A.')),
            const SizedBox(height: 16),
            const SecTitle('¿Cómo la agregas?'),
            _opcion(
              context,
              activa: _porEnlace,
              icono: Icons.link,
              titulo: 'Pegar el enlace del PDF',
              detalle: 'DIRECTA lo descarga por ti',
              onTap: () => setState(() => _porEnlace = true),
              extra: _porEnlace
                  ? TextField(controller: _enlace, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://…/memoria-anual-2022.pdf'))
                  : null,
            ),
            _opcion(
              context,
              activa: !_porEnlace,
              icono: Icons.upload_file,
              titulo: 'Subir el PDF',
              detalle: 'Si ya lo tienes en tu teléfono',
              onTap: () => setState(() => _porEnlace = false),
            ),
            GgCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('¿Dónde encuentro la memoria?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Text('En la sección de inversionistas del sitio de la empresa, o en el sitio de la CMF (cmfchile.cl), donde cada sociedad abierta publica sus memorias.',
                    style: TextStyle(fontSize: 12, height: 1.5, color: c.text2)),
              ]),
            ),
            GgCard(
              borderColor: c.med.withValues(alpha: 0.4),
              color: c.med.withValues(alpha: 0.08),
              child: Text('Este documento queda aparte. No se mezcla con el análisis ni con la memoria de tu empresa.',
                  style: TextStyle(fontSize: 11.5, height: 1.45, color: c.text2)),
            ),
            const SizedBox(height: 4),
            GgButton('Agregar y analizar', icon: Icons.add, expand: true,
                onTap: () => st.toast('Esta función se activa cuando el servidor incluya el módulo de competencia.')),
          ]),
        ),
      ),
    );
  }
}
