# -*- coding: utf-8 -*-
"""
DIRECTA v2 — Módulo Dashboard (sin IA).

Convierte los análisis que ya están guardados en indicadores para el Gerente General:
puntaje global, semáforo por agente, señales por severidad, plan de acción y comparación
entre dos documentos.

Conexión en main.py (3 líneas, después de crear `app`):

    from dashboard import crear_router as _dash
    app.include_router(_dash(lambda: supabase))
"""
import os
from datetime import datetime
from fastapi import APIRouter, Body
from fastapi.responses import FileResponse, JSONResponse, Response

from modulos_base import (
    SEVERIDADES, agentes_analizables, nombre_corto, es_integrador, tiene_info, score_de,
    etiqueta_score, banda_score, senales_de, lista_textos, id_estable, info_documento,
    cargar_analisis, similitud_titulos, esc_pdf, html_a_pdf, pagina_pdf,
)

UMBRAL_MISMA_SENAL = 0.55


def _conteo_vacio():
    return {s: 0 for s in SEVERIDADES}


def construir_dashboard(sb, document_id):
    doc = info_documento(sb, document_id)
    if doc is None:
        return None
    analisis = cargar_analisis(sb, document_id)

    agentes, senales, omisiones, preguntas, recomendaciones = [], [], [], [], []
    for key in agentes_analizables():
        res = analisis.get(key)
        base = {"key": key, "nombre": nombre_corto(key), "transversal": es_integrador(key)}
        if res is None:
            agentes.append({**base, "estado": "sin_analizar", "con_info": False, "score": None,
                            "etiqueta": "Sin analizar", "banda": "sin_analizar",
                            "senales": _conteo_vacio(), "n_omisiones": 0, "n_preguntas": 0,
                            "n_recomendaciones": 0, "resumen": ""})
            continue
        s_list = senales_de(key, res)
        cont = _conteo_vacio()
        for s in s_list:
            cont[s["severidad"]] += 1
        om = lista_textos(res.get("omisiones"), "descripcion", "texto")
        pr = lista_textos(res.get("preguntas"), "pregunta", "texto")
        rc = lista_textos(res.get("recomendaciones"), "descripcion", "recomendacion", "texto")
        con_info = tiene_info(res)
        sc = score_de(res)
        agentes.append({**base, "estado": "ok", "con_info": con_info, "score": sc,
                        "etiqueta": etiqueta_score(sc) if con_info else "Sin información relevante",
                        "banda": banda_score(sc) if con_info else "sin_info",
                        "senales": cont, "n_omisiones": len(om), "n_preguntas": len(pr),
                        "n_recomendaciones": len(rc), "resumen": str(res.get("resumen_ejecutivo") or "")})
        senales.extend(s_list)
        omisiones += [{"agente": key, "agente_nombre": nombre_corto(key), "texto": t} for t in om]
        preguntas += [{"agente": key, "agente_nombre": nombre_corto(key), "texto": t} for t in pr]
        recomendaciones += [{"id": id_estable(document_id, key, t), "agente": key,
                             "agente_nombre": nombre_corto(key), "texto": t} for t in rc]

    con_score = [a["score"] for a in agentes if a["con_info"]]
    global_score = round(sum(con_score) / len(con_score)) if con_score else None
    total_sen = _conteo_vacio()
    for s in senales:
        total_sen[s["severidad"]] += 1
    orden = {sv: i for i, sv in enumerate(SEVERIDADES)}
    senales.sort(key=lambda s: (orden[s["severidad"]], s["transversal"]))

    return {
        "ok": True,
        "documento": doc,
        "resumen": {
            "score_global": global_score,
            "etiqueta": etiqueta_score(global_score) if global_score is not None else "Sin datos",
            "banda": banda_score(global_score) if global_score is not None else "sin_datos",
            "agentes_total": len(agentes),
            "agentes_analizados": sum(1 for a in agentes if a["estado"] == "ok"),
            "agentes_con_info": len(con_score),
            "senales": total_sen,
            "senales_total": len(senales),
            "senales_transversales": sum(1 for s in senales if s["transversal"]),
            "omisiones": len(omisiones),
            "preguntas": len(preguntas),
            "recomendaciones": len(recomendaciones),
        },
        "agentes": agentes,
        "senales": senales,
        "omisiones": omisiones,
        "preguntas": preguntas,
        "recomendaciones": recomendaciones,
    }


def comparar_documentos(sb, id_a, id_b):
    """A = documento base (anterior), B = documento nuevo. Todo sale de lo ya guardado."""
    da, db_ = construir_dashboard(sb, id_a), construir_dashboard(sb, id_b)
    if da is None or db_ is None:
        return None
    por_agente = []
    for aa in da["agentes"]:
        bb = next(x for x in db_["agentes"] if x["key"] == aa["key"])
        delta = (bb["score"] - aa["score"]) if (aa["score"] is not None and bb["score"] is not None
                                                and aa["con_info"] and bb["con_info"]) else None
        por_agente.append({"key": aa["key"], "nombre": aa["nombre"], "transversal": aa["transversal"],
                           "score_a": aa["score"] if aa["con_info"] else None,
                           "score_b": bb["score"] if bb["con_info"] else None,
                           "delta": delta,
                           "senales_a": sum(aa["senales"].values()), "senales_b": sum(bb["senales"].values())})

    # Señales que persisten / nuevas / resueltas: se emparejan por agente y similitud de título (aproximado)
    nuevas, resueltas, persisten = [], [], []
    usadas_b = set()
    for sa in da["senales"]:
        match = None
        for j, sb_ in enumerate(db_["senales"]):
            if j in usadas_b or sb_["agente"] != sa["agente"]:
                continue
            if similitud_titulos(sa["titulo"], sb_["titulo"]) >= UMBRAL_MISMA_SENAL:
                match = j
                break
        if match is None:
            resueltas.append(sa)
        else:
            usadas_b.add(match)
            persisten.append({**db_["senales"][match], "severidad_anterior": sa["severidad"]})
    nuevas = [s for j, s in enumerate(db_["senales"]) if j not in usadas_b]
    ga, gb = da["resumen"]["score_global"], db_["resumen"]["score_global"]
    return {
        "ok": True,
        "a": da["documento"], "b": db_["documento"],
        "global": {"a": ga, "b": gb, "delta": (gb - ga) if (ga is not None and gb is not None) else None},
        "senales_por_severidad": {"a": da["resumen"]["senales"], "b": db_["resumen"]["senales"]},
        "agentes": por_agente,
        "nuevas": nuevas, "resueltas": resueltas, "persisten": persisten,
        "nota": "El emparejamiento de señales entre documentos es aproximado (similitud de títulos).",
    }


_ESTADOS_PLAN = {"pendiente": "Pendiente", "curso": "En curso", "hecho": "Hecha"}
_CLS_SEV = {"crítica": "crit", "alta": "alta", "media": "media", "baja": "baja"}


def html_pdf_dashboard(d, acciones=None):
    """HTML del PDF del Dashboard. `acciones` = {id_recomendación: {estado, responsable, fecha}} (viene del navegador)."""
    acciones = acciones or {}
    r = d["resumen"]
    sv = r["senales"]
    kpis = "".join(
        f"<td><span class='big {_CLS_SEV[k]}'>{sv.get(k, 0)}</span><br/>{esc_pdf(etq)}</td>"
        for k, etq in (("crítica", "críticas"), ("alta", "altas"), ("media", "medias"), ("baja", "bajas")))
    resumen = (f"<table class='kpi'><tr><td style='width:28%'><span class='big'>{r['score_global'] if r['score_global'] is not None else '-'}</span>"
               f"<span class='muted'> /100</span><br/><b>{esc_pdf(r['etiqueta'])}</b><br/>"
               f"<span class='small muted'>Promedio de {r['agentes_con_info']} agentes con información</span></td>{kpis}</tr></table>"
               f"<p class='small muted'>{r['agentes_analizados']} de {r['agentes_total']} agentes analizados | {r['omisiones']} omisiones | "
               f"{r['preguntas']} preguntas probables | {r['recomendaciones']} recomendaciones | "
               f"{r['senales_transversales']} señales transversales (Riesgos y Estrategia repiten temas de otros agentes).</p>")
    orden = sorted(d["agentes"], key=lambda a: (a["score"] is None, a["score"] if a["score"] is not None else 999, a["nombre"]))
    filas = ""
    for a in orden:
        s_ = a["senales"]
        filas += (f"<tr><td><b>{esc_pdf(a['nombre'])}</b>{' (transversal)' if a.get('transversal') else ''}</td>"
                  f"<td class='num'>{a['score'] if a['score'] is not None and a.get('con_info') else '-'}</td><td>{esc_pdf(a['etiqueta'])}</td>"
                  f"<td class='num'>{s_['crítica']}</td><td class='num'>{s_['alta']}</td><td class='num'>{s_['media']}</td><td class='num'>{s_['baja']}</td>"
                  f"<td class='num'>{a['n_omisiones']}</td><td class='num'>{a['n_preguntas']}</td></tr>")
    sem = ("<h2>Semáforo por agente</h2><table><tr><th style='width:21%'>Agente</th><th class='num' style='width:9%'>Puntaje</th><th style='width:21%'>Estado</th><th class='num'>Crít.</th>"
           "<th class='num'>Altas</th><th class='num'>Medias</th><th class='num'>Bajas</th><th class='num'>Omis.</th><th class='num'>Preg.</th></tr>"
           f"{filas}</table>")
    orden_sev = {k: i for i, k in enumerate(SEVERIDADES)}
    sens = sorted(d["senales"], key=lambda x: (orden_sev.get(x["severidad"], 9), x.get("transversal", False)))
    filas = "".join(
        f"<tr><td><span class='{_CLS_SEV.get(x['severidad'], '')}'>{esc_pdf(x['severidad'].upper())}</span></td>"
        f"<td>{esc_pdf(x['agente_nombre'])}{' (transv.)' if x.get('transversal') else ''}</td>"
        f"<td><b>{esc_pdf(x['titulo'])}</b><br/><span class='muted'>{esc_pdf(x.get('descripcion', ''))}</span></td></tr>" for x in sens)
    señales = f"<h2>Señales ({len(sens)})</h2>" + (f"<table><tr><th style='width:11%'>Severidad</th><th style='width:17%'>Agente</th><th>Señal</th></tr>{filas}</table>" if sens else "<p class='muted'>Sin señales.</p>")
    filas = ""
    hechas = 0
    for rec in d["recomendaciones"]:
        a = acciones.get(rec["id"]) or {}
        est = a.get("estado") if a.get("estado") in _ESTADOS_PLAN else "pendiente"
        hechas += est == "hecho"
        filas += (f"<tr><td>{esc_pdf(rec['agente_nombre'])}</td><td>{esc_pdf(rec['texto'])}</td><td>{esc_pdf(a.get('responsable', '') or '-')}</td>"
                  f"<td>{esc_pdf(a.get('fecha', '') or '-')}</td><td>{_ESTADOS_PLAN[est]}</td></tr>")
    plan = (f"<h2>Plan de acción ({hechas} de {len(d['recomendaciones'])} hechas)</h2>" +
            (f"<table><tr><th style='width:14%'>Agente</th><th>Recomendación</th><th style='width:16%'>Responsable</th><th style='width:13%'>Fecha límite</th><th style='width:13%'>Estado</th></tr>{filas}</table>"
             if filas else "<p class='muted'>Sin recomendaciones.</p>"))
    doc = d["documento"]
    sub = f"Documento: {doc['nombre']} | Generado el {datetime.now().strftime('%d/%m/%Y %H:%M')}"
    return pagina_pdf("Dashboard de preparación", sub, resumen + sem + señales + plan)


def crear_router(get_supabase):
    router = APIRouter()
    aqui = os.path.dirname(os.path.abspath(__file__))

    @router.get("/api/dashboard/{document_id}")
    def api_dashboard(document_id: str):
        try:
            data = construir_dashboard(get_supabase(), document_id)
        except Exception as e:  # nunca romper el servidor por un módulo opcional
            print(f"[DASHBOARD] Error: {e}", flush=True)
            return JSONResponse({"ok": False, "error": str(e)})
        if data is None:
            return JSONResponse({"ok": False, "error": "Documento no encontrado"})
        return data

    @router.get("/api/dashboard-comparar/{id_a}/{id_b}")
    def api_comparar(id_a: str, id_b: str):
        try:
            data = comparar_documentos(get_supabase(), id_a, id_b)
        except Exception as e:
            print(f"[DASHBOARD] Error comparando: {e}", flush=True)
            return JSONResponse({"ok": False, "error": str(e)})
        if data is None:
            return JSONResponse({"ok": False, "error": "Documento no encontrado"})
        return data

    @router.post("/api/dashboard/{document_id}/pdf")
    def api_dashboard_pdf(document_id: str, payload: dict = Body(default={})):
        try:
            data = construir_dashboard(get_supabase(), document_id)
            if data is None:
                return JSONResponse({"ok": False, "error": "Documento no encontrado"}, status_code=404)
            pdf = html_a_pdf(html_pdf_dashboard(data, (payload or {}).get("acciones")))
        except Exception as e:
            print(f"[DASHBOARD] Error PDF: {e}", flush=True)
            return JSONResponse({"ok": False, "error": str(e)}, status_code=500)
        nombre = f"Directa_Dashboard_{datetime.now().strftime('%Y-%m-%d')}.pdf"
        return Response(content=pdf, media_type="application/pdf",
                        headers={"Content-Disposition": f'attachment; filename="{nombre}"'})

    @router.get("/dashboard.html")
    def pagina_dashboard():
        ruta = os.path.join(aqui, "dashboard.html")
        if os.path.exists(ruta):
            return FileResponse(ruta, media_type="text/html")
        return JSONResponse({"ok": False, "error": "dashboard.html no está junto a main.py"}, status_code=404)

    return router