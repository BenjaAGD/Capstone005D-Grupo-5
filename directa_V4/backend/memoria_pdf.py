# -*- coding: utf-8 -*-
"""Borrador de memoria anual en un paso (Frentes D1 y D2).

El gerente elige el año y obtiene un PDF para revisar con:
  portada con logo y colores del cliente, índice, carta del Gerente General en el tono aprobado,
  los capítulos de la NCG 461 (sus notas o un borrador del Redactor), páginas de indicadores con
  gráficos, una página tipo dashboard, la tabla de cobertura de la norma y la revisión de cifras.

Cada cifra de los textos pasa por la capa 1 del verificador contra los documentos del año, y se marcan
las que solo aparecen en documentos de años anteriores. Los gráficos usan datos calculados por DIRECTA
(análisis de los agentes) o ingresados por el usuario, y el PDF dice cuál es cuál.
Corre en segundo plano: POST /api/memoria/borrador -> GET /api/memoria/borrador/{id} -> GET .../pdf
"""
import base64
import os
import re
import threading
import time
import uuid
from datetime import datetime

from fastapi import APIRouter, Body
from fastapi.responses import JSONResponse, Response

import graficos
from modulos_base import (esc_pdf, html_a_pdf, tabla_pdf, tiles_pdf, nota_pdf, color_texto, listar_documentos,
                          CSS_PDF, CLASIFICACION, COLOR_SEV)

MARCA_CARTA = "[CARTA MEMORIA DIRECTA]"
_RE_COLOR = re.compile(r"^#[0-9A-Fa-f]{6}$")
_RE_LOGO = re.compile(r"^data:image/(png|jpe?g);base64,[A-Za-z0-9+/=\s]+$")
jobs = {}
_TTL_JOB = 3600


def documentos_por_anio(sb):
    import tono
    out = {}
    for d in listar_documentos(sb):
        if d.get("estado") not in ("Listo", "Listo con errores"):
            continue
        anio = tono.anio_de(d.get("titulo") or d.get("nombre_archivo") or "")
        if anio:
            out.setdefault(anio, []).append({"id": d["id"], "nombre": d.get("titulo") or d.get("nombre_archivo")})
    return [{"anio": a, "documentos": out[a]} for a in sorted(out, reverse=True)]


def _marca(m):
    m = m or {}
    color = str(m.get("color") or "").strip()
    logo = str(m.get("logo") or "").strip()
    if logo and (len(logo) > 2_000_000 or not _RE_LOGO.match(logo)):
        logo = ""
    return {"nombre": " ".join(str(m.get("nombre") or "").split())[:80],
            "color": color if _RE_COLOR.match(color) else "#1B2F4B",
            "logo": re.sub(r"\s+", "", logo)}


def _carta(contexto, perfil, anio, empresa):
    import ia_config as _ia
    import tono
    sistema = (f"{MARCA_CARTA}\nEres el Redactor de memoria de DIRECTA. Escribe la carta del Gerente General para la "
               f"memoria anual {anio} de {empresa or 'la empresa'}: tres párrafos, máximo 230 palabras en total, sin "
               "listas ni markdown. Usa SOLO los hechos del contexto; si falta un dato escribe [COMPLETAR: dato]. No "
               "inventes cifras y no uses cifras de otros años como si fueran de este. Cierra con un agradecimiento y "
               "la firma 'Gerente General'. Español.")
    if perfil:
        sistema += "\n\n" + tono.bloque_para_prompt(perfil)
    texto = _ia.llamar_llm_chat(sistema, contexto + "\n\nEscribe la carta.", temperatura=0.3, max_tokens=900)
    return re.sub(r"[*#_`]+", "", str(texto or "")).strip()


def _contexto_carta(dash):
    partes = []
    r = dash.get("resumen") or {}
    if r.get("score_global") is not None:
        partes.append(f"Puntaje global de preparación según los agentes: {r['score_global']}/100.")
    prioridad = ["financiero", "estrategia", "operaciones", "rrhh", "esg", "stakeholders", "capital", "comercial"]
    por_key = {a["key"]: a for a in dash.get("agentes", [])}
    for k in prioridad:
        a = por_key.get(k)
        if a and a.get("con_info") and a.get("resumen"):
            partes.append(f"{a['nombre']}: {a['resumen'][:420]}")
    return "CONTEXTO (resúmenes de los agentes sobre los documentos del año):\n" + "\n".join(partes)


def _texto_html(texto):
    """Párrafos con los [COMPLETAR: …] resaltados."""
    out = []
    for p in re.split(r"\n\s*\n", str(texto or "").strip()):
        if not p.strip():
            continue
        h = esc_pdf(p.strip())
        h = re.sub(r"\[COMPLETAR:([^\]]*)\]", r"<span style='background-color:#FFF1C2;color:#7A5200;'>[COMPLETAR:\1]</span>", h)
        out.append(f"<p>{h}</p>")
    return "".join(out) or "<p class='muted'>Sin texto.</p>"


def _html(ctx):
    m = ctx["marca"]
    color = m["color"]
    css = CSS_PDF.replace("#1B2F4B", color)
    empresa = m["nombre"] or ctx["empresa"] or "La empresa"
    anio = ctx["anio"]
    cab = (f"<div id='pdf_cab'><table width='100%'><tr><td class='cab'><b>{esc_pdf(empresa.upper())}</b> &nbsp;|&nbsp; "
           f"Memoria Anual {anio}</td><td class='cab' align='right'>Borrador para revisión</td></tr></table></div>")
    pie = (f"<div id='pdf_pie'><table width='100%'><tr><td class='pie'>{esc_pdf(CLASIFICACION)}</td>"
           f"<td class='pie' align='right'>P&aacute;gina <pdf:pagenumber/> de <pdf:pagecount/></td></tr></table></div>")
    logo = f"<img src='{m['logo']}' style='height:1.8cm;'/><br/><br/>" if m["logo"] else ""
    foto_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "memoria_portada_edificio.jpg")
    try:
        with open(foto_path, "rb") as f:
            foto_url = "data:image/jpeg;base64," + base64.b64encode(f.read()).decode("ascii")
    except OSError:
        foto_url = ""
    foto = f"<img src='{foto_url}' style='width:9.2cm;height:15.8cm;'/>" if foto_url else ""
    portada = (f"<table class='cover' width='100%' cellpadding='0' cellspacing='0' style='margin-top:0.3cm;'><tr>"
               f"<td class='coverleft' width='45%' style='background-color:{color};'>"
               f"{logo}<span class='cover-kicker'>MEMORIA CORPORATIVA</span><br/><br/>"
               f"<span class='cover-title'>Memoria<br/>anual</span><br/><br/>"
               f"<span class='cover-year'>{anio}</span><br/><br/>"
               f"<span class='cover-caption'>Preparada para<br/>{esc_pdf(empresa)}</span></td>"
               f"<td width='55%' style='padding:0;'>{foto}</td></tr></table>"
               f"<p class='small muted' style='margin-top:8pt;'>Borrador generado por DIRECTA el "
               f"{datetime.now().strftime('%d/%m/%Y')} para revisi&oacute;n del Gerente General. Los textos en amarillo "
               f"([COMPLETAR]) requieren datos del &aacute;rea responsable. Estructura seg&uacute;n la NCG 461 de la CMF.</p>"
               f"<pdf:nextpage/>")

    secciones = ["Carta del Gerente General"] + [f"{c['numero']}. {c['titulo']}" for c in ctx["capitulos"]] + [
        "Indicadores", "Panorama del ejercicio", "Cobertura de la NCG 461", "Revisión de cifras"]
    indice = ("<h2>Índice</h2><table class='dat' width='100%'>" + "".join(
        f"<tr><td class='{'z' if i % 2 else ''}'>{esc_pdf(t)}</td></tr>" for i, t in enumerate(secciones)) + "</table><pdf:nextpage/>")

    cuerpo = f"<h2>Carta del Gerente General</h2>{_texto_html(ctx['carta'])}<pdf:nextpage/>"
    for c in ctx["capitulos"]:
        cuerpo += f"<h2>{c['numero']}. {esc_pdf(c['titulo'])}</h2>"
        cuerpo += f"<p class='small muted'>{esc_pdf(c['descripcion'])} · Origen del texto: {esc_pdf(c['origen'])}</p>"
        cuerpo += _texto_html(c["texto"])
        if c.get("pendientes"):
            cuerpo += tabla_pdf(["Dato pendiente", "Quién lo aporta"],
                                [[esc_pdf(p.get("dato", "")), esc_pdf(p.get("quien", "") or "-")] for p in c["pendientes"]],
                                ["70%", "30%"])

    cuerpo += "<pdf:nextpage/><h2>Indicadores</h2>"
    if ctx["graf_indicadores"]:
        cuerpo += graficos.img_html(ctx["graf_indicadores"])
    filas = []
    for i in ctx["indicadores"]:
        origen = "Ingresado por el usuario" if i.get("origen") != "auto" else "Calculado por DIRECTA (análisis de los agentes)"
        filas.append([f"<b>{esc_pdf(i.get('nombre', ''))}</b><br/><span class='small muted'>{esc_pdf(i.get('tipo', ''))}</span>",
                      esc_pdf(f"{i.get('valor', '-')}{i.get('unidad') or ''}"), esc_pdf(str(i.get("meta", "-"))),
                      color_texto(graficos.ETQ_SEM.get(i.get("estado"), "Sin dato").upper(),
                                  graficos.COLOR_SEM.get(i.get("estado"), "#5F6877")), esc_pdf(origen)])
    if filas:
        cuerpo += tabla_pdf(["Indicador", "Valor", "Meta", "Estado", "Origen del dato"], filas, ["34%", "12%", "10%", "16%", "28%"])
    else:
        cuerpo += "<p class='muted'>No hay indicadores con valor y meta.</p>"

    r = ctx["dash"].get("resumen") or {}
    sev = r.get("senales") or {}
    cuerpo += "<pdf:nextpage/><h2>Panorama del ejercicio</h2>"
    cuerpo += tiles_pdf([
        (r.get("score_global") if r.get("score_global") is not None else "-", "Puntaje global", color),
        (sev.get("crítica", 0), "Señales críticas", COLOR_SEV["crítica"]),
        (sev.get("alta", 0), "Señales altas", COLOR_SEV["alta"]),
        (f"{ctx['cobertura_resumen'].get('fuertes', 0) + ctx['cobertura_resumen'].get('debiles', 0)}/"
         f"{ctx['cobertura_resumen'].get('temas_total', 0)}", "Temas NCG con evidencia", None),
    ])
    for g in (ctx["graf_senales"], ctx["graf_areas"], ctx["graf_evolucion"]):
        if g:
            cuerpo += graficos.img_html(g) + "<br/>"
    cuerpo += nota_pdf("Puntajes y señales calculados por DIRECTA a partir del análisis de los agentes sobre los "
                       "documentos del año; no son cifras de los estados financieros.")

    cuerpo += "<pdf:nextpage/><h2>Cobertura de la NCG 461</h2>"
    filas = []
    for c in ctx["cobertura_capitulos"]:
        for t in c["temas"]:
            ev = {"fuerte": color_texto("Con evidencia", "#2F6B4F"), "debil": color_texto("Evidencia débil", "#A67C00"),
                  "ninguna": color_texto("Sin evidencia", "#8E1B2E")}.get(t["nivel"], "")
            pg = ", ".join(f"pág. {p['pagina']}" for p in t.get("paginas", [])[:4] if p.get("pagina") is not None)
            filas.append([f"{c['numero']}", esc_pdf(t["nombre"]), ev, esc_pdf(pg) or "-"])
    cuerpo += tabla_pdf(["Cap.", "Tema que pide la norma", "Evidencia", "Dónde mirar"], filas, ["7%", "53%", "18%", "22%"])

    cuerpo += "<h2>Revisión de cifras</h2>"
    if ctx["revision"]:
        cuerpo += tabla_pdf(["Sección", "Alerta"], [[esc_pdf(s), esc_pdf(a)] for s, a in ctx["revision"]], ["28%", "72%"])
    else:
        cuerpo += "<p>Todas las cifras de los textos aparecen en los documentos del año o se recalculan con ellos.</p>"
    cuerpo += nota_pdf("La revisión comprueba que cada cifra esté en los documentos del año y marca las que solo aparecen "
                       "en documentos de años anteriores. No comprueba que los documentos sean correctos. Documentos del "
                       f"año: {', '.join(d['nombre'] for d in ctx['documentos'])}.")
    return (f"<html><head><meta charset='utf-8'/><style>{css}</style></head><body>{cab}{pie}{portada}{indice}{cuerpo}"
            "</body></html>")


def generar(get_sb, job, anio, marca=None, caps=None, propios=None, carta=None):
    import memoria
    import tono
    from dashboard import dashboard_cacheado
    from indicadores import construir_sugeridos, estado_semaforo
    sb = get_sb()
    caps = caps or {}
    grupos = {g["anio"]: g["documentos"] for g in documentos_por_anio(sb)}
    docs = grupos.get(int(anio))
    if not docs:
        raise ValueError(f"No hay documentos listos del año {anio}.")
    ids = [d["id"] for d in docs]
    job.update({"paso": "Leyendo los documentos del año", "total": len(memoria.CAPITULOS) + 4, "hechos": 0})
    data = memoria.construir_cobertura_cacheada(sb, ids)
    if not data.get("ok"):
        raise ValueError(data.get("error") or "No se pudo leer la cobertura")
    perfil = tono.perfil_aprobado(get_sb)
    principal = ids[0]
    dash = dashboard_cacheado(sb, principal) or {}
    job["hechos"] += 1

    job["paso"] = "Redactando la carta del Gerente General"
    empresa = (marca or {}).get("nombre") or ""
    texto_carta = (carta or "").strip() or _carta(_contexto_carta(dash), perfil, anio, empresa)
    job["hechos"] += 1

    capitulos, revision = [], []
    clave = ",".join(sorted(ids))
    for cap in memoria.CAPITULOS:
        job["paso"] = f"Capítulo {cap['numero']}: {cap['titulo']}"
        estado = caps.get(cap["id"]) or {}
        notas = str(estado.get("notas") or "").strip()
        if notas:
            texto, pendientes, origen = notas, [], "notas del equipo"
        else:
            r = memoria.sugerir_borrador(data, cap["id"], clave, perfil)
            texto, pendientes = r.get("texto") or "[COMPLETAR: texto del capítulo]", r.get("pendientes") or []
            origen = "borrador del Redactor de memoria" + (" (con perfil de tono)" if perfil else "")
        capitulos.append({"numero": cap["numero"], "titulo": cap["titulo"], "descripcion": cap["descripcion"],
                          "texto": texto, "pendientes": pendientes, "origen": origen})
        job["hechos"] += 1

    job["paso"] = "Revisando las cifras"
    for nombre, texto in [("Carta del Gerente General", texto_carta)] + [(f"{c['numero']}. {c['titulo']}", c["texto"]) for c in capitulos]:
        rv = memoria.revisar_cifras_borrador(sb, texto, ids)
        for a in rv["alertas"]:
            revision.append((nombre, a))
        for o in rv["otros_periodos"]:
            revision.append((nombre, f"La cifra «{o['cifra']}» aparece solo en un documento de un año anterior "
                                     f"({o.get('documento') or 'otro documento'}, pág. {o.get('pagina') or '?'})."))
    job["hechos"] += 1

    job["paso"] = "Dibujando los gráficos"
    sug = construir_sugeridos(sb, principal) or {}
    indicadores = list(sug.get("indicadores") or [])
    for p in (propios or []):
        if isinstance(p, dict) and p.get("nombre"):
            p = {**p, "origen": "propio"}
            p["estado"] = estado_semaforo(p.get("valor"), p.get("meta"), p.get("limite"), p.get("direccion") or "mayor")
            indicadores.append(p)
    r = dash.get("resumen") or {}
    areas = [(a["nombre"], a["score"]) for a in dash.get("agentes", []) if a.get("con_info")]
    evol = []
    for a in sorted(grupos):
        if a <= int(anio):
            d = dashboard_cacheado(sb, grupos[a][0]["id"]) or {}
            evol.append((str(a), (d.get("resumen") or {}).get("score_global")))
    ctx = {
        "anio": int(anio), "marca": _marca(marca), "empresa": empresa, "carta": texto_carta, "capitulos": capitulos,
        "indicadores": [i for i in indicadores if i.get("valor") is not None], "dash": dash,
        "graf_indicadores": graficos.cumplimiento_indicadores(indicadores),
        "graf_senales": graficos.senales_por_severidad(r.get("senales") or {}),
        "graf_areas": graficos.puntaje_por_area(areas),
        "graf_evolucion": graficos.evolucion(evol),
        "cobertura_capitulos": data["capitulos"], "cobertura_resumen": data["resumen"],
        "revision": revision, "documentos": docs,
    }
    job["hechos"] += 1
    job["paso"] = "Armando el PDF"
    pdf = html_a_pdf(_html(ctx))
    job.update({"pdf": pdf, "revision": [{"seccion": s, "alerta": a} for s, a in revision], "carta": texto_carta,
                "tono": {"version": perfil.get("version")} if perfil else None,
                "graficos": sum(1 for k in ("graf_indicadores", "graf_senales", "graf_areas", "graf_evolucion") if ctx[k]),
                "nombre": f"Memoria_Anual_{anio}_borrador.pdf"})


def crear_router(get_supabase):
    router = APIRouter()

    @router.get("/api/memoria/anios")
    def api_anios():
        try:
            return {"ok": True, "anios": documentos_por_anio(get_supabase())}
        except Exception as e:  # noqa: BLE001
            return JSONResponse({"ok": False, "error": str(e)[:300]})

    @router.post("/api/memoria/borrador")
    def api_borrador(payload: dict = Body(default={})):
        payload = payload or {}
        try:
            anio = int(payload.get("anio"))
        except (TypeError, ValueError):
            return JSONResponse({"ok": False, "error": "Indica el año de la memoria."})
        for k in [k for k, j in jobs.items() if time.time() - j["inicio"] > _TTL_JOB]:
            jobs.pop(k, None)
        job_id = str(uuid.uuid4())
        job = {"job_id": job_id, "inicio": time.time(), "corriendo": True, "error": None, "paso": "Iniciando",
               "hechos": 0, "total": 1, "anio": anio}
        jobs[job_id] = job

        def worker():
            try:
                generar(get_supabase, job, anio, payload.get("marca"), payload.get("caps"), payload.get("propios"),
                        payload.get("carta"))
            except Exception as e:  # noqa: BLE001
                import traceback
                traceback.print_exc()
                job["error"] = str(e)[:300]
            finally:
                job["corriendo"] = False
        threading.Thread(target=worker, daemon=True).start()
        return {"ok": True, "job_id": job_id}

    @router.get("/api/memoria/borrador/{job_id}")
    def api_estado(job_id: str):
        job = jobs.get(job_id)
        if not job:
            return JSONResponse({"ok": False, "error": "Borrador no encontrado (el servidor pudo reiniciarse)."})
        return {"ok": True, **{k: v for k, v in job.items() if k not in ("pdf", "inicio")}, "listo": bool(job.get("pdf"))}

    @router.get("/api/memoria/borrador/{job_id}/pdf")
    def api_pdf(job_id: str):
        job = jobs.get(job_id)
        if not job or not job.get("pdf"):
            return JSONResponse({"ok": False, "error": "El PDF todavía no está listo."}, status_code=404)
        return Response(content=job["pdf"], media_type="application/pdf",
                        headers={"Content-Disposition": f'attachment; filename="{job["nombre"]}"'})

    return router
