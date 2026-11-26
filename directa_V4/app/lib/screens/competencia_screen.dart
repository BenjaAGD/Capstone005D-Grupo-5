import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Comparación con la competencia.
///
/// El servidor todavía no tiene el módulo que lee la memoria de otra empresa, así que la pantalla
/// explica la función y permite preparar el alta, sin mostrar cifras inventadas.
class CompetenciaScreen extends StatelessWidget {
  const CompetenciaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead(
        title: 'Comparar con competencia',
        subtitle: 'Basado solo en las memorias públicas de ambas empresas. No es una investigación de mercado.',
      ),
      GgCard(
        child: EmptyState(
          icon: Icons.compare_arrows,
          title: 'Todavía no hay competidores',
          text: 'Agrega la memoria anual pública de otra empresa. La comparación por área y las brechas aparecerán '
              'cuando el servidor incluya el módulo de competencia.',
          action: GgButton('Agregar competidor', icon: Icons.add, expand: true, onTap: () {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AgregarCompetidorScreen()));
          }),
        ),
      ),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Qué vas a ver'),
          for (final (icono, texto) in const [
            (Icons.bar_chart_outlined, 'Puntaje por área de tu memoria y la de la otra empresa.'),
            (Icons.call_split, 'Temas que ellos informan y tú no, y al revés, con la página de origen.'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icono, size: 20, color: c.accentText),
                const SizedBox(width: 8),
                Expanded(child: Text(texto, style: TextStyle(fontSize: Fs.body, height: 1.45, color: c.text2))),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

/// Alta de un competidor: todavía no guarda nada (el servidor no tiene el módulo).
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
            width: 40, height: 40,
            decoration: BoxDecoration(color: activa ? Brand.accent2 : c.surface2, borderRadius: BorderRadius.circular(10)),
            child: Icon(icono, size: 20, color: activa ? Brand.onAccent : c.accentText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: Fs.body)),
              const SizedBox(height: 2),
              Text(detalle, style: TextStyle(fontSize: Fs.sm, color: c.text2)),
            ]),
          ),
        ]),
        if (extra != null) ...[const SizedBox(height: 8), extra],
      ]),
    );
  }

  void _agregar() {
    FocusScope.of(context).unfocus();
    context.read<AppState>().toast('Esta función se activa cuando el servidor incluya el módulo de competencia.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Agregar competidor', style: TextStyle(fontSize: Fs.reading, fontWeight: FontWeight.w700))),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const PageHead(
              title: '¿Con quién te comparas?',
              subtitle: 'Necesitas la memoria anual pública de la otra empresa. DIRECTA la analiza igual que la tuya.',
            ),
            TextField(
              controller: _nombre,
              textInputAction: _porEnlace ? TextInputAction.next : TextInputAction.done,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre de la empresa'),
            ),
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
                  ? TextField(
                      controller: _enlace,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      onSubmitted: (_) => _agregar(),
                      decoration: const InputDecoration(hintText: 'https://…/memoria-anual.pdf'),
                    )
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
                const Text('¿Dónde encuentro la memoria?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: Fs.body)),
                const SizedBox(height: 8),
                Text('En la sección de inversionistas del sitio de la empresa, o en el sitio de la CMF (cmfchile.cl), donde cada sociedad abierta publica sus memorias.',
                    style: TextStyle(fontSize: Fs.md, height: 1.5, color: c.text2)),
              ]),
            ),
            GgCard(
              borderColor: c.med.withValues(alpha: 0.4),
              color: c.med.withValues(alpha: 0.08),
              child: Text('Este documento queda aparte. No se mezcla con el análisis ni con la memoria de tu empresa.',
                  style: TextStyle(fontSize: Fs.sm, height: 1.45, color: c.text2)),
            ),
            const SizedBox(height: 8),
            GgButton('Agregar y analizar', icon: Icons.add, expand: true, onTap: _agregar),
          ],
        ),
      ),
    );
  }
}
