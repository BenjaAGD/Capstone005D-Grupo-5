# -*- coding: utf-8 -*-
"""Aprendizaje con cada interacción (Frente C2).

Los modelos no aprenden solos al conversar. Lo que se hace aquí es guardar la valoración del gerente y
usarla para mejorar el contexto de los agentes, siempre con una persona en el medio:

  1. Registro      pulgar arriba o abajo bajo cada respuesta; si es abajo, un motivo en un toque.
  2. Lecciones     con suficientes valoraciones negativas de un agente se proponen 3 a 5 lecciones cortas
                   (criterio y estilo, nunca contenido del documento). Quedan PENDIENTES: una persona las
                   prueba contra el conjunto de pruebas y las aprueba, rechaza o revierte. Son versionadas.
  3. Ejemplos      las respuestas bien valoradas y verificadas se recuperan por similitud cuando llega una
                   pregunta parecida sobre el mismo documento, como guía de formato.
"""
import json
import re
import threading
import time
import unicodedata
import uuid

from fastapi import APIRouter, Body
from fastapi.responses import JSONResponse

from persistencia import Tabla, ahora_iso, estado as _estado_persistencia

MIN_NEGATIVAS = 3          # valoraciones negativas nuevas de un agente para proponer lecciones
MAX_LECCIONES_ACTIVAS = 5  # lecciones aprobadas que se inyectan por agente
MARCA_LECCIONES = "[LECCIONES DIRECTA]"
MOTIVOS = {
    "cifra_incorrecta": "Cifra incorrecta",
    "no_responde": "No responde lo que pregunté",
    "muy_larga": "Demasiado larga",
    "falta_contexto": "Falta contexto",
    "otro": "Otro",
}
_CACHE_CTX = {}
_TTL_CTX = 60
jobs_prueba = {}


def _norm(t):
    t = unicodedata.normalize("NFD", str(t or "").lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9 ]+", " ", t)


def _palabras(t):
    vacias = {"que", "como", "cual", "cuales", "del", "las", "los", "una", "uno", "por", "para", "con", "sus", "este",
              "esta", "documento", "tiene", "hay", "sobre", "cuanto", "cuantos", "el", "la", "de", "en", "y", "a"}
    return {w for w in _norm(t).split() if len(w) > 2 and w not in vacias}


def similitud(a, b):
    pa, pb = _palabras(a), _palabras(b)
    if not pa or not pb:
        return 0.0
    return len(pa & pb) / len(pa | pb)


# ---------------------------------------------------------------------------
# Valoraciones
# ---------------------------------------------------------------------------
def registrar_valoracion(get_sb, datos):
    valor = int(datos.get("valor") or 0)
    if valor not in (1, -1):
        raise ValueError("valor debe ser 1 o -1")
    motivo = str(datos.get("motivo") or "").strip() or None
    if valor == -1 and motivo not in MOTIVOS:
        motivo = "otro"
    fila = {
        "document_id": str(datos.get("document_id") or "") or None,
        "agente": str(datos.get("agente") or "general")[:40],
        "pregunta": str(datos.get("pregunta") or "")[:1000],
        "respuesta": str(datos.get("respuesta") or "")[:4000],
        "valor": valor,
        "motivo": motivo if valor == -1 else None,
        "sello": str(datos.get("sello") or "") or None,
        "mensaje_id": str(datos.get("mensaje_id") or "")[:80] or None,
        "usada_en_leccion": False,
    }
    tabla = Tabla(get_sb, "valoraciones")
    # Una valoración por mensaje: si el gerente cambia de opinión, se reemplaza.
    if fila["mensaje_id"]:
        for previa in tabla.listar(limite=5, mensaje_id=fila["mensaje_id"]):
            tabla.borrar(previa["id"])
    _CACHE_CTX.clear()
    return tabla.insertar(fila)


def resumen_valoraciones(get_sb):
    filas = Tabla(get_sb, "valoraciones").listar(limite=5000)
    por_agente = {}
    for f in filas:
        a = por_agente.setdefault(f.get("agente") or "general", {
            "positivas": 0, "negativas": 0, "negativas_nuevas": 0, "motivos": {}})
        if f.get("valor") == 1:
            a["positivas"] += 1
        else:
            a["negativas"] += 1
            if not f.get("usada_en_leccion"):
                a["negativas_nuevas"] += 1
            m = f.get("motivo") or "otro"
            a["motivos"][m] = a["motivos"].get(m, 0) + 1
    for a in por_agente.values():
        a["puede_generar"] = a["negativas_nuevas"] >= MIN_NEGATIVAS
    return {"total": len(filas), "por_agente": por_agente, "minimo_para_lecciones": MIN_NEGATIVAS,
            "motivos": MOTIVOS}


# ---------------------------------------------------------------------------
# Lecciones
# ---------------------------------------------------------------------------
_RE_CIFRA = re.compile(r"\d[\d.,]{2,}|\d+\s?%|\bMM?\$|\bUS\$|\bMUS\$")


def _leccion_segura(texto, respuestas):
    """Una lección es criterio o estilo: corta, sin cifras y sin copiar frases de una respuesta."""
    t = " ".join(str(texto or "").split())
    if not (12 <= len(t) <= 240):
        return False
    if _RE_CIFRA.search(t):
        return False
    pal = _norm(t).split()
    for r in respuestas:
        rn = " " + " ".join(_norm(r).split()) + " "
        for i in range(0, max(0, len(pal) - 7)):
            if " " + " ".join(pal[i:i + 8]) + " " in rn:
                return False
    return True


def proponer_lecciones(get_sb, agente=None):
    """Por cada agente con suficientes valoraciones negativas nuevas, propone 3 a 5 lecciones pendientes."""
    import ia_config as _ia
    tv, tl = Tabla(get_sb, "valoraciones"), Tabla(get_sb, "lecciones")
    negativas = [f for f in tv.listar(limite=5000) if f.get("valor") == -1 and not f.get("usada_en_leccion")]
    por_agente = {}
    for f in negativas:
        por_agente.setdefault(f.get("agente") or "general", []).append(f)
    creadas, omitidas = [], []
    for ag, filas in por_agente.items():
        if agente and ag != agente:
            continue
        if len(filas) < MIN_NEGATIVAS:
            omitidas.append({"agente": ag, "motivo": f"solo {len(filas)} valoraciones negativas nuevas (mínimo {MIN_NEGATIVAS})"})
            continue
        casos = "\n".join(
            f"- Motivo: {MOTIVOS.get(f.get('motivo') or 'otro')}. Pregunta: {f.get('pregunta', '')[:200]}\n"
            f"  Respuesta (extracto): {f.get('respuesta', '')[:400]}"
            for f in filas[:12])
        sistema = (
            f"{MARCA_LECCIONES}\nEres el editor de los agentes de DIRECTA. El Gerente General valoró mal estas respuestas "
            f"del agente '{ag}'. Propón entre 3 y 5 LECCIONES cortas (máximo 30 palabras cada una) que el agente debe "
            "aplicar desde ahora. Una lección es un criterio de estilo o de método (por ejemplo: 'compara siempre la "
            "cifra contra el presupuesto y contra el año anterior'). NUNCA incluyas cifras, nombres de empresas ni frases "
            "copiadas de las respuestas: el contenido del documento es confidencial y la lección debe servir para "
            "cualquier documento. Responde ÚNICAMENTE con este JSON: {\"lecciones\":[\"...\"]}")
        try:
            texto = _ia.llamar_llm_chat(sistema, f"VALORACIONES NEGATIVAS:\n{casos}\n\nDevuelve el JSON.",
                                        temperatura=0.2, max_tokens=800, json_mode=True)
            data = _ia.parsear_json_respuesta(texto)
        except Exception as e:  # noqa: BLE001
            omitidas.append({"agente": ag, "motivo": f"la IA no respondió: {str(e)[:120]}"})
            continue
        respuestas = [f.get("respuesta", "") for f in filas]
        propuestas = [str(x).strip() for x in (data.get("lecciones") or []) if isinstance(x, (str, int, float))]
        validas = [x for x in propuestas if _leccion_segura(x, respuestas)][:5]
        descartadas = len(propuestas) - len(validas)
        for x in validas:
            creadas.append(tl.insertar({
                "agente": ag, "texto": x, "estado": "pendiente", "version": 1, "historial": [],
                "origen": [f["id"] for f in filas], "prueba": None, "aprobado_en": None, "revertido_en": None,
            }))
        for f in filas:
            tv.actualizar(f["id"], {"usada_en_leccion": True})
        if descartadas:
            omitidas.append({"agente": ag, "motivo": f"{descartadas} propuesta(s) descartadas por traer cifras o frases copiadas"})
    _CACHE_CTX.clear()
    return {"creadas": creadas, "omitidas": omitidas}


def listar_lecciones(get_sb, estado=None, agente=None):
    return Tabla(get_sb, "lecciones").listar(limite=500, estado=estado, agente=agente)


def cambiar_estado_leccion(get_sb, id_, accion):
    tl = Tabla(get_sb, "lecciones")
    lec = tl.obtener(id_)
    if not lec:
        raise ValueError("Lección no encontrada")
    if accion == "aprobar":
        activas = [x for x in tl.listar(limite=200, agente=lec["agente"], estado="aprobada") if x["id"] != id_]
        if len(activas) >= MAX_LECCIONES_ACTIVAS:
            raise ValueError(f"El agente ya tiene {MAX_LECCIONES_ACTIVAS} lecciones activas; revierte una antes de aprobar otra.")
        cambios = {"estado": "aprobada", "aprobado_en": ahora_iso(), "revertido_en": None}
    elif accion == "rechazar":
        cambios = {"estado": "rechazada"}
    elif accion == "revertir":
        cambios = {"estado": "revertida", "revertido_en": ahora_iso()}
    else:
        raise ValueError("Acción no válida")
    _CACHE_CTX.clear()
    return tl.actualizar(id_, cambios)


def editar_leccion(get_sb, id_, texto):
    tl = Tabla(get_sb, "lecciones")
    lec = tl.obtener(id_)
    if not lec:
        raise ValueError("Lección no encontrada")
    if lec.get("estado") == "aprobada":
        raise ValueError("Revierte la lección antes de editarla.")
    if not _leccion_segura(texto, []):
        raise ValueError("La lección debe tener entre 12 y 240 caracteres y no llevar cifras.")
    historial = list(lec.get("historial") or []) + [{"version": lec.get("version", 1), "texto": lec.get("texto")}]
    _CACHE_CTX.clear()
    return tl.actualizar(id_, {"texto": " ".join(texto.split()), "version": int(lec.get("version") or 1) + 1,
                               "historial": historial, "estado": "pendiente", "prueba": None})


def lecciones_activas(get_sb, agente):
    tl = Tabla(get_sb, "lecciones")
    propias = tl.listar(limite=MAX_LECCIONES_ACTIVAS, agente=agente, estado="aprobada")
    generales = tl.listar(limite=3, agente="general", estado="aprobada") if agente != "general" else []
    return [x["texto"] for x in propias + generales]


# ---------------------------------------------------------------------------
# Ejemplos bien valorados
# ---------------------------------------------------------------------------
def mejor_ejemplo(get_sb, agente, pregunta, document_id, umbral=0.3):
    """Respuesta bien valorada y verificada, del MISMO documento, para una pregunta parecida."""
    if not document_id:
        return None
    filas = [f for f in Tabla(get_sb, "valoraciones").listar(limite=300, document_id=document_id, valor=1)
             if (f.get("agente") or "general") == agente and f.get("sello") == "verificada"]
    mejor, puntos = None, umbral
    for f in filas:
        s = similitud(pregunta, f.get("pregunta", ""))
        if s >= puntos and _norm(f.get("pregunta")) != _norm(pregunta):
            mejor, puntos = f, s
    return mejor


def contexto_para_prompt(get_sb, agente, pregunta, document_id, con_lecciones=True, leccion_extra=None):
    """Bloque que se agrega al prompt del chat: lecciones aprobadas y, si hay, un ejemplo bien valorado."""
    clave = (agente, document_id, _norm(pregunta)[:200], con_lecciones, leccion_extra)
    hit = _CACHE_CTX.get(clave)
    if hit and time.time() - hit[0] < _TTL_CTX:
        return hit[1]
    partes = []
    lecciones = lecciones_activas(get_sb, agente) if con_lecciones else []
    if leccion_extra:
        lecciones = lecciones + [leccion_extra]
    if lecciones:
        partes.append("LECCIONES APROBADAS POR EL GERENTE (aplícalas siempre):\n" + "\n".join(f"- {x}" for x in lecciones))
    ej = mejor_ejemplo(get_sb, agente, pregunta, document_id)
    if ej:
        partes.append("EJEMPLO DE UNA RESPUESTA BIEN VALORADA Y VERIFICADA (mismo documento, pregunta parecida). Úsalo "
                      "solo como guía de formato y nivel de detalle; los datos salen de los fragmentos de ahora:\n"
                      f"P: {ej.get('pregunta', '')[:300]}\nR: {ej.get('respuesta', '')[:900]}")
    texto = "\n\n".join(partes)
    _CACHE_CTX[clave] = (time.time(), texto)
    return texto


# ---------------------------------------------------------------------------
# Probar una lección contra el conjunto de pruebas antes de aprobarla
# ---------------------------------------------------------------------------
def _preguntas_para_probar(agente, maximo=6):
    import os
    import agentes as _ag
    ruta = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pruebas", "conjunto_pruebas.json")
    preguntas = []
    try:
        with open(ruta, encoding="utf-8") as f:
            conj = json.load(f)
        preguntas = [{"pregunta": p["pregunta"], "cifras": p.get("cifras_clave") or []}
                     for p in conj.get("preguntas", []) if p.get("agente") == agente]
    except Exception:  # noqa: BLE001
        pass
    if len(preguntas) < maximo:
        guia = (_ag.AGENTES.get(agente) or {}).get("preguntas_guia") or []
        preguntas += [{"pregunta": q["pregunta"], "cifras": []} for q in guia]
    return preguntas[:maximo]


def iniciar_prueba(get_sb, id_, document_id, responder):
    """`responder(pregunta, agente, document_id, extra_prompt)` -> (texto, verificacion). Corre en segundo plano:
    cada pregunta se responde con y sin la lección y se compara cuántas cifras clave aparecen y cuántas
    alertas pone el verificador. Una lección que empeora no se debería aprobar."""
    tl = Tabla(get_sb, "lecciones")
    lec = tl.obtener(id_)
    if not lec:
        raise ValueError("Lección no encontrada")
    job_id = str(uuid.uuid4())
    job = {"job_id": job_id, "leccion_id": id_, "corriendo": True, "hechas": 0, "total": 0, "error": None}
    jobs_prueba[job_id] = job

    def contar(texto, verif, cifras):
        aciertos = sum(1 for c in cifras if _norm(c).replace(" ", "") in _norm(texto).replace(" ", ""))
        alertas = len([p for p in ((verif or {}).get("capa1") or {}).get("problemas", []) if p.get("gravedad") in ("alta", "media")])
        malas = len([a for a in (verif or {}).get("afirmaciones", []) if a.get("estado") in ("no_respaldada", "contradicha")])
        return aciertos, alertas + malas

    def worker():
        try:
            preguntas = _preguntas_para_probar(lec["agente"])
            job["total"] = len(preguntas)
            sin = {"aciertos": 0, "alertas": 0}
            con = {"aciertos": 0, "alertas": 0}
            for p in preguntas:
                base_ctx = contexto_para_prompt(get_sb, lec["agente"], p["pregunta"], document_id)
                con_ctx = contexto_para_prompt(get_sb, lec["agente"], p["pregunta"], document_id, leccion_extra=lec["texto"])
                t0, v0 = responder(p["pregunta"], lec["agente"], document_id, base_ctx)
                t1, v1 = responder(p["pregunta"], lec["agente"], document_id, con_ctx)
                a0, e0 = contar(t0, v0, p["cifras"])
                a1, e1 = contar(t1, v1, p["cifras"])
                sin["aciertos"] += a0
                sin["alertas"] += e0
                con["aciertos"] += a1
                con["alertas"] += e1
                job["hechas"] += 1
            empeora = con["aciertos"] < sin["aciertos"] or con["alertas"] > sin["alertas"]
            resultado = {"document_id": document_id, "preguntas": len(preguntas), "sin_leccion": sin, "con_leccion": con,
                         "empeora": empeora, "fecha": ahora_iso(),
                         "conclusion": ("La lección empeora el resultado: no conviene aprobarla." if empeora else
                                        "La lección no empeora el resultado en el conjunto de pruebas.")}
            tl.actualizar(id_, {"prueba": resultado})
            job["resultado"] = resultado
        except Exception as e:  # noqa: BLE001
            job["error"] = str(e)[:300]
        finally:
            job["corriendo"] = False
    threading.Thread(target=worker, daemon=True).start()
    return job


def estado_tablas(get_sb):
    return _estado_persistencia(get_sb)


# ---------------------------------------------------------------------------
# Rutas
# ---------------------------------------------------------------------------
def crear_router(get_supabase, responder=None):
    """`responder` lo entrega main.py (para probar lecciones con el mismo chat que usa la app)."""
    router = APIRouter()

    def err(e, codigo=200):
        return JSONResponse({"ok": False, "error": str(e)[:300]}, status_code=codigo)

    @router.post("/api/valoraciones")
    def api_valorar(payload: dict = Body(default={})):
        try:
            fila = registrar_valoracion(get_supabase, payload or {})
            return {"ok": True, "id": fila.get("id")}
        except Exception as e:  # noqa: BLE001
            return err(e)

    @router.get("/api/valoraciones/resumen")
    def api_resumen():
        try:
            return {"ok": True, **resumen_valoraciones(get_supabase)}
        except Exception as e:  # noqa: BLE001
            return err(e)

    @router.get("/api/lecciones")
    def api_lecciones(estado: str = "", agente: str = ""):
        try:
            return {"ok": True, "lecciones": listar_lecciones(get_supabase, estado or None, agente or None)}
        except Exception as e:  # noqa: BLE001
            return err(e)

    @router.post("/api/lecciones/generar")
    def api_generar(payload: dict = Body(default={})):
        try:
            r = proponer_lecciones(get_supabase, (payload or {}).get("agente") or None)
            return {"ok": True, **r}
        except Exception as e:  # noqa: BLE001
            return err(e)

    @router.post("/api/lecciones/{id_}/{accion}")
    def api_accion(id_: str, accion: str, payload: dict = Body(default={})):
        try:
            if accion == "probar":
                if responder is None:
                    return err("La prueba no está disponible en este servidor.")
                doc = str((payload or {}).get("document_id") or "")
                if not doc:
                    return err("Elige el documento con que se probará la lección.")
                job = iniciar_prueba(get_supabase, id_, doc, responder)
                return {"ok": True, "job_id": job["job_id"]}
            if accion == "editar":
                return {"ok": True, "leccion": editar_leccion(get_supabase, id_, str((payload or {}).get("texto") or ""))}
            return {"ok": True, "leccion": cambiar_estado_leccion(get_supabase, id_, accion)}
        except Exception as e:  # noqa: BLE001
            return err(e)

    @router.get("/api/lecciones-prueba/{job_id}")
    def api_estado_prueba(job_id: str):
        job = jobs_prueba.get(job_id)
        if not job:
            return err("Prueba no encontrada")
        return {"ok": True, **job}

    return router
