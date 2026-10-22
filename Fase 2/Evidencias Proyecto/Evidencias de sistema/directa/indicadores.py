import os
from datetime import datetime
from fastapi import APIRouter, Body
from fastapi.responses import FileResponse, JSONResponse, Response

from modulos_base import (esc_pdf, html_a_pdf, pagina_pdf, seccion, parrafo, nota_pdf, tiles_pdf, tabla_pdf,
                          color_texto, COLOR_SEM, COLOR_SEV)
from dashboard import dashboard_cacheado

MAX_SOLUCIONES = 3


def estado_semaforo(valor, meta, limite, direccion):
    """'verde' | 'amarillo' | 'rojo' | 'sin_dato'."""
    try:
        v, m, l = float(valor), float(meta), float(limite)
    except (TypeError, ValueError):
        return "sin_dato"
    if direccion == "menor":
        return "verde" if v <= m else ("amarillo" if v <= l else "rojo")
    return "verde" if v >= m else ("amarillo" if v >= l else "rojo")


def _recs(d, agentes):
    """Recomendaciones de los agentes indicados (sin repetir), máximo MAX_SOLUCIONES."""
    claves = set(agentes)
    out = []
    for r in d["recomendaciones"]:
        if r["agente"] in claves and r["texto"] not in out:
            out.append(r["texto"])
        if len(out) >= MAX_SOLUCIONES:
            break
    return out


def construir_sugeridos(sb, document_id, refrescar=False):
    d = dashboard_cacheado(sb, document_id, refrescar)
    if d is None:
        return None
    r = d["resumen"]
    ags = d["agentes"]
    analizados = [a for a in ags if a["estado"] == "ok"]
    con_sev = lambda sev: [a["key"] for a in ags if a["senales"].get(sev, 0) > 0]
    serios = [a for a in analizados if a["con_info"] and a["banda"] in ("serio", "critico")]
    pendientes = [a["nombre"] for a in ags if a["estado"] != "ok"]
    por_score = [a["key"] for a in sorted((a for a in analizados if a["con_info"]), key=lambda a: a["score"])][:3]

    def pct(a, b):
        return round(100 * a / b) if b else None

    def item(id_, tipo, nombre, valor, unidad, meta, limite, direccion, como, soluciones):
        return {"id": id_, "tipo": tipo, "nombre": nombre, "valor": valor, "unidad": unidad,
                "meta": meta, "limite": limite, "direccion": direccion, "como": como,
                "soluciones": soluciones, "origen": "auto",
                "estado": estado_semaforo(valor, meta, limite, direccion) if valor is not None else "sin_dato"}

    items = [
        item("kpi-score", "KPI", "Puntaje global de preparación", r["score_global"], "/100", 75, 55, "mayor",
             "Promedio del puntaje de los agentes que encontraron información relevante.",
             _recs(d, por_score)),
        item("kpi-cobertura", "KPI", "Cobertura del análisis", pct(r["agentes_analizados"], r["agentes_total"]), "%", 100, 70, "mayor",
             "Porcentaje de agentes que ya analizaron este documento.",
             [f"Ejecutar el análisis de los agentes pendientes: {', '.join(pendientes[:6])}."] if pendientes else []),
        item("kpi-informacion", "KPI", "Agentes con información relevante", pct(r["agentes_con_info"], r["agentes_analizados"]), "%", 80, 50, "mayor",
             "De los agentes analizados, cuántos encontraron datos útiles en el documento.",
             ["Completar el documento con la información que echan de menos los agentes sin hallazgos."] if r["agentes_analizados"] and r["agentes_con_info"] < r["agentes_analizados"] else []),
        item("kri-criticas", "KRI", "Señales críticas abiertas", r["senales"]["crítica"], "", 0, 2, "menor",
             "Cantidad de señales de severidad crítica detectadas por los agentes.",
             _recs(d, con_sev("crítica"))),
        item("kri-altas", "KRI", "Señales de severidad alta", r["senales"]["alta"], "", 2, 5, "menor",
             "Cantidad de señales de severidad alta detectadas por los agentes.",
             _recs(d, con_sev("alta"))),
        item("kri-areas", "KRI", "Áreas con observaciones serias o críticas", len(serios), "", 0, 2, "menor",
             "Agentes cuyo puntaje queda por debajo de 55 (observaciones serias o críticas).",
             _recs(d, [a["key"] for a in serios])),
        item("kri-omisiones", "KRI", "Omisiones detectadas", r["omisiones"], "", 3, 10, "menor",
             "Temas que el documento debería cubrir y no cubre, según los agentes.",
             ["Completar en el documento: " + o["texto"] for o in d["omisiones"][:MAX_SOLUCIONES]]),
    ]
    return {"ok": True, "documento": d["documento"], "indicadores": items}


_TXT = {"verde": "En meta", "amarillo": "Atención", "rojo": "Fuera de meta", "sin_dato": "Sin dato"}
_EST_SOL = {"pendiente": "Pendiente", "curso": "En curso", "hecho": "Hecha"}


def _num(x):
    try:
        f = float(x)
        return str(int(f)) if f == int(f) else str(round(f, 2))
    except (TypeError, ValueError):
        return "-"


def _fila(i):
    sol = i.get("solucion") or "; ".join(i.get("soluciones") or [])
    est = _EST_SOL.get(i.get("estado_solucion") or "", "")
    meta = ("<= " if i.get("direccion") == "menor" else ">= ") + _num(i.get("meta"))
    if i.get("limite") not in (None, ""):
        meta += f"<br/><span class='small muted'>Rojo si {'>' if i.get('direccion') == 'menor' else '<'} {esc_pdf(_num(i.get('limite')))}</span>"
    origen = "sugerido" if i.get("origen") == "auto" else "propio"
    detalle = " | ".join(x for x in (i.get("responsable") or "", i.get("fecha") or "", est) if x)
    return [f"<b>{esc_pdf(i.get('nombre', ''))}</b><br/><span class='small muted'>{esc_pdf(i.get('tipo', ''))} {origen}</span>",
            f"<b>{esc_pdf(_num(i.get('valor')))}{esc_pdf(i.get('unidad') or '')}</b>", meta,
            color_texto(_TXT[i["estado"]].upper(), COLOR_SEM[i["estado"]]),
            (esc_pdf(sol) or "-") + (f"<br/><span class='small muted'>{esc_pdf(detalle)}</span>" if detalle else "")]


def html_pdf_indicadores(doc_nombre, indicadores):
    for i in indicadores:
        if i.get("estado") not in _TXT:
            i["estado"] = estado_semaforo(i.get("valor"), i.get("meta"), i.get("limite"), i.get("direccion"))
    rojos = [i for i in indicadores if i["estado"] == "rojo"]
    amar = [i for i in indicadores if i["estado"] == "amarillo"]
    verdes = [i for i in indicadores if i["estado"] == "verde"]
    n = len(indicadores)
    if not n:
        lectura = "No hay indicadores para mostrar."
    else:
        lectura = f"Se monitorean {n} indicadores: {len(rojos)} fuera de meta, {len(amar)} en atención y {len(verdes)} en meta."
        if rojos:
            lectura += " Requieren acción inmediata: " + ", ".join(i.get("nombre", "") for i in rojos[:4]) + "."
    cuerpo = seccion(1, "Resumen ejecutivo") + parrafo(lectura)
    cuerpo += tiles_pdf([(len(rojos), "Fuera de meta", COLOR_SEM["rojo"]), (len(amar), "En atención", COLOR_SEM["amarillo"]),
                         (len(verdes), "En meta", COLOR_SEM["verde"]), (n, "Indicadores", None)])
    orden = {"rojo": 0, "amarillo": 1, "sin_dato": 2, "verde": 3}
    num = 2
    for tipo, titulo, expl in (("KPI", "KPI - Indicadores de desempeño", "Miden si se están cumpliendo las metas. Mientras más alto, mejor."),
                               ("KRI", "KRI - Indicadores de riesgo", "Avisan cuando la organización se acerca a un problema. Mientras más bajo, mejor.")):
        lista = sorted((i for i in indicadores if i.get("tipo") == tipo), key=lambda i: orden[i["estado"]])
        cuerpo += seccion(num, titulo) + parrafo(expl)
        cuerpo += (tabla_pdf(["Indicador", "Valor", "Meta", "Estado", "Solución / responsable / fecha"], [_fila(i) for i in lista],
                             ["24%", "10%", "14%", "12%", "40%"]) if lista else parrafo("Sin indicadores."))
        num += 1
    cuerpo += seccion(num, "Cómo leer el semáforo")
    cuerpo += tabla_pdf(["Estado", "Significado"], [
        [color_texto("EN META", COLOR_SEM["verde"]), "El indicador cumple la meta definida."],
        [color_texto("ATENCIÓN", COLOR_SEM["amarillo"]), "No cumple la meta, pero todavía no supera el límite definido."],
        [color_texto("FUERA DE META", COLOR_SEM["rojo"]), "Superó el límite: requiere una solución con responsable y fecha."]], ["22%", "78%"])
    meta = [("Documento base", doc_nombre), ("Fecha de emisión", datetime.now().strftime("%d/%m/%Y %H:%M")),
            ("Indicadores", str(n)), ("Clasificación", "Confidencial")]
    return pagina_pdf("Indicadores de Gestión", "KPI, KRI y soluciones para la Gerencia General", cuerpo, meta, "Indicadores de Gestión")


_CACHE_SUG = {}


def sugerir_indicador(sb, p):
    """Rellena un indicador con IA (una consulta corta). Contexto: solo los títulos de las señales ya analizadas."""
    modo = "solucion" if p.get("modo") == "solucion" else "form"
    tipo = "KRI" if str(p.get("tipo")).upper() == "KRI" else "KPI"
    nombre = " ".join(str(p.get("nombre") or "").split())[:120]
    doc = str(p.get("documento_id") or "")
    clave = (modo, tipo, nombre.lower(), str(p.get("valor")), str(p.get("meta")), doc)
    if clave in _CACHE_SUG:
        return {**_CACHE_SUG[clave], "cache": True}
    senales = []
    if doc:
        d = dashboard_cacheado(sb, doc, False) or {}
        for sg in (d.get("senales") or [])[:6]:
            senales.append(f"- ({sg.get('severidad')}) {str(sg.get('titulo') or '')[:110]}")
    ctx = "Señales detectadas en el documento:\n" + ("\n".join(senales) or "(ninguna)")
    if modo == "solucion":
        ctx += (f"\n\nIndicador {tipo}: {nombre}. Valor actual: {p.get('valor')} {p.get('unidad') or ''}. Meta: {p.get('meta')}. "
                f"Límite (rojo): {p.get('limite')}. Estado: {p.get('estado')}.")
        sis = ("Eres asesor del Gerente General de una empresa chilena. Propón la acción concreta para llevar este indicador a verde. "
               "Devuelve SOLO un JSON {\"solucion\": texto de 1 a 2 frases en imperativo, \"responsable\": área sugerida}. "
               "Sin cifras inventadas ni markdown.")
    else:
        ctx += f"\n\nTipo pedido: {tipo} ({'riesgo: más bajo es mejor' if tipo == 'KRI' else 'desempeño: más alto es mejor'}). Nombre escrito: {nombre or '(vacío: propón uno relevante)'}"
        sis = ("Eres asesor del Gerente General de una empresa chilena. Ayuda a definir un indicador. Devuelve SOLO un JSON "
               "{\"nombre\": nombre corto, \"unidad\": unidad (%, $, días, número), \"meta\": número objetivo típico, "
               "\"limite\": número a partir del cual se pone rojo, \"como\": una frase de cómo se mide, "
               "\"solucion\": acción si no está en verde (1 frase), \"responsable\": área}. "
               "Meta y límite son referencias típicas de mercado y el usuario las ajustará; NO inventes el valor actual. "
               "En un KRI el límite es mayor que la meta; en un KPI el límite es menor que la meta. Sin markdown.")
    from ia_config import llamar_llm_chat, parsear_json_respuesta
    obj = parsear_json_respuesta(llamar_llm_chat(sis, ctx, temperatura=0.2, max_tokens=900, json_mode=True) or "")
    limpio = lambda t, n=300: " ".join(str(t or "").replace("*", "").replace("#", "").split())[:n]
    def num(x):
        try:
            return float(str(x).replace(",", ".").replace("%", "").strip())
        except Exception:
            return None
    res = {"ok": True, "solucion": limpio(obj.get("solucion")), "responsable": limpio(obj.get("responsable"), 60)}
    if modo == "form":
        res.update({"nombre": limpio(obj.get("nombre"), 120), "unidad": limpio(obj.get("unidad"), 12),
                    "meta": num(obj.get("meta")), "limite": num(obj.get("limite")), "como": limpio(obj.get("como"))})
    if not res["solucion"] and not res.get("nombre"):
        return {"ok": False, "error": "La IA no devolvió una sugerencia útil. Intenta de nuevo."}
    _CACHE_SUG[clave] = res
    return res


def crear_router(get_supabase):
    router = APIRouter()
    aqui = os.path.dirname(os.path.abspath(__file__))

    @router.get("/api/indicadores/sugeridos/{document_id}")
    def api_sugeridos(document_id: str, refrescar: int = 0):
        try:
            data = construir_sugeridos(get_supabase(), document_id, bool(refrescar))
        except Exception as e:  # nunca romper el servidor por un módulo opcional
            print(f"[INDICADORES] Error: {e}", flush=True)
            return JSONResponse({"ok": False, "error": str(e)})
        if data is None:
            return JSONResponse({"ok": False, "error": "Documento no encontrado"})
        return data

    @router.post("/api/indicadores/sugerir")
    def api_sugerir(payload: dict = Body(default={})):
        try:
            return sugerir_indicador(get_supabase(), payload or {})
        except Exception as e:
            print(f"[INDICADORES] Error sugerir: {e}", flush=True)
            return JSONResponse({"ok": False, "error": "No se pudo generar la sugerencia: " + str(e)[:150]})

    @router.post("/api/indicadores/pdf")
    def api_pdf(payload: dict = Body(default={})):
        try:
            payload = payload or {}
            did = str(payload.get("documento_id") or "")
            sug = construir_sugeridos(get_supabase(), did) if did else None
            lista = list(sug["indicadores"]) if sug else []
            # lo que el gerente editó sobre los sugeridos (solución, responsable, fecha, estado)
            ajustes = payload.get("ajustes") or {}
            for i in lista:
                a = ajustes.get(i["id"]) or {}
                for k in ("responsable", "fecha", "estado_solucion", "solucion"):
                    if a.get(k):
                        i[k] = str(a[k])
            for m in (payload.get("propios") or []):
                if isinstance(m, dict) and m.get("nombre"):
                    m = {k: m.get(k) for k in ("id", "tipo", "nombre", "valor", "unidad", "meta", "limite", "direccion",
                                               "solucion", "responsable", "fecha", "estado_solucion")}
                    m["tipo"] = "KRI" if m.get("tipo") == "KRI" else "KPI"
                    m["direccion"] = "menor" if m.get("direccion") == "menor" else "mayor"
                    m["origen"] = "propio"
                    m["estado"] = estado_semaforo(m.get("valor"), m.get("meta"), m.get("limite"), m["direccion"])
                    lista.append(m)
            nombre_doc = sug["documento"]["nombre"] if sug else "(sin documento)"
            pdf = html_a_pdf(html_pdf_indicadores(nombre_doc, lista))
        except Exception as e:
            print(f"[INDICADORES] Error PDF: {e}", flush=True)
            return JSONResponse({"ok": False, "error": str(e)}, status_code=500)
        nombre = f"Directa_Indicadores_{datetime.now().strftime('%Y-%m-%d')}.pdf"
        return Response(content=pdf, media_type="application/pdf",
                        headers={"Content-Disposition": f'attachment; filename="{nombre}"'})

    @router.get("/indicadores.html")
    def pagina_indicadores():
        ruta = os.path.join(aqui, "indicadores.html")
        if os.path.exists(ruta):
            return FileResponse(ruta, media_type="text/html")
        return JSONResponse({"ok": False, "error": "indicadores.html no está junto a main.py"}, status_code=404)

    return router