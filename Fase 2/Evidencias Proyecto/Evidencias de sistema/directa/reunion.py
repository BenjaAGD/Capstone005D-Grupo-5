# -*- coding: utf-8 -*-
"""
DIRECTA - «Preparar mi reunión»: un clic y el Gerente General recibe su carpeta para el próximo directorio.

Qué hace (sin que el gerente tenga que elegir agentes ni escribir preguntas):
  1. Toma los análisis que ya hicieron los agentes del informe y ordena las SEÑALES por gravedad (sin repetidos).
  2. Junta las PREGUNTAS que los agentes anticipan que harán los directores y elige las mejores
     (una por área primero, empezando por las áreas con señales más graves).
  3. Responde cada pregunta con el mismo circuito del chat, con la DOBLE VERIFICACIÓN (código -> segundo prompt con
     sub-agentes -> memorias anuales) y la corrección automática; cada respuesta lleva su sello.
  4. Arma la carpeta: resumen, puntos de atención, preguntas probables con respuesta sellada y reservas.
     Todo el resumen sale de datos (conteos y títulos de señales), no de una IA que pueda inventar.

La lógica recibe `responder(pregunta, agente) -> {...}` para poder probarse sin la aplicación completa.
"""
import re
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

import almacen
from modulos_base import (
    esc_pdf, pagina_pdf, seccion, parrafo, nota_pdf, tiles_pdf, tabla_pdf, color_texto, COLOR_SEV, NAVY,
    norm_sev, nombre_corto, similitud_titulos, es_integrador,
)

ORDEN_SEV = {"crítica": 0, "alta": 1, "media": 2, "baja": 3}
MAX_SENALES = 6
MAX_PREGUNTAS = 6
TRABAJADORES = 2
TABLA = "reunion_carpetas"
JOBS = {}
_LOCK = threading.Lock()
_COLOR_SELLO = {"verificada": "#2F6B4F", "con_reservas": "#A67C00", "no_verificable": "#8E1B2E"}
_TEXTO_SELLO = {"verificada": "VERIFICADA", "con_reservas": "CON RESERVAS", "no_verificable": "NO VERIFICABLE"}


# ----------------------------------------------------------------------------- selección (todo por código)
def senales_prioritarias(analisis, maximo=MAX_SENALES):
    """Señales de todos los agentes, de la más grave a la menos grave, sin repetir las que dicen lo mismo."""
    todas = []
    for key, res in (analisis or {}).items():
        for s in (res or {}).get("senales") or []:
            if not isinstance(s, dict):
                continue
            titulo = str(s.get("titulo") or "").strip()
            if titulo:
                todas.append({"agente": key, "agente_nombre": nombre_corto(key), "titulo": titulo,
                              "descripcion": str(s.get("descripcion") or "").strip()[:400],
                              "severidad": norm_sev(s.get("severidad"))})
    todas.sort(key=lambda s: (ORDEN_SEV[s["severidad"]], s["agente"]))
    out = []
    for s in todas:
        dup = next((o for o in out if similitud_titulos(o["titulo"], s["titulo"]) >= 0.6), None)
        if dup:
            dup.setdefault("tambien_en", []).append(s["agente_nombre"])
            continue
        out.append(s)
    return out[:maximo], len(todas)


def _texto_pregunta(p):
    if isinstance(p, dict):
        p = p.get("pregunta") or p.get("texto") or p.get("question") or ""
    return re.sub(r"\s+", " ", str(p or "")).strip()


def preguntas_probables(analisis, maximo=MAX_PREGUNTAS):
    """Preguntas que los agentes anticipan de los directores. Una por área primero (las áreas con señales más graves van antes)."""
    peso = {}
    for key, res in (analisis or {}).items():
        sev = [ORDEN_SEV[norm_sev(s.get("severidad"))] for s in (res or {}).get("senales") or [] if isinstance(s, dict)]
        peso[key] = min(sev) if sev else 9
    por_agente = {}
    for key, res in (analisis or {}).items():
        qs = [q for q in (_texto_pregunta(p) for p in (res or {}).get("preguntas") or []) if len(q) >= 12]
        if qs and not es_integrador(key):
            por_agente[key] = qs
    for key, res in (analisis or {}).items():                   # los integradores van al final
        qs = [q for q in (_texto_pregunta(p) for p in (res or {}).get("preguntas") or []) if len(q) >= 12]
        if qs and es_integrador(key):
            por_agente[key] = qs
    orden = sorted(por_agente, key=lambda k: (es_integrador(k), peso.get(k, 9), k))
    elegidas, vistas = [], []
    ronda = 0
    while len(elegidas) < maximo and any(ronda < len(por_agente[k]) for k in orden):
        for k in orden:
            if ronda < len(por_agente[k]) and len(elegidas) < maximo:
                q = por_agente[k][ronda]
                if not any(similitud_titulos(q, v) >= 0.6 for v in vistas):
                    vistas.append(q)
                    elegidas.append({"pregunta": q, "agente": k, "agente_nombre": nombre_corto(k)})
        ronda += 1
    return elegidas


# ----------------------------------------------------------------------------- armado de la carpeta
def armar_carpeta(document_id, nombre_documento, analisis, responder, max_preguntas=MAX_PREGUNTAS, progreso=None):
    senales, total_senales = senales_prioritarias(analisis)
    preguntas = preguntas_probables(analisis, max_preguntas)
    if progreso:
        progreso(0, len(preguntas), "Respondiendo las preguntas probables con doble verificación…")

    hechas = [0]
    lock = threading.Lock()

    def una(q):
        try:
            r = responder(q["pregunta"], q["agente"]) or {}
        except Exception as e:                     # una pregunta que falla no tumba la carpeta
            r = {"respuesta": "", "error": str(e)[:160]}
        v = r.get("verificacion") or {}
        out = {**q, "respuesta": r.get("respuesta") or "", "agente_usado": r.get("agente_key") or q["agente"],
               "sello": v.get("sello") or "no_verificable", "puntaje": v.get("puntaje"), "corregida": bool(v.get("corregida")),
               "problemas": [{"tipo": p.get("tipo"), "gravedad": p.get("gravedad"), "detalle": p.get("detalle")}
                             for p in (v.get("problemas") or [])[:4]],
               "paginas": sorted({f.get("pagina") for f in (r.get("fuentes") or []) if f.get("pagina") is not None})[:6]}
        if r.get("error") or not out["respuesta"]:
            out.update(sello="no_verificable", error=r.get("error") or "No hubo respuesta.")
        with lock:
            hechas[0] += 1
            if progreso:
                progreso(hechas[0], len(preguntas), "Respondiendo las preguntas probables con doble verificación…")
        return out

    with ThreadPoolExecutor(max_workers=TRABAJADORES) as ex:
        respuestas = list(ex.map(una, preguntas))

    cuenta_sello = {k: sum(1 for r in respuestas if r["sello"] == k) for k in _TEXTO_SELLO}
    sev = {k: sum(1 for s in senales if s["severidad"] == k) for k in ORDEN_SEV}
    reservas = [{"pregunta": r["pregunta"], "sello": r["sello"], "problemas": r["problemas"]}
                for r in respuestas if r["sello"] != "verificada"]
    return {
        "document_id": document_id, "documento": nombre_documento, "generado_en": datetime.now().isoformat(timespec="seconds"),
        "resumen": {
            "senales_totales": total_senales, "senales_mostradas": len(senales), "por_severidad": sev,
            "preguntas": len(respuestas), "por_sello": cuenta_sello,
            "agentes_con_analisis": len([k for k, v in (analisis or {}).items() if v]),
        },
        "senales": senales, "preguntas": respuestas, "reservas": reservas,
        "texto_resumen": _texto_resumen(senales, total_senales, respuestas, cuenta_sello, sev),
    }


def _texto_resumen(senales, total, respuestas, cuenta, sev):
    """Resumen redactado con plantilla a partir de conteos y títulos reales (no lo escribe una IA)."""
    if not senales and not respuestas:
        return "Los agentes aún no dejaron señales ni preguntas para este documento. Corre el análisis de los agentes y vuelve a preparar la reunión."
    partes = []
    if senales:
        graves = sev.get("crítica", 0) + sev.get("alta", 0)
        partes.append(f"Los agentes marcaron {total} señales; las {len(senales)} más relevantes están en esta carpeta"
                      + (f" y {graves} de ellas son críticas o altas." if graves else ", ninguna crítica ni alta."))
        partes.append("Lo primero que conviene tener claro: " + "; ".join(s["titulo"].rstrip(".") for s in senales[:3]) + ".")
    if respuestas:
        ok = cuenta.get("verificada", 0)
        partes.append(f"Se prepararon respuestas a {len(respuestas)} preguntas probables del directorio: {ok} salieron verificadas"
                      + (f", {cuenta.get('con_reservas', 0)} con reservas y {cuenta.get('no_verificable', 0)} no verificables" if len(respuestas) - ok else "")
                      + ". Revisa las que traen reservas antes de usarlas.")
    return " ".join(partes)


# ----------------------------------------------------------------------------- trabajo en segundo plano
def iniciar(document_id, nombre_documento, obtener_analisis, responder, max_preguntas=MAX_PREGUNTAS):
    job_id = uuid.uuid4().hex[:12]
    job = {"id": job_id, "document_id": document_id, "estado": "corriendo", "hechas": 0, "total": 0,
           "mensaje": "Reuniendo señales y preguntas de los agentes…", "inicio": time.time(), "fin": None, "carpeta": None}
    with _LOCK:
        JOBS[job_id] = job

    def prog(h, t, m):
        job.update(hechas=h, total=t, mensaje=m)

    def correr():
        try:
            analisis = obtener_analisis(document_id)
            if not analisis:
                job.update(estado="error", fin=time.time(),
                           mensaje="Este documento todavía no tiene análisis de los agentes. Súbelo y espera a que termine el análisis.")
                return
            carpeta = armar_carpeta(document_id, nombre_documento, analisis, responder, max_preguntas, prog)
            guardar(carpeta)
            job.update(estado="listo", carpeta=carpeta, fin=time.time(), mensaje="Carpeta lista.")
        except Exception as e:
            job.update(estado="error", fin=time.time(), mensaje=f"No se pudo preparar la reunión: {str(e)[:200]}")

    threading.Thread(target=correr, daemon=True, name=f"reunion-{job_id}").start()
    return job_id


def estado(job_id):
    j = JOBS.get(job_id)
    if not j:
        return None
    return {"id": j["id"], "document_id": j["document_id"], "estado": j["estado"], "hechas": j["hechas"], "total": j["total"],
            "mensaje": j["mensaje"], "segundos": round((j["fin"] or time.time()) - j["inicio"], 1), "carpeta": j["carpeta"]}


def guardar(carpeta):
    almacen.tabla(TABLA).guardar_unico("document_id", {"document_id": carpeta["document_id"], "carpeta": carpeta,
                                                       "actualizado_en": carpeta["generado_en"]})


def ultima(document_id):
    f = almacen.tabla(TABLA).listar(orden=None, document_id=document_id)
    return f[0]["carpeta"] if f else None


# ----------------------------------------------------------------------------- PDF
def html_carpeta(c):
    r = c["resumen"]
    cuerpo = seccion(1, "Resumen para la reunión") + parrafo(c["texto_resumen"])
    cuerpo += tiles_pdf([
        (r["por_severidad"].get("crítica", 0) + r["por_severidad"].get("alta", 0), "Señales críticas o altas", COLOR_SEV["alta"]),
        (r["senales_totales"], "Señales de los agentes", None),
        (r["preguntas"], "Preguntas preparadas", None),
        (f"{r['por_sello'].get('verificada', 0)}/{r['preguntas']}", "Respuestas verificadas", _COLOR_SELLO["verificada"]),
    ])
    cuerpo += seccion(2, "Puntos de atención")
    if c["senales"]:
        cuerpo += tabla_pdf(["Área", "Señal", "Severidad"],
                            [[esc_pdf(s["agente_nombre"] + (" (+" + ", ".join(s["tambien_en"]) + ")" if s.get("tambien_en") else "")),
                              f"<b>{esc_pdf(s['titulo'])}</b><br/><span class='small muted'>{esc_pdf(s['descripcion'])}</span>",
                              color_texto(s["severidad"].upper(), COLOR_SEV.get(s["severidad"], NAVY))] for s in c["senales"]],
                            ["20%", "60%", "20%"])
    else:
        cuerpo += "<p class='muted small'>Los agentes no dejaron señales para este documento.</p>"
    cuerpo += seccion(3, "Preguntas probables del directorio y cómo responderlas")
    for i, q in enumerate(c["preguntas"], 1):
        col = _COLOR_SELLO.get(q["sello"], NAVY)
        cuerpo += (f"<h3>{i}. {esc_pdf(q['pregunta'])}</h3>"
                   f"<p class='small'>{color_texto(_TEXTO_SELLO.get(q['sello'], q['sello']), col)} "
                   f"<span class='muted'>· área: {esc_pdf(q['agente_nombre'])}"
                   + (f" · puntaje {q['puntaje']}" if q.get("puntaje") is not None else "")
                   + (" · corregida automáticamente" if q.get("corregida") else "")
                   + (f" · págs. {', '.join(str(p) for p in q['paginas'])}" if q.get("paginas") else "") + "</span></p>")
        cuerpo += "".join(f"<p>{esc_pdf(par.strip())}</p>" for par in re.split(r"\n\s*\n", q["respuesta"]) if par.strip()) \
            or "<p class='muted small'>No se pudo preparar una respuesta.</p>"
        for p in q["problemas"][:3]:
            cuerpo += f"<p class='small muted'>Reserva ({esc_pdf(p.get('gravedad') or '')}): {esc_pdf(p.get('detalle') or '')}</p>"
    cuerpo += seccion(4, "Reservas: qué revisar antes de la reunión")
    if c["reservas"]:
        cuerpo += tabla_pdf(["Pregunta", "Sello", "Motivo"],
                            [[esc_pdf(x["pregunta"]), color_texto(_TEXTO_SELLO.get(x["sello"], x["sello"]), _COLOR_SELLO.get(x["sello"], NAVY)),
                              esc_pdf("; ".join((p.get("detalle") or "")[:140] for p in x["problemas"][:2]) or "Sin detalle")] for x in c["reservas"]],
                            ["38%", "17%", "45%"])
    else:
        cuerpo += "<p class='small'>Todas las respuestas pasaron las verificaciones.</p>"
    cuerpo += nota_pdf("Las respuestas se redactaron solo con el documento y se pasaron por tres verificaciones independientes: un control por código "
                       "(cifras, páginas y citas), un segundo prompt con sub-agentes verificadores y el contraste con las memorias anuales cargadas. "
                       "«Verificada» significa que pasaron todas; no reemplaza el criterio del gerente.")
    meta = [("Documento", c["documento"] or c["document_id"]), ("Fecha de emisión", datetime.now().strftime("%d/%m/%Y %H:%M")),
            ("Áreas con análisis", str(r["agentes_con_analisis"])), ("Clasificación", "Confidencial")]
    return pagina_pdf("Carpeta de preparación del directorio", "Puntos de atención, preguntas probables y respuestas verificadas",
                      cuerpo, meta, "Preparación de reunión")
