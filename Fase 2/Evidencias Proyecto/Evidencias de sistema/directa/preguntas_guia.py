# -*- coding: utf-8 -*-
"""
Preguntas guiadas para el Gerente General.

Cada uno de los 14 agentes (+ el asistente general) tiene una SECUENCIA de 6 preguntas en 3 niveles:
  1. Panorama    -> "¿Cómo estamos?"                (entender el tema en 30 segundos)
  2. Diagnóstico -> "¿Qué está mal o qué no cuadra?" (encontrar lo que el directorio va a cuestionar)
  3. Decisión    -> "¿Qué hago / qué respondo?"      (salir de la reunión con acciones)

El gerente no tiene que pensar qué preguntar: el botón "Siguiente pregunta" entrega la que sigue, ya
ordenada según las alertas que el propio análisis detectó (si un agente encontró una señal alta o crítica,
la pregunta de diagnóstico sube al segundo lugar y se agrega una pregunta dinámica sobre esa señal).

Este módulo NO llama a la IA: es determinista, rápido y se puede probar sin red.
"""
import hashlib
import re

NIVELES = ("panorama", "diagnostico", "decision")
NOMBRE_NIVEL = {"panorama": "Panorama", "diagnostico": "Diagnóstico", "decision": "Decisión"}

# (nivel, pregunta). Se redactan como las hace el gerente general al agente.
_PREGUNTAS = {
    "financiero": [
        ("panorama", "¿Cómo cerró el ejercicio? Dame resultado, ingresos y EBITDA con su variación contra el año anterior."),
        ("panorama", "¿Qué partidas explican la variación del resultado y cuáles son efectos no recurrentes?"),
        ("diagnostico", "¿Qué cifras de este informe no cuadran entre sí (resumen, tablas y notas)?"),
        ("diagnostico", "¿Cómo está la liquidez y la deuda, y qué tan holgado estamos respecto de los covenants?"),
        ("decision", "¿Qué pregunta financiera es más probable que me haga un director y cómo la respondo con las cifras del documento?"),
        ("decision", "¿Qué dato financiero me falta confirmar antes de la reunión de directorio?"),
    ],
    "ciberseguridad": [
        ("panorama", "¿Cuál es la postura de ciberseguridad hoy y cómo se mide (madurez, certificaciones, métricas)?"),
        ("panorama", "¿Hubo incidentes en el período? ¿Cuál fue su impacto y si están contenidos?"),
        ("diagnostico", "¿Qué hallazgos de seguridad siguen abiertos, hace cuántos días y con qué fecha comprometida?"),
        ("diagnostico", "¿Qué dependencias bloquean la remediación (proyectos TI, proveedores, certificaciones por vencer)?"),
        ("decision", "Si un director pregunta '¿estamos expuestos a un ransomware?', ¿qué le respondo con lo que consta en el documento?"),
        ("decision", "¿Qué decisión o aprobación debería pedirle al directorio en materia de ciberseguridad?"),
    ],
    "auditoria": [
        ("panorama", "¿Qué dice la auditoría (interna y externa) sobre el período? ¿Hay salvedades u opiniones con énfasis?"),
        ("panorama", "¿Cuántos hallazgos hay, de qué criticidad y cuántos están cerrados?"),
        ("diagnostico", "¿Qué hallazgos se repiten de un año a otro sin resolverse?"),
        ("diagnostico", "¿Hay provisiones o reversiones relevantes sin nota explicativa?"),
        ("decision", "¿Qué hallazgos tienen un plan de acción sin responsable o sin fecha y qué le pido a cada dueño?"),
        ("decision", "¿Qué preguntaría el presidente del comité de auditoría y qué le respondo?"),
    ],
    "legal": [
        ("panorama", "¿Qué litigios y contingencias legales relevantes hay y cuál es la exposición total?"),
        ("panorama", "¿Cómo estamos en cumplimiento regulatorio (CMF y normativa sectorial)? ¿Hay requerimientos pendientes?"),
        ("diagnostico", "¿Hay contingencias probables con provisión menor que la cuantía estimada?"),
        ("diagnostico", "¿Alguna entidad del grupo está bajo un mínimo contractual (patrimonio, ratios) o depende de una dispensa?"),
        ("decision", "¿Qué contingencia debería explicarle yo mismo al directorio antes de que la pregunten?"),
        ("decision", "¿Qué normativa próxima a entrar en vigencia exige un plan y cuál es el plazo?"),
    ],
    "capital": [
        ("panorama", "¿Cuánto se invirtió contra lo planificado (CAPEX) y en qué proyectos?"),
        ("panorama", "¿Qué retorno (ROIC, TIR, VAN) declaran los proyectos principales y cómo se compara con el costo de capital?"),
        ("diagnostico", "¿Qué proyectos se desviaron más de 10% de su presupuesto y cuál es la explicación?"),
        ("diagnostico", "¿Qué propuestas de inversión no traen TIR, VAN o análisis de sensibilidad?"),
        ("decision", "¿Qué proyecto me van a cuestionar más y qué argumento tengo para sostenerlo?"),
        ("decision", "¿Qué inversión conviene postergar, acelerar o pedir aprobación al directorio?"),
    ],
    "operaciones": [
        ("panorama", "¿Cómo estuvo la operación: producción, productividad y cumplimiento de metas?"),
        ("panorama", "¿Qué dependencias críticas tenemos (proveedores, plantas, sistemas)?"),
        ("diagnostico", "¿Hay insumos con cobertura bajo el mínimo de la política? Compara fila por fila."),
        ("diagnostico", "¿Qué proveedor único o contrato exclusivo concentra el riesgo de suministro?"),
        ("decision", "¿Qué plan de continuidad tenemos y qué parte está solo probada en parte?"),
        ("decision", "¿Qué le digo al directorio si pregunta '¿qué pasa si se corta el suministro principal?'?"),
    ],
    "comercial": [
        ("panorama", "¿Cómo se comportaron las ventas por segmento, canal y cliente?"),
        ("panorama", "¿Cómo está el pipeline y la tasa de cierre contra el período anterior?"),
        ("diagnostico", "¿Algún cliente supera el 20% de los ingresos? ¿Cuánto pesan los principales?"),
        ("diagnostico", "¿Hay presión de precios o pérdida de participación que el documento minimice?"),
        ("decision", "¿Qué explicación comercial me van a pedir los directores y qué cifras la respaldan?"),
        ("decision", "¿Qué acción comercial concreta propongo para reducir la concentración o recuperar el pipeline?"),
    ],
    "rrhh": [
        ("panorama", "¿Cómo está la dotación, la rotación y el clima laboral contra el año anterior?"),
        ("panorama", "¿Qué relaciones laborales están abiertas (negociación colectiva, sindicatos)?"),
        ("diagnostico", "¿Qué cargos críticos no tienen sucesor identificado?"),
        ("diagnostico", "¿La rotación está sobre el promedio histórico o del sector? ¿Cuál es la brecha?"),
        ("decision", "¿Qué plan de sucesión y retención debería presentar al directorio?"),
        ("decision", "¿Qué pregunta sobre personas es más probable en la reunión y cómo la respondo?"),
    ],
    "tecnologia": [
        ("panorama", "¿En qué estado están los proyectos TI principales (avance, plazo, presupuesto)?"),
        ("panorama", "¿Qué sistemas críticos tenemos y cuáles están cerca del fin de su vida útil?"),
        ("diagnostico", "¿Qué proyectos TI tienen una desviación de plazo mayor a 25%?"),
        ("diagnostico", "¿Qué sistemas sin soporte del fabricante no tienen plan de migración con fecha?"),
        ("decision", "¿Qué dependencias entre proyectos TI y otras remediaciones (seguridad, auditoría) debo explicar?"),
        ("decision", "¿Qué inversión o decisión tecnológica debo someter al directorio?"),
    ],
    "compensacion": [
        ("panorama", "¿Cómo está estructurada la compensación de la gerencia (fija, variable, largo plazo)?"),
        ("panorama", "¿Qué metas ejecutivas existen y qué ponderación tiene cada una?"),
        ("diagnostico", "¿Los incentivos premian el corto plazo en desmedro de algún pilar estratégico?"),
        ("diagnostico", "¿Hay cargos fuera del rango de mercado definido por la política (por ejemplo P50 a P75)?"),
        ("decision", "¿Qué me pregunta el comité de remuneraciones y con qué datos respondo?"),
        ("decision", "¿Qué ajuste al esquema de incentivos conviene proponer?"),
    ],
    "esg": [
        ("panorama", "¿Qué reporta la compañía en sostenibilidad: emisiones, huella, metas y cumplimiento NCG 461?"),
        ("panorama", "¿Cómo evolucionaron las emisiones de Alcance 1, 2 y 3?"),
        ("diagnostico", "¿Qué brechas de reporte o cumplimiento ESG se ven en el documento?"),
        ("diagnostico", "¿Se mapearon los riesgos climáticos físicos y de transición? ¿Hay análisis de escenarios?"),
        ("decision", "¿Qué compromiso o meta ESG puedo defender con los datos que tenemos?"),
        ("decision", "¿Qué riesgo reputacional de sostenibilidad debería anticipar al directorio?"),
    ],
    "stakeholders": [
        ("panorama", "¿Qué relación tenemos hoy con comunidades, reguladores, sindicatos y accionistas?"),
        ("panorama", "¿Qué conflictos abiertos hay y en qué etapa están?"),
        ("diagnostico", "¿Qué conflicto no tiene plan de mitigación o ya escaló (por ejemplo, una huelga autorizada)?"),
        ("diagnostico", "¿Hay requerimientos de accionistas minoritarios sin respuesta formal?"),
        ("decision", "¿Qué conflicto con un stakeholder debería explicar yo antes de que llegue a la prensa?"),
        ("decision", "¿Qué acción de relacionamiento propongo en los próximos 30 días?"),
    ],
    "riesgos": [
        ("panorama", "¿Cuáles son los riesgos más relevantes que surgen al cruzar todas las áreas?"),
        ("panorama", "¿Cómo se compara la matriz de riesgos del documento con la evidencia del propio documento?"),
        ("diagnostico", "¿Qué combinaciones de hechos de distintas áreas se agravan entre sí?"),
        ("diagnostico", "¿Qué riesgo está calificado como bajo o medio pero la evidencia dice que es mayor?"),
        ("decision", "¿Cuál es el riesgo combinado que más debo preocuparme de explicar al directorio?"),
        ("decision", "¿Qué mitigación transversal propongo y quién la lidera?"),
    ],
    "estrategia": [
        ("panorama", "¿Cuál es el avance declarado del plan estratégico y por pilar?"),
        ("panorama", "¿Qué iniciativas estratégicas se ejecutaron en el período?"),
        ("diagnostico", "¿El avance global declarado se condice con las metas cuantitativas por pilar?"),
        ("diagnostico", "¿Qué decisiones, inversiones o incentivos contradicen las prioridades del plan?"),
        ("decision", "¿Qué pilar está más atrasado y qué le digo al directorio sobre cómo se recupera?"),
        ("decision", "¿Qué decisión estratégica debo pedir al directorio en esta reunión?"),
    ],
    "general": [
        ("panorama", "¿De qué trata este documento? Dame el resumen ejecutivo para el directorio."),
        ("panorama", "¿Cuáles son las cinco cifras clave que debo tener en la cabeza?"),
        ("diagnostico", "¿Hay contradicciones entre el resumen y el detalle del documento?"),
        ("diagnostico", "¿Qué afirmaciones del documento no tienen respaldo en sus propias cifras?"),
        ("decision", "¿Cuáles son las tres preguntas más difíciles que me pueden hacer en el directorio?"),
        ("decision", "¿Qué debería pedirle al equipo que traiga antes de la reunión?"),
    ],
}

AGENTES_GUIA = tuple(_PREGUNTAS.keys())


def _hash(texto):
    return hashlib.sha1(texto.strip().lower().encode("utf-8")).hexdigest()[:8]


def preguntas_de(agente):
    """Las 6 preguntas fijas del agente, con id estable ('financiero-1'..'financiero-6')."""
    base = _PREGUNTAS.get(agente) or _PREGUNTAS["general"]
    clave = agente if agente in _PREGUNTAS else "general"
    return [{"id": f"{clave}-{i + 1}", "nivel": n, "nivel_nombre": NOMBRE_NIVEL[n], "pregunta": p, "dinamica": False}
            for i, (n, p) in enumerate(base)]


def _norm_sev(valor):
    t = str(valor or "").lower()
    if "crit" in t or "crít" in t:
        return "crítica"
    if "alt" in t:
        return "alta"
    if "baj" in t:
        return "baja"
    return "media"


def pregunta_dinamica(agente, resultado):
    """Pregunta sobre la señal más grave que detectó el análisis (si es alta o crítica)."""
    if not isinstance(resultado, dict):
        return None
    orden = {"crítica": 0, "alta": 1}
    senales = [s for s in (resultado.get("senales") or []) if isinstance(s, dict) and s.get("titulo")
               and _norm_sev(s.get("severidad")) in orden]
    if not senales:
        return None
    senales.sort(key=lambda s: orden[_norm_sev(s["severidad"])])
    titulo = re.sub(r"\s+", " ", str(senales[0]["titulo"])).strip(" .:")[:110]
    texto = f"El análisis marcó una alerta {_norm_sev(senales[0]['severidad'])}: «{titulo}». ¿Qué respalda esa alerta en el documento y cómo se la explico al directorio?"
    return {"id": f"{agente}-dyn-{_hash(titulo)}", "nivel": "diagnostico", "nivel_nombre": "Diagnóstico",
            "pregunta": texto, "dinamica": True}


def secuencia(agente, resultado=None):
    """Orden recomendado: Panorama (1) -> [alerta dinámica] -> resto de Diagnóstico -> Panorama (2) -> Decisión.
    Si el agente no encontró alertas altas, el orden es el natural (Panorama, Diagnóstico, Decisión)."""
    fijas = preguntas_de(agente)
    dyn = pregunta_dinamica(agente, resultado)
    if not dyn:
        return fijas
    pan = [p for p in fijas if p["nivel"] == "panorama"]
    dia = [p for p in fijas if p["nivel"] == "diagnostico"]
    dec = [p for p in fijas if p["nivel"] == "decision"]
    return pan[:1] + [dyn] + dia + pan[1:] + dec


def siguiente(agente, hechas=(), resultado=None):
    """Próxima pregunta no hecha. `hechas` = ids ya consultados. Devuelve dict con 'progreso'."""
    hechas = set(hechas or ())
    seq = secuencia(agente, resultado)
    pend = [p for p in seq if p["id"] not in hechas]
    # una pregunta dinámica anterior (otra alerta) cuenta como hecha por su id; las demás siguen en orden
    total = len(seq)
    hechas_n = total - len(pend)
    return {
        "pregunta": pend[0] if pend else None,
        "restantes": len(pend) - 1 if pend else 0,
        "progreso": {"hechas": hechas_n, "total": total, "completo": not pend},
        "secuencia": [{**p, "hecha": p["id"] in hechas} for p in seq],
    }


def todas_las_preguntas():
    return {k: preguntas_de(k) for k in _PREGUNTAS}


def validar():
    """Para pruebas: cada agente con 6 preguntas, 2 por nivel, sin repetidas."""
    problemas = []
    vistos = set()
    for k, lista in _PREGUNTAS.items():
        if len(lista) != 6:
            problemas.append(f"{k}: {len(lista)} preguntas (se esperaban 6)")
        for nivel in NIVELES:
            n = sum(1 for lv, _ in lista if lv == nivel)
            if n != 2:
                problemas.append(f"{k}: {n} preguntas de nivel {nivel} (se esperaban 2)")
        for _, p in lista:
            if p in vistos:
                problemas.append(f"{k}: pregunta repetida: {p[:50]}")
            vistos.add(p)
            if not (p.startswith("¿") or p.startswith("Si ")):
                problemas.append(f"{k}: formato de pregunta dudoso: {p[:50]}")
    return problemas


if __name__ == "__main__":
    pr = validar()
    print("agentes:", len(_PREGUNTAS), "| problemas:", pr or "ninguno")
