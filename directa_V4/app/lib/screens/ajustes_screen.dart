import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/theme.dart';
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
  Map<String, dynamic>? servidor;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: context.read<AppState>().apiUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) => _estadoServidor());
  }

  Future<void> _estadoServidor() async {
    try {
      final r = await context.read<AppState>().api.getJson('/api/estado', timeout: const Duration(seconds: 8));
      if (mounted && r is Map) setState(() => servidor = Map<String, dynamic>.from(r));
    } catch (_) {
      if (mounted) setState(() => servidor = null);
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
    final err = await context.read<AppState>().setApi(_url.text);
    if (!mounted) return;
    setState(() {
      probando = false;
      _url.text = context.read<AppState>().apiUrl;
      estado = err == null ? '✓ Conectado. El servidor respondió correctamente.' : '✗ $err';
    });
    _estadoServidor();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead(title: 'Servidor y apariencia'),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Dirección del backend'),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'URL del servidor', hintText: 'http://192.168.1.10:8000'),
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
        ]),
      ),
      if (servidor != null)
        GgCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SecTitle('Servidor conectado'),
            KvRow('Versión', '${servidor!['version'] ?? '?'}'),
            KvRow('Escribe', '${(servidor!['verificador'] as Map?)?['modelo_escritor'] ?? '?'}'),
            KvRow('Verifica', '${(servidor!['verificador'] as Map?)?['modelo_verificador'] ?? '?'}'
                '${(servidor!['verificador'] as Map?)?['chat'] == false ? ' (desactivado en el chat)' : ''}'),
            KvRow('Guardado', [
              for (final e in ((servidor!['persistencia'] as Map?) ?? {}).entries)
                if (e.key != 'aviso' && e.key != 'error') '${e.key}: ${e.value == 'supabase' ? 'Supabase' : 'archivo local'}'
            ].join(' · '), last: true),
            if ('${(servidor!['persistencia'] as Map?)?['aviso'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${(servidor!['persistencia'] as Map)['aviso']}', style: TextStyle(fontSize: 12, color: c.med)),
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
    ]);
  }
}
