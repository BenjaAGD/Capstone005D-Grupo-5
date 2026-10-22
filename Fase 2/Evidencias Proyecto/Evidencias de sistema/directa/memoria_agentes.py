# -*- coding: utf-8 -*-
"""
MEMORIA DE LOS AGENTES: cómo cada agente mejora con cada interacción.

Qué se guarda (tablas nuevas, ver almacen.py / migracion_v3.sql)
  agente_interacciones : cada pregunta, la respuesta, el sello de verificación y la valoración del gerente
  agente_lecciones     : reglas de estilo y rigor aprendidas por agente, con versiones y posibilidad de revertir

De dónde aprende (3 fuentes)
  1. El gerente: 👍/👎 con un motivo rápido ("cifra incorrecta", "muy largo"...). Con N valoraciones iguales (por defecto 2) nace una lección.
  2. El verificador: si el mismo tipo de problema (p. ej. "cifra sin respaldo") aparece en 3 de las últimas 15 respuestas del agente, nace una lección.
  3. El "mejorador": una pasada de la IA que lee las valoraciones y los problemas recientes y propone lecciones nuevas.

Qué NO aprende (protecciones)
  * Las lecciones son reglas de comportamiento, nunca datos: se rechaza cualquier texto con cifras, años o porcentajes.
  * Se rechazan frases que intentan dar órdenes al sistema ("ignora las instrucciones", "clave", "contraseña"...).
  * Máximo 8 lecciones activas por agente (entra una nueva, sale la de menor respaldo), sin duplicados.
  * Todo cambio genera una versión; se puede volver a cualquier versión anterior (revertir).
  * Los fragmentos del documento siempre mandan sobre una lección: así se le dice al modelo.

El resultado del aprendizaje se entrega a los prompts con `contexto_aprendizaje(agente)`.
"""
import os
import re
import unicodedata
from datetime import datetime, timezone

import almacen

MAX_LECCIONES = int(os.getenv("MAX_LECCIONES_POR_AGENTE", "8"))
UMBRAL_VALORACIONES = int(os.getenv("UMBRAL_VALORACIONES", "2"))     # 👎 iguales para crear una lección
UMBRAL_PROBLEMA = int(os.getenv("UMBRAL_PROBLEMA_VERIFICADOR", "3"))  # apariciones en la ventana
VENTANA_PROBLEMA = int(os.getenv("VENTANA_PROBLEMA_VERIFICADOR", "15"))
MAX_CHARS_LECCION = 220
MAX_CHARS_RESPUESTA_GUARDADA = int(os.getenv("MAX_CHARS_RESPUESTA_GUARDADA", "4000"))
APRENDER = os.getenv("AGENTES_APRENDEN", "1") != "0"

MOTIVOS = {
    "cifra_incorrecta": "Una cifra no era correcta",
    "sin_fuente": "No indicó de dónde sale el dato",
    "no_responde": "No respondió lo que pregunté",
    "muy_largo": "Demasiado largo",
    "falta_detalle": "Faltó detalle o cifras",
    "no_sirve_directorio": "No me sirve para el directorio",
}

# Lección que nace de cada motivo de 👎 (reglas de comportamiento, sin datos)
LECCION_POR_MOTIVO = {
    "cifra_incorrecta": "Usa solo cifras que aparezcan en los fragmentos y copia cada monto con su unidad y su año; si no consta, dilo en vez de estimarlo.",
    "sin_fuente": "Cita la página de donde sale cada cifra importante, usando solo los números de [Página N] de los fragmentos.",
    "no_responde": "Empieza con la respuesta directa a lo que se pregunta, en la primera frase, y deja el contexto para después.",
    "muy_largo": "Sé más breve: prioriza lo que el gerente general necesita decir en la reunión y deja el resto fuera.",
    "falta_detalle": "Incluye las cifras exactas del documento con su comparación (contra qué año o meta) en lugar de frases generales.",
    "no_sirve_directorio": "Cierra cada respuesta con la pregunta probable de un director y cómo responderla con lo que respalda el documento.",
}

# Lección que nace de cada tipo de problema que detecta el verificador
LECCION_POR_PROBLEMA = {
    "cifra_sin_respaldo": "Antes de escribir una cifra, comprueba que aparece en los fragmentos o que sale de una operación simple que muestres; si no, dilo.",
    "cifra_incorrecta": "Revisa cada cifra contra el fragmento antes de responder y no mezcles columnas ni períodos de una tabla.",
    "pagina_inexistente": "Cita solo páginas marcadas como [Página N] en los fragmentos; si no estás seguro, no pongas número de página.",
    "cita": "Cita solo páginas y secciones que estén en los fragmentos entregados.",
    "cita_no_literal": "Usa comillas solo para texto copiado literalmente de los fragmentos; si parafraseas, no uses comillas.",
    "cita_analisis": "No menciones los análisis previos en la respuesta: habla del documento y sus fragmentos.",
    "unidad": "Copia cada monto con la unidad y la escala del documento (por ejemplo millones de pesos o miles de dólares) sin convertirlos.",
    "base_comparacion": "Indica contra qué base se compara cada variación (año anterior, presupuesto o año base) tal como lo dice el documento.",
    "calculo": "Recalcula variaciones y porcentajes paso a paso con las cifras del documento antes de afirmarlos.",
    "periodo": "Confirma el ejercicio que cubre el documento antes de mencionar años, y no mezcles períodos distintos.",
    "entidad": "Atribuye cada dato a la entidad correcta (matriz, filial o segmento) según el fragmento.",
    "norma": "No exijas una norma o formato que no regía en el período del documento.",
    "exceso": "No afirmes más de lo que dicen los fragmentos: separa el hecho que consta de tu interpretación.",
    "omision_relevante": "Si un dato relacionado matiza o contradice tu respuesta, menciónalo aunque no te lo hayan preguntado.",
    "difiere_memoria": "Cuando una cifra cambie respecto de la memoria anual anterior, explica la diferencia en lugar de repetir el dato sin contexto.",
}

_FRASES_PROHIBIDAS = (
    "ignora", "olvida", "desobedece", "instrucciones anteriores", "instrucciones previas", "system prompt",
    "prompt del sistema", "api key", "apikey", "contrasena", "password", "clave secreta", "token", "http://", "https://",
    "eres ahora", "actua como", "jailbreak", "sin restricciones", "no verifiques", "omite la verificacion",
    "desactiva", "salta la verificacion",
)


def _norm(t):
    t = unicodedata.normalize("NFD", str(t or "").lower())
    return "".join(c for c in t if unicodedata.category(c) != "Mn")


def _ahora():
    return datetime.now(timezone.utc).isoformat()


def _t(nombre):
    return almacen.tabla(nombre)


# =====================================================================================================
# LECCIONES: filtro, deduplicación, versiones
# =====================================================================================================
def filtrar_leccion(texto):
    """Devuelve (ok, texto_limpio, motivo_de_rechazo)."""
    t = re.sub(r"\s+", " ", str(texto or "")).strip().strip("-•* ")
    if len(t) < 15:
        return False, t, "demasiado corta"
    if len(t) > MAX_CHARS_LECCION:
        return False, t[:MAX_CHARS_LECCION], f"supera {MAX_CHARS_LECCION} caracteres"
    if re.search(r"\d", t):
        return False, t, "contiene cifras o años (una lección es una regla, no un dato)"
    n = _norm(t)
    for f in _FRASES_PROHIBIDAS:
        if f in n:
            return False, t, f"contiene una frase no permitida («{f}»)"
    if len(re.findall(r"[A-Za-zÁÉÍÓÚÑáéíóúñ]+", t)) < 4:
        return False, t, "no parece una regla completa"
    if not t.endswith("."):
        t += "."
    return True, t, None


def _tokens(t):
    return {w for w in re.findall(r"[a-z]{4,}", _norm(t))}


def _similares(a, b, umbral=0.7):
    ta, tb = _tokens(a), _tokens(b)
    if not ta or not tb:
        return False
    return len(ta & tb) / len(ta | tb) >= umbral


def _version_de(filas):
    v = 0
    for f in filas:
        for e in (f.get("eventos") or []):
            v = max(v, int(e.get("version") or 0))
    return v


def _activa_en(leccion, version):
    estado = False
    for e in sorted(leccion.get("eventos") or [], key=lambda e: e["version"]):
        if e["version"] <= version:
            estado = bool(e["activa"])
    return estado


def todas_las_lecciones(agente):
    return _t("agente_lecciones").listar(orden="creado_en", desc=False, agente=agente)


def version_actual(agente):
    return _version_de(todas_las_lecciones(agente))


def lecciones_activas(agente):
    filas = todas_las_lecciones(agente)
    return [f for f in filas if f.get("activa")]


def agregar_leccion(agente, texto, origen="gerente", tipo_problema=None, motivo=None):
    """Agrega una lección si pasa el filtro. Devuelve {ok, leccion|motivo_rechazo, version}."""
    ok, limpio, rechazo = filtrar_leccion(texto)
    if not ok:
        return {"ok": False, "rechazada": True, "motivo": rechazo, "texto": limpio}
    filas = todas_las_lecciones(agente)
    activas = [f for f in filas if f.get("activa")]
    for f in activas:
        if _similares(f["texto"], limpio):
            # ya existe: se refuerza su respaldo y no se duplica
            _t("agente_lecciones").actualizar(f["id"], {"soporte": int(f.get("soporte") or 1) + 1})
            return {"ok": True, "duplicada": True, "leccion": {**f, "soporte": int(f.get("soporte") or 1) + 1},
                    "version": _version_de(filas)}
    version = _version_de(filas) + 1
    if len(activas) >= MAX_LECCIONES:
        # sale la de menor respaldo (y, a igual respaldo, la más antigua)
        saliente = sorted(activas, key=lambda f: (int(f.get("soporte") or 1), f.get("creado_en") or ""))[0]
        _t("agente_lecciones").actualizar(saliente["id"], {
            "activa": False, "eventos": (saliente.get("eventos") or []) + [{"version": version, "activa": False}]})
    fila = _t("agente_lecciones").insertar({
        "agente": agente, "texto": limpio, "origen": origen, "tipo_problema": tipo_problema, "motivo": motivo,
        "soporte": 1, "activa": True, "eventos": [{"version": version, "activa": True}],
    })
    return {"ok": True, "leccion": fila, "version": version}


def retirar_leccion(agente, leccion_id):
    filas = todas_las_lecciones(agente)
    f = next((x for x in filas if x["id"] == leccion_id), None)
    if not f or not f.get("activa"):
        return {"ok": False, "error": "La lección no existe o ya estaba retirada."}
    version = _version_de(filas) + 1
    _t("agente_lecciones").actualizar(leccion_id, {
        "activa": False, "eventos": (f.get("eventos") or []) + [{"version": version, "activa": False}]})
    return {"ok": True, "version": version}


def revertir(agente, version_objetivo):
    """Vuelve al conjunto de lecciones que estaba activo en `version_objetivo` (crea una versión nueva)."""
    filas = todas_las_lecciones(agente)
    actual = _version_de(filas)
    version_objetivo = int(version_objetivo)
    if version_objetivo < 0 or version_objetivo > actual:
        return {"ok": False, "error": f"La versión debe estar entre 0 y {actual}."}
    nueva = actual + 1
    for f in filas:
        deberia = _activa_en(f, version_objetivo)
        if deberia != bool(f.get("activa")):
            _t("agente_lecciones").actualizar(f["id"], {
                "activa": deberia, "eventos": (f.get("eventos") or []) + [{"version": nueva, "activa": deberia}]})
    return {"ok": True, "version": nueva, "revertida_a": version_objetivo,
            "activas": len(lecciones_activas(agente))}


def historial_versiones(agente):
    filas = todas_las_lecciones(agente)
    versiones = sorted({int(e["version"]) for f in filas for e in (f.get("eventos") or [])})
    out = []
    for v in versiones:
        activas = [f["texto"] for f in filas if _activa_en(f, v)]
        out.append({"version": v, "lecciones": activas, "cantidad": len(activas)})
    return out


# =====================================================================================================
# INTERACCIONES
# =====================================================================================================
def _resumen_problemas(verificacion):
    out = []
    for p in (verificacion or {}).get("problemas") or []:
        out.append({"tipo": p.get("tipo"), "gravedad": p.get("gravedad"), "detalle": str(p.get("detalle") or "")[:200]})
    return out[:12]


def registrar_interaccion(document_id, agente, pregunta, respuesta, verificacion=None, pregunta_id=None, origen="chat"):
    """Guarda la interacción y aprende de la verificación. Devuelve la fila (con su id)."""
    v = verificacion or {}
    fila = _t("agente_interacciones").insertar({
        "document_id": document_id, "agente": agente, "pregunta": str(pregunta or "")[:1500],
        "pregunta_id": pregunta_id, "origen": origen,
        "respuesta": str(respuesta or "")[:MAX_CHARS_RESPUESTA_GUARDADA],
        "sello": v.get("sello"), "puntaje": v.get("puntaje"), "corregida": bool(v.get("corregida")),
        "problemas": _resumen_problemas(v), "valoracion": None, "motivo": None, "comentario": None,
        "version_lecciones": version_actual(agente),
    })
    if APRENDER:
        try:
            aprender_de_verificacion(agente)
        except Exception as e:
            print(f"[MEMORIA] No se pudo aprender de la verificación: {e}", flush=True)
    return fila


def interacciones(agente=None, limite=None, **filtros):
    if agente:
        filtros["agente"] = agente
    return _t("agente_interacciones").listar(orden="creado_en", desc=True, limite=limite, **filtros)


def valorar(interaccion_id, valor, motivo=None, comentario=None):
    """valor: 1 (👍) o -1 (👎). Con 👎 y motivo, puede nacer una lección."""
    if valor not in (1, -1):
        return {"ok": False, "error": "La valoración debe ser 1 o -1."}
    fila = _t("agente_interacciones").obtener(interaccion_id)
    if not fila:
        return {"ok": False, "error": "No encontré esa interacción."}
    motivo = motivo if motivo in MOTIVOS else None
    _t("agente_interacciones").actualizar(interaccion_id, {
        "valoracion": valor, "motivo": motivo, "comentario": str(comentario or "")[:500] or None, "valorada_en": _ahora()})
    nueva = None
    if valor == -1 and motivo and APRENDER:
        nueva = aprender_de_valoraciones(fila["agente"], motivo)
    return {"ok": True, "leccion_nueva": nueva}


def aprender_de_valoraciones(agente, motivo):
    """Si hay al menos UMBRAL_VALORACIONES 👎 con el mismo motivo para este agente, crea la lección de ese motivo."""
    if motivo not in LECCION_POR_MOTIVO:
        return None
    cuantas = [f for f in interacciones(agente, valoracion=-1) if f.get("motivo") == motivo]
    if len(cuantas) < UMBRAL_VALORACIONES:
        return None
    r = agregar_leccion(agente, LECCION_POR_MOTIVO[motivo], origen="gerente", motivo=motivo)
    return r if r.get("ok") and not r.get("duplicada") else None


def aprender_de_verificacion(agente):
    """Mira las últimas respuestas: si un tipo de problema (alta/media) se repite, crea la lección correspondiente."""
    recientes = interacciones(agente, limite=VENTANA_PROBLEMA)
    conteo = {}
    for it in recientes:
        tipos = {p.get("tipo") for p in (it.get("problemas") or []) if p.get("gravedad") in ("alta", "media")}
        for t in tipos:
            conteo[t] = conteo.get(t, 0) + 1
    nuevas = []
    for tipo, n in conteo.items():
        if n >= UMBRAL_PROBLEMA and tipo in LECCION_POR_PROBLEMA:
            ya = any(l.get("tipo_problema") == tipo for l in lecciones_activas(agente))
            if ya:
                continue
            r = agregar_leccion(agente, LECCION_POR_PROBLEMA[tipo], origen="verificador", tipo_problema=tipo)
            if r.get("ok") and not r.get("duplicada"):
                nuevas.append(r["leccion"])
    return nuevas


# =====================================================================================================
# CONTEXTO PARA LOS PROMPTS
# =====================================================================================================
def preguntas_valoradas(agente, maximo=3):
    buenas = [f for f in interacciones(agente, limite=60, valoracion=1)]
    out, vistos = [], set()
    for f in buenas:
        q = re.sub(r"\s+", " ", f.get("pregunta") or "").strip()
        if q and not re.search(r"\d", q) and q.lower() not in vistos and len(q) <= 160:
            vistos.add(q.lower()); out.append(q)
        if len(out) >= maximo:
            break
    return out


def contexto_aprendizaje(agente, max_chars=1400):
    """Texto que se agrega al prompt del agente. Vacío si todavía no aprendió nada."""
    if not APRENDER:
        return ""
    lecs = lecciones_activas(agente)
    if not lecs:
        return ""
    lecs.sort(key=lambda f: -int(f.get("soporte") or 1))
    lineas = [f"- {l['texto']}" for l in lecs]
    bloque = ("\n\nAPRENDIZAJES DE ESTE AGENTE (salen de las valoraciones del gerente general y de verificaciones anteriores; "
              "son reglas de estilo y rigor, NO datos del documento. Si una regla contradice los fragmentos, mandan los fragmentos):\n"
              + "\n".join(lineas))
    buenas = preguntas_valoradas(agente)
    if buenas:
        bloque += "\nPreguntas que el gerente valoró bien antes (enfoque que le sirve): " + " | ".join(buenas)
    return bloque[:max_chars]


# =====================================================================================================
# MEJORADOR (IA): propone lecciones nuevas a partir de lo que pasó
# =====================================================================================================
PROMPT_MEJORADOR = (
    "Eres el 'mejorador' de un agente de IA que asiste al Gerente General de una empresa chilena a prepararse para el "
    "directorio. Recibes: el nombre del agente, sus lecciones actuales, y un resumen de sus últimas interacciones "
    "(preguntas, sello de verificación, tipos de problema detectados, valoraciones del gerente y sus comentarios). "
    "Propón entre 0 y 3 lecciones NUEVAS que corrijan los patrones que realmente se repiten. "
    "Cada lección es una REGLA DE COMPORTAMIENTO de una sola oración, de máximo 200 caracteres, en español, sin cifras, sin años, "
    "sin nombres de empresas y sin datos de ningún documento. No repitas las lecciones actuales. "
    "Si no hay un patrón claro, devuelve una lista vacía: no inventes. "
    "Responde SOLO con JSON: {\"lecciones\": [{\"texto\": \"...\", \"motivo\": \"qué patrón la origina\"}], "
    "\"retirar\": [indices de lecciones actuales que ya no aportan o que contradicen las valoraciones]}"
)


def _usuario_mejorador(agente, lecs, recientes):
    partes = [f"AGENTE: {agente}", "LECCIONES ACTUALES:"]
    partes += [f"[{i}] {l['texto']}" for i, l in enumerate(lecs)] or ["(ninguna)"]
    partes.append("\nINTERACCIONES RECIENTES:")
    for it in recientes:
        val = {1: "👍", -1: "👎"}.get(it.get("valoracion"), "sin valorar")
        probs = ", ".join(sorted({f"{p.get('tipo')}({p.get('gravedad')})" for p in (it.get("problemas") or [])})) or "sin problemas"
        linea = f"- Pregunta: {str(it.get('pregunta'))[:140]} | sello: {it.get('sello')} | problemas: {probs} | gerente: {val}"
        if it.get("motivo"):
            linea += f" ({MOTIVOS.get(it['motivo'], it['motivo'])})"
        if it.get("comentario"):
            linea += f" | comentario: {str(it['comentario'])[:160]}"
        partes.append(linea)
    return "\n".join(partes)


def mejorar_agente(agente, llm=None, minimo_interacciones=3):
    """Pasada de mejora con IA. Devuelve {ok, agregadas, rechazadas, retiradas}."""
    recientes = interacciones(agente, limite=20)
    if len(recientes) < minimo_interacciones:
        return {"ok": True, "agregadas": [], "rechazadas": [], "retiradas": [],
                "mensaje": f"Aún hay pocas interacciones de este agente (mínimo {minimo_interacciones})."}
    lecs = lecciones_activas(agente)
    sistema, usuario = PROMPT_MEJORADOR, _usuario_mejorador(agente, lecs, recientes)
    if llm is not None:
        datos = llm(sistema, usuario, 900, None)
    else:
        import ia_config
        datos = ia_config.llamar_llm_json(sistema, usuario, temperatura=0.2, max_tokens=900)
    agregadas, rechazadas, retiradas = [], [], []
    for it in (datos.get("lecciones") or [])[:3]:
        texto = it.get("texto") if isinstance(it, dict) else str(it)
        r = agregar_leccion(agente, texto, origen="mejorador", motivo=(it.get("motivo") if isinstance(it, dict) else None))
        if r.get("ok") and not r.get("duplicada"):
            agregadas.append(r["leccion"]["texto"])
        elif not r.get("ok"):
            rechazadas.append({"texto": r.get("texto"), "motivo": r.get("motivo")})
    for idx in (datos.get("retirar") or [])[:2]:
        if isinstance(idx, int) and 0 <= idx < len(lecs) and lecs[idx].get("origen") != "gerente":
            if retirar_leccion(agente, lecs[idx]["id"]).get("ok"):
                retiradas.append(lecs[idx]["texto"])
    return {"ok": True, "agregadas": agregadas, "rechazadas": rechazadas, "retiradas": retiradas}


# =====================================================================================================
# TENDENCIA E INFORME DE MEJORA
# =====================================================================================================
def _prom(xs):
    xs = [x for x in xs if x is not None]
    return round(sum(xs) / len(xs), 1) if xs else None


def _metricas(grupo):
    n = len(grupo)
    if not n:
        return {"interacciones": 0, "puntaje_promedio": None, "pct_verificada": None, "pct_pulgar_arriba": None, "pct_pulgar_abajo": None}
    val = [g for g in grupo if g.get("valoracion") in (1, -1)]
    return {
        "interacciones": n,
        "puntaje_promedio": _prom([g.get("puntaje") for g in grupo]),
        "pct_verificada": round(100 * sum(1 for g in grupo if g.get("sello") == "verificada") / n),
        "pct_pulgar_arriba": round(100 * sum(1 for g in val if g["valoracion"] == 1) / len(val)) if val else None,
        "pct_pulgar_abajo": round(100 * sum(1 for g in val if g["valoracion"] == -1) / len(val)) if val else None,
    }


def tendencia(agente):
    """Métricas por versión de lecciones (cómo cambió la calidad al cambiar las reglas)."""
    todas = list(reversed(interacciones(agente)))
    por_version = {}
    for it in todas:
        por_version.setdefault(int(it.get("version_lecciones") or 0), []).append(it)
    versiones = [{"version": v, **_metricas(g)} for v, g in sorted(por_version.items())]
    mitad = len(todas) // 2
    return {"agente": agente, "versiones": versiones, "total": _metricas(todas),
            "primera_mitad": _metricas(todas[:mitad]) if mitad else None,
            "segunda_mitad": _metricas(todas[mitad:]) if mitad else None}


def estado_agente(agente):
    lecs = lecciones_activas(agente)
    its = interacciones(agente)
    return {"agente": agente, "version": version_actual(agente), "lecciones": lecs,
            "interacciones": len(its), "valoradas": sum(1 for i in its if i.get("valoracion")),
            "metricas": _metricas(its)}


def resumen_global(claves_agentes):
    return [{**{k: v for k, v in estado_agente(a).items() if k != "lecciones"},
             "lecciones_activas": len(lecciones_activas(a))} for a in claves_agentes]


def informe_mejora_md(claves_agentes, nombres=None):
    """Informe en Markdown con lo que aprendió cada agente (para el documento de mejora)."""
    nombres = nombres or {}
    fecha = datetime.now().strftime("%d/%m/%Y")
    L = [f"# Informe de mejora de los agentes — {fecha}", "",
         "Este informe resume qué ha aprendido cada agente a partir de las valoraciones del Gerente General "
         "y de las verificaciones automáticas. Las lecciones son reglas de comportamiento (no datos) y se pueden revertir.", ""]
    total_int = 0
    filas = []
    for a in claves_agentes:
        e = estado_agente(a)
        total_int += e["interacciones"]
        filas.append((a, e))
    L += [f"**Interacciones registradas:** {total_int}", "",
          "| Agente | Interacciones | Verificadas | Puntaje prom. | 👍 | 👎 | Lecciones activas | Versión |",
          "|---|---|---|---|---|---|---|---|"]
    for a, e in filas:
        m = e["metricas"]
        L.append(f"| {nombres.get(a, a)} | {m['interacciones']} | {m['pct_verificada'] if m['pct_verificada'] is not None else '—'}% | "
                 f"{m['puntaje_promedio'] if m['puntaje_promedio'] is not None else '—'} | "
                 f"{m['pct_pulgar_arriba'] if m['pct_pulgar_arriba'] is not None else '—'}% | "
                 f"{m['pct_pulgar_abajo'] if m['pct_pulgar_abajo'] is not None else '—'}% | {len(e['lecciones'])} | v{e['version']} |")
    L.append("")
    con_lecc = [(a, e) for a, e in filas if e["lecciones"]]
    if con_lecc:
        L += ["## Lo que aprendió cada agente", ""]
        for a, e in con_lecc:
            L.append(f"### {nombres.get(a, a)} (versión {e['version']})")
            for l in e["lecciones"]:
                L.append(f"- {l['texto']}  _(origen: {l.get('origen')}, respaldo: {l.get('soporte', 1)})_")
            tr = tendencia(a)
            p1, p2 = tr.get("primera_mitad"), tr.get("segunda_mitad")
            if p1 and p2 and p1["puntaje_promedio"] is not None and p2["puntaje_promedio"] is not None:
                L.append(f"- Puntaje de verificación: {p1['puntaje_promedio']} en la primera mitad de las interacciones → {p2['puntaje_promedio']} en la segunda.")
            L.append("")
    else:
        L += ["Todavía no hay lecciones: los agentes aprenden cuando el gerente valora respuestas o cuando el verificador "
              "detecta el mismo tipo de problema varias veces.", ""]
    return "\n".join(L)
