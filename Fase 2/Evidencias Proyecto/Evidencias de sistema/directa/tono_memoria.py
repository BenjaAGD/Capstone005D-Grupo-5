# -*- coding: utf-8 -*-
"""
DIRECTA - Tono de la Memoria Anual.

La memoria que se redacta este año debe sonar como las de años anteriores. Este módulo:

  1. MIDE el estilo de cada memoria cargada con CÓDIGO (sin IA): largo de las oraciones, persona gramatical
     («hemos», «contamos»), voz pasiva refleja («se aprobó»), densidad de cifras, fórmulas recurrentes
     («Cabe destacar», «En línea con»…). Son números verificables.
  2. Le pide a Gemini que DESCRIBA el tono a partir de esas medidas y de pasajes narrativos reales
     (voz, registro, estructura, fórmulas, palabras a evitar, 5 reglas). Lo que la IA propone se contrasta con
     el texto: una «fórmula recurrente» que no aparece en ninguna memoria se descarta.
  3. Guarda el perfil como BORRADOR; el Gerente General lo revisa, lo edita y lo APRUEBA con un clic. Solo el perfil
     aprobado (o, si no hay, uno derivado solo de las medidas) se usa para redactar.
  4. Entrega `instruccion_de_tono()`: el bloque que se agrega a los prompts de redacción.

Semilla: datos_base/estilo_memorias_csav.json trae las medidas de las memorias de CSAV que había en el
proyecto (calculadas por código con este mismo módulo). Se usan mientras no haya memorias cargadas en la base.
"""
import json
import os
import re
import statistics
import unicodedata

import almacen

AQUI = os.path.dirname(os.path.abspath(__file__))
SEMILLA = os.path.join(AQUI, "datos_base", "estilo_memorias_csav.json")

MUESTRA_CHARS_POR_MEMORIA = int(os.getenv("TONO_MUESTRA_CHARS", "3600"))
MAX_MEMORIAS_TONO = int(os.getenv("TONO_MAX_MEMORIAS", "6"))

# Fórmulas típicas de una memoria en español de Chile; se cuentan por cada 1.000 palabras.
FORMULAS_CANDIDATAS = [
    "cabe destacar", "cabe notar", "cabe mencionar", "cabe recordar", "es asi como", "en linea con",
    "en este contexto", "en este sentido", "en consecuencia", "por su parte", "ademas", "asimismo",
    "durante el ano", "al cierre de", "a lo largo del ano", "como resultado", "con el fin de",
    "con el objetivo de", "en el marco de", "de esta forma", "de esta manera", "en particular",
    "principalmente", "en relacion con", "a su vez", "tal como", "dado que", "lo anterior",
]

# Verbos en primera persona plural que no son verbos (o que no revelan la voz del texto).
_NO_VERBO_MOS = {"mismos", "mas", "mos", "demos", "gramos", "kilogramos", "pueblo", "ramos", "termos", "ismos",
                 "sismos", "carismos", "mecanismos", "organismos", "turismo", "optimismos", "sistemas"}


def _norm(t):
    t = unicodedata.normalize("NFD", str(t or "").lower())
    return "".join(c for c in t if unicodedata.category(c) != "Mn")


# ----------------------------------------------------------------------------- limpieza y medidas
def limpiar_texto(texto):
    """Une las líneas que deja la extracción de un PDF, corta en los títulos y en las viñetas, quita guiones de fin de línea."""
    t = str(texto or "").replace("\r", "\n")
    t = re.sub(r"(\w)-\n(\w)", r"\1\2", t)               # «gra-\ncias» -> «gracias»
    t = t.replace("\u2022", "\n\u2022 ")
    lineas = [re.sub(r"[ \t]+", " ", l).strip() for l in t.split("\n")]
    lineas = [l for l in lineas if l and not re.fullmatch(r"\d{1,3}", l)]
    partes, actual = [], []
    for i, linea in enumerate(lineas):
        n = len(linea.split())
        if linea.startswith("\u2022"):
            partes.append(" ".join(actual))
            actual = [linea.lstrip("\u2022 ").strip()]
            continue
        sigue_mayuscula = i + 1 < len(lineas) and lineas[i + 1][:1].isupper()
        if n <= 6 and not re.search(r"[.,;:]$", linea) and sigue_mayuscula and linea[:1].isupper():
            partes.append(" ".join(actual))      # título o etiqueta: corta la oración en curso
            actual = []
            continue
        actual.append(linea)
    partes.append(" ".join(actual))
    return " ".join(p if re.search(r"[.!?:]$", p) or not p else p + "." for p in (x.strip() for x in partes) if p)


_SEP_ORACION = re.compile(r"(?<=[.!?])\s+(?=[A-ZÁÉÍÓÚÑ¿¡“\"])")


def oraciones(texto):
    """Oraciones de prosa: descarta tablas, listas de cifras y fragmentos de menos de 5 palabras."""
    out, vistas = [], set()
    for s in _SEP_ORACION.split(limpiar_texto(texto)):
        s = s.strip()
        palabras = re.findall(r"[A-Za-zÁÉÍÓÚÑáéíóúñü]+", s)
        if not (5 <= len(palabras) <= 90):
            continue
        letras = sum(c.isalpha() for c in s)
        if letras / max(1, len(s)) < 0.72:               # demasiadas cifras o símbolos: es una tabla
            continue
        clave = _norm(s)[:120]
        if clave in vistas:                              # los fragmentos se solapan: no contar dos veces
            continue
        vistas.add(clave)
        out.append(s)
    return out


def estadisticas(texto):
    """Medidas de estilo de un texto (todas calculadas por código)."""
    sents = oraciones(texto)
    if not sents:
        return {"oraciones": 0, "palabras": 0}
    largos = [len(re.findall(r"[A-Za-zÁÉÍÓÚÑáéíóúñü]+", s)) for s in sents]
    palabras = sum(largos)
    toks = [_norm(w) for s in sents for w in re.findall(r"[A-Za-zÁÉÍÓÚÑáéíóúñü]+", s)]
    mil = max(1.0, palabras / 1000.0)
    plural_1 = sum(1 for w in toks if w.endswith("mos") and w not in _NO_VERBO_MOS and len(w) > 4)
    se_pasiva = sum(1 for i, w in enumerate(toks[:-1]) if w == "se" and len(toks[i + 1]) >= 4
                    and toks[i + 1] not in {"puede", "pueden", "debe", "deben", "trata", "refiere", "encuentra", "encuentran"})
    se_total = sum(1 for w in toks if w == "se")
    con_cifras = sum(1 for s in sents if re.search(r"\d", s))
    cifras = len(re.findall(r"\d[\d.,]*", " ".join(sents)))
    coma = " ".join(sents).count(",")
    joined = _norm(" ".join(sents))
    formulas = {}
    for f in FORMULAS_CANDIDATAS:
        n = len(re.findall(r"(?<![a-z])" + re.escape(f) + r"(?![a-z])", joined))
        if n:
            formulas[f] = round(n / mil, 2)
    return {
        "oraciones": len(sents),
        "palabras": palabras,
        "palabras_por_oracion": round(statistics.mean(largos), 1),
        "mediana_palabras_por_oracion": round(statistics.median(largos), 1),
        "pct_oraciones_largas": round(100.0 * sum(1 for n in largos if n > 30) / len(largos), 1),
        "primera_persona_plural_por_mil": round(plural_1 / mil, 2),
        "se_por_mil": round(se_total / mil, 2),
        "se_pasiva_por_mil": round(se_pasiva / mil, 2),
        "cifras_por_mil": round(cifras / mil, 2),
        "pct_oraciones_con_cifras": round(100.0 * con_cifras / len(sents), 1),
        "comas_por_oracion": round(coma / len(sents), 2),
        "formulas_por_mil": dict(sorted(formulas.items(), key=lambda kv: -kv[1])),
    }


def estadisticas_de_memorias(textos):
    """textos = {anio_o_nombre: texto} -> {"por_memoria": {...}, "promedio": {...}}."""
    por = {str(k): estadisticas(v) for k, v in textos.items()}
    por = {k: v for k, v in por.items() if v.get("oraciones")}
    return {"por_memoria": por, "promedio": _promedio(por)}


def _promedio(por):
    if not por:
        return {}
    claves = ["palabras_por_oracion", "mediana_palabras_por_oracion", "pct_oraciones_largas",
              "primera_persona_plural_por_mil", "se_por_mil", "se_pasiva_por_mil", "cifras_por_mil",
              "pct_oraciones_con_cifras", "comas_por_oracion"]
    prom = {k: round(statistics.mean(v[k] for v in por.values()), 2) for k in claves}
    formulas = {}
    for v in por.values():
        for f, n in (v.get("formulas_por_mil") or {}).items():
            formulas.setdefault(f, []).append(n)
    prom["formulas_por_mil"] = dict(sorted(
        ((f, round(sum(ns) / len(por), 2)) for f, ns in formulas.items() if len(ns) >= max(1, len(por) // 2)),
        key=lambda kv: -kv[1]))
    return prom


# ----------------------------------------------------------------------------- semilla y lectura desde la base
def cargar_semilla():
    try:
        with open(SEMILLA, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def textos_de_memorias(sb, maximo=None, excluir_id=None):
    """Texto completo de las memorias anuales cargadas ({etiqueta: texto}), más recientes primero."""
    import verificador
    from modulos_base import cargar_chunks
    metas = {}
    try:
        for m in almacen.tabla("documentos_meta").listar(orden=None):
            metas[m.get("document_id")] = m
    except Exception:
        pass
    mems = verificador.memorias_de_referencia(sb, excluir_id=excluir_id, metas=metas, maximo=maximo or MAX_MEMORIAS_TONO)
    out = {}
    for m in mems:
        chunks = cargar_chunks(sb, m["id"])
        chunks.sort(key=lambda c: (c.get("page_number") or 0))
        texto = "\n".join((c.get("content") or "") for c in chunks)
        if texto.strip():
            out[str(m["anio"] or m["nombre"])] = texto
    return out


def muestra_narrativa(texto, maximo=None):
    """Los pasajes con más prosa corrida (cartas, introducciones), que es donde se oye la voz de la compañía."""
    maximo = maximo or MUESTRA_CHARS_POR_MEMORIA
    sents = oraciones(texto)
    if not sents:
        return ""
    ventanas = []
    paso = 6
    for i in range(0, max(1, len(sents) - paso + 1), paso):
        v = sents[i:i + paso]
        puntaje = sum(1 for s in v if len(s.split()) >= 12) - 0.5 * sum(1 for s in v if re.search(r"\d{3}", s))
        ventanas.append((puntaje, i, " ".join(v)))
    ventanas.sort(key=lambda x: -x[0])
    elegidas, total = [], 0
    for _, i, v in ventanas:
        if total + len(v) > maximo:
            continue
        elegidas.append((i, v))
        total += len(v)
        if total >= maximo * 0.85:
            break
    elegidas.sort()
    return "\n\n".join(v for _, v in elegidas)


# ----------------------------------------------------------------------------- perfil de tono
PERFIL_VACIO = {
    "resumen": "", "voz": "", "persona_gramatical": "", "registro": "", "estructura": "",
    "formulas_recurrentes": [], "palabras_preferidas": [], "palabras_a_evitar": [],
    "tratamiento_cifras": "", "tratamiento_malas_noticias": "", "reglas": [],
}
_TEXTOS = ["resumen", "voz", "persona_gramatical", "registro", "estructura", "tratamiento_cifras", "tratamiento_malas_noticias"]
_LISTAS = ["formulas_recurrentes", "palabras_preferidas", "palabras_a_evitar", "reglas"]
_PROHIBIDO = ("ignora", "olvida las instrucciones", "contrasena", "contraseña", "api key", "apikey", "http://", "https://", "system prompt")


def _limpio(t, n):
    t = re.sub(r"\s+", " ", str(t or "")).strip()
    t = re.sub(r"[`*#<>{}\[\]]", "", t)
    if any(p in _norm(t) for p in _PROHIBIDO):
        return ""
    return t[:n]


def sanear_perfil(perfil, textos_fuente=None):
    """Deja solo lo seguro y comprobable: sin instrucciones sospechosas y, si hay texto fuente, sin fórmulas inventadas."""
    p = dict(PERFIL_VACIO)
    perfil = perfil if isinstance(perfil, dict) else {}
    for k in _TEXTOS:
        p[k] = _limpio(perfil.get(k), 400)
    base = _norm(" ".join(textos_fuente.values())) if textos_fuente else None
    descartadas = []
    for k, tope, largo in (("formulas_recurrentes", 12, 60), ("palabras_preferidas", 15, 30),
                           ("palabras_a_evitar", 15, 30), ("reglas", 6, 220)):
        vistos, lista = set(), []
        for x in (perfil.get(k) or []):
            x = _limpio(x, largo)
            if not x or _norm(x) in vistos:
                continue
            if k == "formulas_recurrentes" and base is not None and _norm(x).strip(" .,;") not in base:
                descartadas.append(x)                      # la IA propuso una fórmula que no está en las memorias
                continue
            vistos.add(_norm(x))
            lista.append(x)
        p[k] = lista[:tope]
    if descartadas:
        p["_descartadas"] = descartadas
    return p


def perfil_desde_estadisticas(est):
    """Perfil mínimo derivado SOLO de las medidas (sin IA). Sirve de base si aún no hay perfil aprobado."""
    prom = (est or {}).get("promedio") or {}
    if not prom:
        return dict(PERFIL_VACIO)
    plural = prom.get("primera_persona_plural_por_mil", 0)
    persona = ("primera persona plural moderada («contamos», «hemos»), alternada con tercera persona institucional"
               if plural >= 1.0 else "tercera persona institucional («la Compañía»), con pocas formas en primera persona plural")
    p = dict(PERFIL_VACIO)
    p.update({
        "resumen": f"Medido en {len(est.get('por_memoria') or {})} memorias: oraciones de {prom.get('palabras_por_oracion')} palabras en promedio.",
        "persona_gramatical": persona,
        "registro": "formal, sobrio e institucional",
        "formulas_recurrentes": list((prom.get("formulas_por_mil") or {}).keys())[:6],
        "reglas": [
            f"Escribe oraciones de unas {int(round(prom.get('palabras_por_oracion') or 20))} palabras, sin superar las treinta.",
            "Usa un tono formal e institucional, sin adjetivos exagerados ni promesas.",
            "Presenta cada cifra con su unidad y su período, y explica la causa de cada variación.",
        ],
    })
    return p


def _prompt_generar(est, muestras):
    prom = (est.get("promedio") or {})
    por = est.get("por_memoria") or {}
    tabla = "\n".join(f"- {a}: {v.get('palabras_por_oracion')} palabras/oración, {v.get('primera_persona_plural_por_mil')} verbos en 1ª persona plural "
                      f"y {v.get('se_pasiva_por_mil')} «se» pasivos por mil palabras, {v.get('cifras_por_mil')} cifras por mil palabras" for a, v in sorted(por.items()))
    ej = "\n\n".join(f"[Memoria {a}]\n{t}" for a, t in muestras.items())
    sistema = (
        "Eres un editor experto en memorias anuales de sociedades anónimas abiertas chilenas. Describe el TONO con que una "
        "compañía escribe su memoria, para que otra persona pueda redactar la del próximo año con la misma voz. "
        "Basa todo en las MEDIDAS y en los PASAJES entregados; no inventes rasgos que no se vean. "
        "Responde SOLO un JSON con estas claves: "
        '"resumen" (2 frases), "voz", "persona_gramatical", "registro", "estructura" (cómo suelen armarse los párrafos), '
        '"formulas_recurrentes" (lista de expresiones que SE REPITEN literalmente en los pasajes, de 2 a 6 palabras), '
        '"palabras_preferidas" (lista), "palabras_a_evitar" (lista de lo que no usa la compañía), '
        '"tratamiento_cifras", "tratamiento_malas_noticias" (cómo comunica resultados adversos), '
        '"reglas" (exactamente 5 reglas de redacción, cada una de máximo 200 caracteres, sin cifras ni nombres propios). '
        "Español. Sin markdown."
    )
    usuario = (f"MEDIDAS (calculadas por código):\n{tabla}\n\nPromedio: {prom.get('palabras_por_oracion')} palabras por oración; "
               f"{prom.get('cifras_por_mil')} cifras por mil palabras.\n\nPASAJES REALES DE LAS MEMORIAS:\n{ej}")
    return sistema, usuario


def generar_perfil(sb=None, textos=None, llm=None, guardar=True):
    """Calcula las medidas, pide a la IA describir el tono, valida y guarda un BORRADOR. Devuelve el registro."""
    textos = textos if textos is not None else (textos_de_memorias(sb) if sb is not None else {})
    fuente = "memorias cargadas"
    if textos:
        est = estadisticas_de_memorias(textos)
    else:
        sem = cargar_semilla()
        if not sem:
            return {"ok": False, "error": "No hay memorias cargadas con texto ni medidas de semilla. Sube al menos una memoria anual."}
        est, fuente = {"por_memoria": sem.get("por_memoria", {}), "promedio": sem.get("promedio", {})}, "medidas de semilla (sin pasajes)"
    if not est.get("por_memoria"):
        sem = cargar_semilla()
        if not sem:
            return {"ok": False, "error": "No se pudo medir el estilo: las memorias no tienen suficiente prosa legible."}
        # las memorias cargadas no traen prosa medible (p. ej. solo tablas): se usan las medidas de semilla
        est, fuente, textos = {"por_memoria": sem.get("por_memoria", {}), "promedio": sem.get("promedio", {})}, \
            "medidas de semilla (las memorias cargadas no traen prosa medible)", {}
    muestras = {a: muestra_narrativa(t) for a, t in textos.items()} if textos else {}
    muestras = {a: m for a, m in muestras.items() if m}
    perfil, origen, aviso = None, "llm", None
    if muestras:
        sistema, usuario = _prompt_generar(est, muestras)
        try:
            if llm is None:
                import ia_config
                llm = lambda s, u: ia_config.llamar_llm_json(s, u, 0.2, 2200)
            perfil = sanear_perfil(llm(sistema, usuario), textos)
        except Exception as e:
            aviso = f"La IA no respondió ({str(e)[:120]}); se dejó un perfil derivado solo de las medidas."
        if perfil and len(perfil["reglas"]) < 3 and not aviso:
            aviso = "La IA entregó menos de 3 reglas válidas; se completó con las derivadas de las medidas."
            perfil["reglas"] += [r for r in perfil_desde_estadisticas(est)["reglas"] if r not in perfil["reglas"]][: 5 - len(perfil["reglas"])]
    else:
        aviso = "Sin pasajes de texto disponibles: el perfil se derivó solo de las medidas."
    if not perfil or not (perfil.get("voz") or perfil.get("reglas")):
        perfil, origen = perfil_desde_estadisticas(est), "medidas"
    registro = {"estado": "borrador", "origen": origen, "perfil": perfil, "estadisticas": est,
                "fuentes": sorted(est["por_memoria"].keys()), "fuente_datos": fuente}
    if guardar:
        registro = guardar_registro(registro)
    return {"ok": True, "aviso": aviso, **registro}


# ----------------------------------------------------------------------------- almacenamiento y aprobación
def _t():
    return almacen.tabla("perfil_tono")


def guardar_registro(registro):
    filas = _t().listar(orden="version", desc=True, limite=1)
    version = (filas[0].get("version") or 0) + 1 if filas else 1
    fila = dict(registro)
    fila["version"] = version
    return _t().insertar(fila)


def listar_versiones():
    return _t().listar(orden="version", desc=True)


def perfil_vigente():
    """Último perfil APROBADO por el gerente (o None)."""
    for f in _t().listar(orden="version", desc=True):
        if f.get("estado") == "aprobado":
            return f
    return None


def perfil_borrador():
    for f in _t().listar(orden="version", desc=True):
        if f.get("estado") == "borrador":
            return f
        if f.get("estado") == "aprobado":
            return None            # lo último que hay es un perfil aprobado: no hay borrador pendiente
    return None


def editar_borrador(fila_id, perfil):
    f = _t().obtener(fila_id)
    if not f:
        return {"ok": False, "error": "Perfil no encontrado."}
    if f.get("estado") != "borrador":
        return {"ok": False, "error": "Solo se puede editar un borrador; genera uno nuevo para cambiar un perfil aprobado."}
    p = sanear_perfil(perfil)
    _t().actualizar(fila_id, {"perfil": p, "origen": "gerente"})
    return {"ok": True, "perfil": p}


def aprobar(fila_id, aprobado_por="gerente"):
    f = _t().obtener(fila_id)
    if not f:
        return {"ok": False, "error": "Perfil no encontrado."}
    p = f.get("perfil") or {}
    if not (p.get("reglas") or p.get("voz")):
        return {"ok": False, "error": "El perfil está vacío: complétalo antes de aprobarlo."}
    _t().actualizar(fila_id, {"estado": "aprobado", "aprobado_por": aprobado_por})
    return {"ok": True, "id": fila_id, "version": f.get("version")}


def estadisticas_vigentes():
    """Medidas del perfil aprobado, o las de la semilla, o vacío."""
    v = perfil_vigente()
    if v and v.get("estadisticas"):
        return v["estadisticas"]
    sem = cargar_semilla()
    return {"por_memoria": sem.get("por_memoria", {}), "promedio": sem.get("promedio", {})} if sem else {}


def perfil_para_redactar():
    """(perfil, estadisticas, etiqueta). Aprobado > derivado de medidas > vacío."""
    v = perfil_vigente()
    if v:
        return v.get("perfil") or {}, v.get("estadisticas") or {}, f"perfil aprobado v{v.get('version')}"
    est = estadisticas_vigentes()
    if est.get("promedio"):
        return perfil_desde_estadisticas(est), est, "derivado de medidas (sin aprobar)"
    return dict(PERFIL_VACIO), {}, "sin perfil"


def instruccion_de_tono(perfil=None, est=None):
    """Bloque de texto para agregar al prompt de redacción. Vacío si no hay nada que decir."""
    if perfil is None:
        perfil, est, _ = perfil_para_redactar()
    perfil = perfil or {}
    lineas = []
    for etiqueta, k in (("Voz", "voz"), ("Persona gramatical", "persona_gramatical"), ("Registro", "registro"),
                        ("Estructura de los párrafos", "estructura"), ("Cifras", "tratamiento_cifras"),
                        ("Resultados adversos", "tratamiento_malas_noticias")):
        if perfil.get(k):
            lineas.append(f"- {etiqueta}: {perfil[k]}")
    prom = (est or {}).get("promedio") or {}
    if prom.get("palabras_por_oracion"):
        lineas.append(f"- Largo de las oraciones: unas {int(round(prom['palabras_por_oracion']))} palabras en promedio (las memorias anteriores).")
    if perfil.get("formulas_recurrentes"):
        lineas.append("- Fórmulas habituales (úsalas con moderación): " + "; ".join(perfil["formulas_recurrentes"][:8]))
    if perfil.get("palabras_a_evitar"):
        lineas.append("- Evita: " + ", ".join(perfil["palabras_a_evitar"][:10]))
    for i, r in enumerate(perfil.get("reglas") or [], 1):
        lineas.append(f"- Regla {i}: {r}")
    if not lineas:
        return ""
    return ("\n\nTONO DE LA COMPAÑÍA (imita el estilo de sus memorias anteriores; esto NO te autoriza a agregar hechos ni cifras que no estén "
            "en la evidencia):\n" + "\n".join(lineas))


def comparar_con_historico(texto, est=None):
    """Mide un texto nuevo y lo compara con el promedio histórico (para decir si 'suena' como las memorias)."""
    est = est or estadisticas_vigentes()
    prom = (est or {}).get("promedio") or {}
    mio = estadisticas(texto)
    if not mio.get("oraciones") or not prom:
        return {"medido": mio, "diferencias": [], "alineado": None}
    dif = []
    ref = prom.get("palabras_por_oracion")
    if ref and abs(mio["palabras_por_oracion"] - ref) / ref > 0.30:
        dif.append({"medida": "palabras_por_oracion", "texto": mio["palabras_por_oracion"], "historico": ref,
                    "aviso": "Las oraciones son mucho más " + ("largas" if mio["palabras_por_oracion"] > ref else "cortas") + " que en las memorias anteriores."})
    return {"medido": mio, "diferencias": dif, "alineado": not dif}
