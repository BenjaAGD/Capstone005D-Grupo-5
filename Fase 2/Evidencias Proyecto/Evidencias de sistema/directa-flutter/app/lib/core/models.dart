/// Agente del backend (agentes.py). La lista local es la misma del index.html y se actualiza con /api/agentes.
class Agente {
  Agente(this.key, this.name, this.badge, this.tipo, this.ola, this.desc);
  final String key, name, badge, desc;
  String tipo;
  int ola;
}

List<Agente> agentesIniciales() => [
      Agente('financiero', 'Financiero', 'FIN', 'productor', 1, 'Márgenes, liquidez, covenants, calidad de resultados y disciplina presupuestaria.'),
      Agente('ciberseguridad', 'Ciberseguridad', 'CYB', 'productor', 1, 'Postura de seguridad, incidentes, hallazgos de pentest y cumplimiento normativo.'),
      Agente('auditoria', 'Auditoría', 'AUD', 'productor', 2, 'Hallazgos de auditoría interna/externa, provisiones y controles internos.'),
      Agente('legal', 'Legal', 'LEG', 'productor', 2, 'Contingencias legales, litigios, cumplimiento regulatorio y contratos relevantes.'),
      Agente('capital', 'Asignación de Capital', 'CAP', 'productor', 2, 'CAPEX, retorno sobre capital invertido, escenarios y disciplina de inversión.'),
      Agente('operaciones', 'Operaciones', 'OPS', 'productor', 2, 'Continuidad operativa, cadena de suministro, productividad y dependencias.'),
      Agente('comercial', 'Comercial', 'COM', 'productor', 3, 'Pipeline, concentración de clientes, pricing y desempeño de ventas.'),
      Agente('rrhh', 'RRHH', 'HR', 'productor', 3, 'Rotación, clima, sucesión de ejecutivos clave y capacidades críticas.'),
      Agente('tecnologia', 'Tecnología', 'TEC', 'productor', 3, 'Deuda técnica, proyectos TI, obsolescencia y dependencia de proveedores.'),
      Agente('compensacion', 'Compensación', 'CMP', 'productor', 3, 'Alineación de incentivos, benchmarks de compensación y metas ejecutivas.'),
      Agente('esg', 'ESG', 'ESG', 'productor', 4, 'Sostenibilidad, emisiones, cumplimiento NCG 461 y riesgos climáticos.'),
      Agente('stakeholders', 'Stakeholders', 'STK', 'productor', 4, 'Reputación, comunidades, reguladores, medios y relación con accionistas.'),
      Agente('riesgos', 'Riesgos', 'RSK', 'integrador', 5, 'Correlaciona las señales de los agentes especialistas contra la matriz de riesgos.'),
      Agente('estrategia', 'Estrategia', 'EST', 'integrador', 5, 'Coherencia entre plan estratégico, recursos y señales del negocio.'),
    ];

/// Mensaje del chat ("Preguntar a IA").
class ChatMsg {
  ChatMsg({
    required this.id,
    required this.rol,
    this.texto = '',
    this.agente = '',
    this.agenteKey = 'general',
    List<Map<String, dynamic>>? fuentes,
    this.streaming = false,
    this.error = false,
  }) : fuentes = fuentes ?? [];

  final String id, rol; // rol: "me" | "ai"
  String texto, agente, agenteKey;
  List<Map<String, dynamic>> fuentes;
  bool streaming, error;

  Map<String, dynamic> toJson() => {
        'id': id, 'rol': rol, 'texto': texto, 'agente': agente, 'agente_key': agenteKey, 'error': error,
        'fuentes': [
          for (final f in fuentes)
            {'pagina': f['pagina'], 'preview': (f['preview'] ?? '').toString().substring(0, ((f['preview'] ?? '').toString().length).clamp(0, 240)), 'similarity': f['similarity']}
        ],
      };

  static ChatMsg fromJson(Map m) => ChatMsg(
        id: (m['id'] ?? '').toString(),
        rol: (m['rol'] ?? 'ai').toString(),
        texto: (m['texto'] ?? '').toString(),
        agente: (m['agente'] ?? '').toString(),
        agenteKey: (m['agente_key'] ?? 'general').toString(),
        fuentes: [for (final f in (m['fuentes'] as List? ?? const [])) if (f is Map) Map<String, dynamic>.from(f)],
        error: m['error'] == true,
      );
}

/// Helpers para leer los análisis (resultado JSON de cada agente).
List<Map<String, dynamic>> listaDe(Map? r, String k) =>
    [for (final x in (r?[k] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];

bool tieneInfo(Map? r) => r != null && (listaDe(r, 'hallazgos').isNotEmpty || listaDe(r, 'senales').isNotEmpty);

int scoreDe(Map? r) => (num.tryParse('${r?['score'] ?? 0}') ?? 0).round();

String nombreDoc(Map? d) =>
    d == null ? '' : (d['titulo'] ?? d['nombre_archivo'] ?? d['nombre'] ?? d['id'] ?? '').toString();
