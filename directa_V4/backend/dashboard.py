
import os
import time
from datetime import datetime
from fastapi import APIRouter, Body
from fastapi.responses import FileResponse, JSONResponse, Response

from modulos_base import (
    SEVERIDADES, agentes_analizables, nombre_corto, es_integrador, tiene_info, score_de,
    etiqueta_score, banda_score, senales_de, lista_textos, id_estable, info_documento,
    cargar_analisis, similitud_titulos, esc_pdf, html_a_pdf, pagina_pdf,
    seccion, parrafo, nota_pdf, tiles_pdf, tabla_pdf, color_texto, COLOR_SEV, NAVY,
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


_CACHE_DASH = {}
CACHE_DASH_SEG = 45


def dashboard_cacheado(sb, document_id, refrescar=False):
    """Igual que construir_dashboard, pero reutiliza el resultado de los últimos 45 s (el análisis no cambia a cada rato)."""
    ahora = time.time()
    hit = _CACHE_DASH.get(document_id)
    if hit and not refrescar and ahora - hit[0] < CACHE_DASH_SEG:
        return hit[1]
    data = construir_dashboard(sb, document_id)
    if data is not None:
        _CACHE_DASH[document_id] = (ahora, data)
    return data


def comparar_documentos(sb, id_a, id_b):
    """A = documento base (anterior), B = documento nuevo. Todo sale de lo ya guardado."""
    da, db_ = dashboard_cacheado(sb, id_a), dashboard_cacheado(sb, id_b)
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
_PLURAL_SEV = {"crítica": "críticas", "alta": "altas", "media": "medias", "baja": "bajas"}
_BANDAS_TXT = (("90 a 100", "Sin observaciones", "No hay hallazgos que requieran acción."),
               ("75 a 89", "Menor atención", "Observaciones menores; conviene revisarlas."),
               ("55 a 74", "Requiere revisión", "Hay temas que deben revisarse antes de la reunión."),
               ("40 a 54", "Observaciones serias", "Hay riesgos relevantes que exigen un plan de acción."),
               ("0 a 39", "Observaciones críticas", "Situación que requiere atención inmediata."))


def _sev_txt(sv):
    return color_texto(sv.upper(), COLOR_SEV.get(sv, NAVY))


def _fecha_hoy():
    return datetime.now().strftime("%d/%m/%Y %H:%M")


def html_pdf_dashboard(d, acciones=None):
    """PDF corporativo del Dashboard. `acciones` = {id_recomendación: {estado, responsable, fecha}} (viene del navegador)."""
    acciones = acciones or {}
    r = d["resumen"]
    sv = r["senales"]
    doc = d["documento"]

    # 1. Resumen ejecutivo
    con_info = sorted((a for a in d["agentes"] if a["con_info"] and a["score"] is not None), key=lambda a: a["score"])
    if r["score_global"] is None:
        lectura = "Aún no hay análisis suficientes para calcular un puntaje global."
    else:
        lectura = (f"El puntaje global de preparación es {r['score_global']} sobre 100 ({r['etiqueta']}). "
                   f"Se detectaron {r['senales_total']} señales: {sv['crítica']} críticas, {sv['alta']} altas, "
                   f"{sv['media']} medias y {sv['baja']} bajas. ")
        if con_info:
            peores = ", ".join(f"{a['nombre']} ({a['score']})" for a in con_info[:3])
            lectura += f"Las áreas que requieren mayor atención son: {peores}. "
        lectura += (f"Además, los agentes identificaron {r['omisiones']} omisiones, {r['preguntas']} preguntas probables "
                    f"del directorio y {r['recomendaciones']} recomendaciones.")
    gcol = {"ok": "#2F6B4F", "leve": "#2F6B4F", "revision": "#A67C00", "serio": "#C2571A", "critico": "#8E1B2E"}.get(r["banda"], NAVY)
    tiles = tiles_pdf([
        (f"{r['score_global']}/100" if r["score_global"] is not None else "-", "Puntaje global", gcol),
        (sv["crítica"], "Señales críticas", COLOR_SEV["crítica"]), (sv["alta"], "Señales altas", COLOR_SEV["alta"]),
        (sv["media"], "Señales medias", COLOR_SEV["media"]), (sv["baja"], "Señales bajas", COLOR_SEV["baja"])])
    cuerpo = seccion(1, "Resumen ejecutivo") + parrafo(lectura) + tiles

    # 2. Semáforo por área
    orden = sorted(d["agentes"], key=lambda a: (a["score"] is None, a["score"] if a["score"] is not None else 999, a["nombre"]))
    filas = []
    for a in orden:
        s_ = a["senales"]
        puntaje = str(a["score"]) if a["score"] is not None and a.get("con_info") else "-"
        nombre = f"<b>{esc_pdf(a['nombre'])}</b>" + (" <span class='small muted'>(transversal)</span>" if a.get("transversal") else "")
        filas.append([nombre, puntaje, esc_pdf(a["etiqueta"]), str(s_["crítica"]), str(s_["alta"]), str(s_["media"]),
                      str(s_["baja"]), str(a["n_omisiones"]), str(a["n_preguntas"])])
    cuerpo += seccion(2, "Estado por área de análisis")
    cuerpo += parrafo("Cada área evalúa un aspecto distinto del documento. Se ordenan de menor a mayor puntaje para ver primero las más delicadas.")
    cuerpo += tabla_pdf(["Área", "Puntaje", "Estado", "Crít.", "Altas", "Medias", "Bajas", "Omis.", "Preg."], filas,
                        ["20%", "9%", "22%", "8%", "8%", "9%", "8%", "8%", "8%"], num_cols=(1, 3, 4, 5, 6, 7, 8))

    # 3. Señales
    orden_sev = {k: i for i, k in enumerate(SEVERIDADES)}
    sens = sorted(d["senales"], key=lambda x: (orden_sev.get(x["severidad"], 9), x.get("transversal", False)))
    cuerpo += seccion(3, f"Señales detectadas ({len(sens)})")
    if sens:
        filas = [[_sev_txt(x["severidad"]), esc_pdf(x["agente_nombre"]) + (" <span class='small muted'>(transv.)</span>" if x.get("transversal") else ""),
                  f"<b>{esc_pdf(x['titulo'])}</b><br/><span class='muted'>{esc_pdf(x.get('descripcion', ''))}</span>"] for x in sens]
        cuerpo += tabla_pdf(["Severidad", "Área", "Señal"], filas, ["12%", "18%", "70%"])
    else:
        cuerpo += parrafo("No se detectaron señales.")

    # 4. Plan de acción
    hechas = 0
    filas = []
    for rec in d["recomendaciones"]:
        a = acciones.get(rec["id"]) or {}
        est = a.get("estado") if a.get("estado") in _ESTADOS_PLAN else "pendiente"
        hechas += est == "hecho"
        filas.append([esc_pdf(rec["agente_nombre"]), esc_pdf(rec["texto"]), esc_pdf(a.get("responsable", "") or "-"),
                      esc_pdf(a.get("fecha", "") or "-"), _ESTADOS_PLAN[est]])
    cuerpo += seccion(4, f"Plan de acción ({hechas} de {len(d['recomendaciones'])} acciones hechas)")
    cuerpo += (tabla_pdf(["Área", "Acción recomendada", "Responsable", "Fecha límite", "Estado"], filas, ["14%", "46%", "16%", "12%", "12%"])
               if filas else parrafo("No hay recomendaciones."))

    # 5. Cómo leer el puntaje
    cuerpo += seccion(5, "Cómo leer el puntaje")
    cuerpo += parrafo("El puntaje de cada área va de 0 a 100 y resume qué tan preparado está el documento en ese aspecto. "
                      "El puntaje global es el promedio de las áreas que encontraron información relevante.")
    cuerpo += tabla_pdf(["Puntaje", "Estado", "Significado"], [[b[0], f"<b>{esc_pdf(b[1])}</b>", esc_pdf(b[2])] for b in _BANDAS_TXT],
                        ["14%", "26%", "60%"])
    meta = [("Documento", doc["nombre"]), ("Fecha de emisión", _fecha_hoy()),
            ("Áreas analizadas", f"{r['agentes_analizados']} de {r['agentes_total']}"), ("Clasificación", "Confidencial")]
    return pagina_pdf("Dashboard de Preparación", "Indicadores para la Gerencia General", cuerpo, meta, "Dashboard de Preparación")


def _delta_txt(x):
    if x is None:
        return "-"
    return "0" if x == 0 else (f"+{x}" if x > 0 else str(x))


def html_pdf_comparacion(c):
    """PDF corporativo de la comparación entre dos documentos (A = anterior, B = actual)."""
    g = c["global"]
    sa, sb_ = c["senales_por_severidad"]["a"], c["senales_por_severidad"]["b"]
    nom_a, nom_b = c["a"]["nombre"], c["b"]["nombre"]
    if g["delta"] is None:
        lectura = "No hay puntaje global comparable entre ambos documentos."
    elif g["delta"] > 0:
        lectura = f"El puntaje global mejoró {g['delta']} puntos, de {g['a']} a {g['b']}."
    elif g["delta"] < 0:
        lectura = f"El puntaje global bajó {abs(g['delta'])} puntos, de {g['a']} a {g['b']}."
    else:
        lectura = f"El puntaje global se mantiene en {g['b']}."
    lectura += (f" Respecto del documento anterior hay {len(c['nuevas'])} señales nuevas, {len(c['resueltas'])} resueltas "
                f"y {len(c['persisten'])} que persisten.")
    dcol = NAVY if g["delta"] in (None, 0) else ("#2F6B4F" if g["delta"] > 0 else "#8E1B2E")
    cuerpo = seccion(1, "Resumen ejecutivo") + parrafo(lectura)
    cuerpo += tiles_pdf([
        (g["a"] if g["a"] is not None else "-", "Puntaje anterior", None),
        (g["b"] if g["b"] is not None else "-", "Puntaje actual", None),
        (_delta_txt(g["delta"]), "Variación", dcol),
        (len(c["nuevas"]), "Señales nuevas", COLOR_SEV["alta"]),
        (len(c["resueltas"]), "Señales resueltas", COLOR_SEV["baja"]),
        (len(c["persisten"]), "Señales que persisten", COLOR_SEV["media"])])

    cuerpo += seccion(2, "Señales por severidad")
    filas = [[_sev_txt(k), str(sa.get(k, 0)), str(sb_.get(k, 0)), _delta_txt(sb_.get(k, 0) - sa.get(k, 0))] for k in SEVERIDADES]
    cuerpo += tabla_pdf(["Severidad", "Anterior", "Actual", "Variación"], filas, ["34%", "22%", "22%", "22%"], num_cols=(1, 2, 3))

    cuerpo += seccion(3, "Variación del puntaje por área")
    filas = []
    for a in sorted(c["agentes"], key=lambda x: (x["delta"] is None, x["delta"] if x["delta"] is not None else 0)):
        dcol_a = "#8E1B2E" if (a["delta"] or 0) < 0 else ("#2F6B4F" if (a["delta"] or 0) > 0 else "#5F6877")
        filas.append([f"<b>{esc_pdf(a['nombre'])}</b>" + (" <span class='small muted'>(transversal)</span>" if a["transversal"] else ""),
                      str(a["score_a"]) if a["score_a"] is not None else "-", str(a["score_b"]) if a["score_b"] is not None else "-",
                      color_texto(_delta_txt(a["delta"]), dcol_a), f"{a['senales_a']} -> {a['senales_b']}"])
    cuerpo += tabla_pdf(["Área", "Anterior", "Actual", "Variación", "Señales"], filas, ["34%", "15%", "15%", "16%", "20%"], num_cols=(1, 2, 3, 4))

    def tabla_senales(lista, vacio, con_ant=False):
        if not lista:
            return parrafo(vacio)
        filas = []
        for x in lista:
            ant = ""
            if con_ant and x.get("severidad_anterior") and x["severidad_anterior"] != x["severidad"]:
                ant = f"<br/><span class='small muted'>Antes: {esc_pdf(x['severidad_anterior'])}</span>"
            filas.append([_sev_txt(x["severidad"]) + ant, esc_pdf(x["agente_nombre"]),
                          f"<b>{esc_pdf(x['titulo'])}</b><br/><span class='muted'>{esc_pdf(x.get('descripcion', ''))}</span>"])
        return tabla_pdf(["Severidad", "Área", "Señal"], filas, ["13%", "18%", "69%"])
    cuerpo += seccion(4, f"Señales nuevas ({len(c['nuevas'])})") + tabla_senales(c["nuevas"], "No aparecieron señales nuevas.")
    cuerpo += seccion(5, f"Señales resueltas ({len(c['resueltas'])})") + tabla_senales(c["resueltas"], "No hay señales resueltas.")
    cuerpo += seccion(6, f"Señales que persisten ({len(c['persisten'])})") + tabla_senales(c["persisten"], "Ninguna señal persiste.", True)
    cuerpo += seccion(7, "Nota metodológica")
    cuerpo += nota_pdf(c.get("nota") or "El emparejamiento de señales entre documentos es aproximado (similitud de títulos).")
    meta = [("Documento anterior", nom_a), ("Documento actual", nom_b), ("Fecha de emisión", _fecha_hoy()), ("Clasificación", "Confidencial")]
    return pagina_pdf("Comparación de Documentos", "Evolución entre dos versiones analizadas", cuerpo, meta, "Comparación de Documentos")


def excel_plan(d, acciones=None):
    """Libro de trabajo del plan de acciÃ³n con identidad visual DIRECTA."""
    import io
    from datetime import datetime
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
    from openpyxl.utils import get_column_letter

    acciones = acciones or {}
    wb = Workbook()
    wb.properties.title = "Plan de acciÃ³n DIRECTA"
    wb.properties.subject = "Informe para Gerencia General y Directorio"
    wb.properties.creator = "DIRECTA | Inteligencia para Directorios"

    navy = "1B2F4B"
    purple = "7161E8"
    cyan = "18B9D2"
    pale = "EAF6FA"
    zebra = "F3F5F8"
    ink = "26354D"
    muted = "66738A"
    line = "C9D0DA"
    white = "FFFFFF"
    doc_name = str((d.get("documento") or {}).get("nombre") or "Documento analizado")
    emitted = datetime.now().strftime("%d/%m/%Y %H:%M")

    def merged_band(ws, row, last_col, text, fill, font, height, align=None):
        ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=last_col)
        cell = ws.cell(row=row, column=1, value=text)
        cell.fill = PatternFill("solid", fgColor=fill)
        cell.font = font
        cell.alignment = align or Alignment(vertical="center", horizontal="left")
        ws.row_dimensions[row].height = height

    def hoja(ws, titulo, seccion, encabezados, filas, anchos):
        last_col = len(encabezados)
        merged_band(ws, 1, last_col, "DIRECTA   /   INTELIGENCIA PARA DIRECTORIOS",
                    navy, Font(name="Calibri", size=11, bold=True, color=white), 30,
                    Alignment(vertical="center", horizontal="left", indent=1))
        merged_band(ws, 2, last_col, titulo,
                    white, Font(name="Times New Roman", size=19, bold=True, color=navy), 36)
        merged_band(ws, 3, last_col, "Informe para Gerencia General Â· PreparaciÃ³n para el Directorio",
                    white, Font(name="Calibri", size=10, color=muted), 22)
        merged_band(ws, 4, last_col, f"DOCUMENTO: {doc_name}     Â·     EMISIÃ“N: {emitted}     Â·     USO INTERNO",
                    "F2F5F9", Font(name="Calibri", size=9, color=ink), 23,
                    Alignment(vertical="center", horizontal="left", indent=1))
        merged_band(ws, 5, last_col, seccion.upper(),
                    purple, Font(name="Calibri", size=9, bold=True, color=white), 23,
                    Alignment(vertical="center", horizontal="left", indent=1))

        header_row = 7
        ws.row_dimensions[6].height = 8
        for j, encabezado in enumerate(encabezados, 1):
            cell = ws.cell(row=header_row, column=j, value=encabezado)
            cell.font = Font(name="Calibri", size=9, bold=True, color=white)
            cell.fill = PatternFill("solid", fgColor=navy)
            cell.alignment = Alignment(vertical="center", horizontal="left", wrap_text=True)
            cell.border = Border(bottom=Side(style="medium", color=cyan))
        ws.row_dimensions[header_row].height = 29

        data_rows = filas or [["Sin registros para este informe"] + [""] * (last_col - 1)]
        for i, fila in enumerate(data_rows, 1):
            max_lines = 1
            for j, value in enumerate(fila, 1):
                cell = ws.cell(row=header_row + i, column=j, value=value)
                cell.font = Font(name="Calibri", size=10, color=ink)
                cell.alignment = Alignment(vertical="top", wrap_text=True)
                cell.border = Border(bottom=Side(style="thin", color=line))
                if i % 2 == 0:
                    cell.fill = PatternFill("solid", fgColor=zebra)
                width = anchos[j - 1] if j - 1 < len(anchos) else 14
                max_lines = max(max_lines, -(-len(str(value if value is not None else "")) // max(1, int(width * 1.15))))
                if str(encabezados[j - 1]).lower() == "estado":
                    normalized = str(value or "").lower()
                    status_colors = {"hecha": "E8F4EC", "en curso": "EAF6FA", "pendiente": "FFF4D6"}
                    if normalized in status_colors:
                        cell.fill = PatternFill("solid", fgColor=status_colors[normalized])
                        cell.font = Font(name="Calibri", size=10, bold=True, color=ink)
            ws.row_dimensions[header_row + i].height = min(120, max(24, 15 * max_lines + 6))

        for j, width in enumerate(anchos, 1):
            ws.column_dimensions[get_column_letter(j)].width = width
        ws.freeze_panes = f"A{header_row + 1}"
        ws.auto_filter.ref = f"A{header_row}:{get_column_letter(last_col)}{header_row + len(data_rows)}"
        ws.sheet_view.showGridLines = False
        ws.sheet_view.zoomScale = 90
        ws.page_setup.orientation = "landscape"
        ws.page_setup.fitToWidth = 1
        ws.page_setup.fitToHeight = 0
        ws.sheet_properties.pageSetUpPr.fitToPage = True
        ws.print_title_rows = f"1:{header_row}"
        ws.print_area = f"A1:{get_column_letter(last_col)}{header_row + len(data_rows)}"
        ws.oddHeader.center.text = "&BDIRECTA  /  INTELIGENCIA PARA DIRECTORIOS&B"
        ws.oddFooter.left.text = doc_name.replace("&", "&&")
        ws.oddFooter.right.text = "PÃ¡gina &P de &N"
        ws.sheet_properties.pageSetUpPr.autoPageBreaks = False

    resumen = d.get("resumen") or {}
    severities = resumen.get("senales") or {}
    recommendations = d.get("recomendaciones", [])
    agents_total = resumen.get("agentes_total", len(d.get("agentes", [])))
    agents_done = resumen.get("agentes_analizados", sum(1 for a in d.get("agentes", []) if a.get("con_info")))
    score_value = resumen.get("score_global")
    high_count = severities.get("crÃ­tica", 0) + severities.get("alta", 0)
    done_count = sum(1 for item in recommendations if (acciones.get(item["id"]) or {}).get("estado") == "hecho")

    # Portada de resumen en Excel: composiciÃ³n inspirada en el informe ejecutivo entregado.
    cover = wb.active
    cover.title = "Resumen ejecutivo"
    cover.sheet_view.showGridLines = False
    cover.sheet_view.zoomScale = 85
    for col in range(1, 11):
        cover.column_dimensions[get_column_letter(col)].width = 15
    merged_band(cover, 1, 10, "DIRECTA   /   INTELIGENCIA PARA DIRECTORIOS",
                navy, Font(name="Calibri", size=12, bold=True, color=white), 34,
                Alignment(vertical="center", horizontal="left", indent=1))
    merged_band(cover, 3, 10, "Informe de preparaciÃ³n para directorio",
                white, Font(name="Times New Roman", size=22, bold=True, color=navy), 42)
    merged_band(cover, 4, 10, f"{doc_name}   Â·   Emitido {emitted}",
                white, Font(name="Calibri", size=10, color=muted), 24)
    merged_band(cover, 6, 10, "INFORME EJECUTIVO   /   MUESTRA DE DISEÃ‘O",
                purple, Font(name="Calibri", size=9, bold=True, color=white), 24,
                Alignment(vertical="center", horizontal="left", indent=1))

    cards = [
        ("ÃNDICE GLOBAL", f"{score_value}/100" if score_value is not None else "â€”", "PreparaciÃ³n general"),
        ("SEÃ‘ALES ALTAS", str(high_count), "CrÃ­ticas y altas"),
        ("ALERTAS TOTALES", str(resumen.get("senales_total", sum(severities.values()))), "Detectadas por agentes"),
        ("ACCIONES", str(len(recommendations)), f"{done_count} completadas"),
        ("AGENTES", f"{agents_done}/{agents_total}", "Con anÃ¡lisis disponible"),
    ]
    for i, (label, value, note) in enumerate(cards):
        start = 1 + i * 2
        end = start + 1
        for row, text, fill, font in (
            (8, label, "F2F5F9", Font(name="Calibri", size=8, bold=True, color=purple)),
            (9, value, white, Font(name="Times New Roman", size=19, bold=True, color=navy)),
            (10, note, white, Font(name="Calibri", size=8, color=muted)),
        ):
            cover.merge_cells(start_row=row, start_column=start, end_row=row, end_column=end)
            c = cover.cell(row=row, column=start, value=text)
            c.fill = PatternFill("solid", fgColor=fill)
            c.font = font
            c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
            for col in range(start, end + 1):
                cover.cell(row=row, column=col).border = Border(bottom=Side(style="thin", color=line))
    cover.row_dimensions[8].height = 23
    cover.row_dimensions[9].height = 37
    cover.row_dimensions[10].height = 25

    merged_band(cover, 12, 10, "LECTURA EJECUTIVA",
                navy, Font(name="Calibri", size=9, bold=True, color=white), 23,
                Alignment(vertical="center", horizontal="left", indent=1))
    reading = (f"El documento {doc_name} fue revisado por {agents_done} de {agents_total} agentes. "
               f"Se detectaron {resumen.get('senales_total', sum(severities.values()))} seÃ±ales, incluidas "
               f"{severities.get('crÃ­tica', 0)} crÃ­ticas y {severities.get('alta', 0)} altas. "
               f"El plan registra {len(recommendations)} acciones y {done_count} completadas.")
    cover.merge_cells(start_row=13, start_column=1, end_row=15, end_column=10)
    c = cover.cell(row=13, column=1, value=reading)
    c.fill = PatternFill("solid", fgColor="F2F5F9")
    c.font = Font(name="Calibri", size=11, color=ink)
    c.alignment = Alignment(vertical="center", wrap_text=True, indent=1)
    cover.row_dimensions[13].height = 30
    cover.row_dimensions[14].height = 26
    cover.row_dimensions[15].height = 26

    merged_band(cover, 17, 10, "ASUNTOS PARA LA SESIÃ“N",
                navy, Font(name="Calibri", size=9, bold=True, color=white), 23,
                Alignment(vertical="center", horizontal="left", indent=1))
    agenda = recommendations[:5]
    for i, item in enumerate(agenda, 18):
        area = str(item.get("agente_nombre") or "Ãrea")
        text = str(item.get("texto") or "")
        cover.merge_cells(start_row=i, start_column=1, end_row=i, end_column=2)
        cover.cell(row=i, column=1, value=area.upper()).font = Font(name="Calibri", size=9, bold=True, color=purple)
        cover.cell(row=i, column=1).fill = PatternFill("solid", fgColor="F2F5F9")
        cover.merge_cells(start_row=i, start_column=3, end_row=i, end_column=10)
        cell = cover.cell(row=i, column=3, value=text)
        cell.font = Font(name="Calibri", size=10, color=ink)
        cell.alignment = Alignment(vertical="center", wrap_text=True)
        cell.border = Border(bottom=Side(style="thin", color=line))
        cover.row_dimensions[i].height = 36
    if not agenda:
        merged_band(cover, 18, 10, "No hay recomendaciones disponibles para este documento.",
                    white, Font(name="Calibri", size=10, color=muted), 30)
    cover.freeze_panes = "A7"
    cover.page_setup.orientation = "landscape"
    cover.page_setup.fitToWidth = 1
    cover.page_setup.fitToHeight = 1
    cover.sheet_properties.pageSetUpPr.fitToPage = True
    cover.print_area = f"A1:J{max(18, 17 + len(agenda))}"
    cover.oddFooter.left.text = doc_name.replace("&", "&&")
    cover.oddFooter.right.text = "PÃ¡gina &P de &N"

    ws = wb.create_sheet("Plan de acciÃ³n")
    ws.title = "Plan de acciÃ³n"
    rows = []
    for item in d.get("recomendaciones", []):
        action = acciones.get(item["id"]) or {}
        status = action.get("estado") if action.get("estado") in _ESTADOS_PLAN else "pendiente"
        rows.append([item["agente_nombre"], item["texto"], action.get("responsable", "") or "",
                     action.get("fecha", "") or "", _ESTADOS_PLAN[status]])
    hoja(ws, "Plan de acciÃ³n", "Informe ejecutivo  /  Seguimiento de recomendaciones",
         ["Ãrea", "AcciÃ³n recomendada", "Responsable", "Fecha lÃ­mite", "Estado"],
         rows, [20, 70, 22, 16, 16])

    ws2 = wb.create_sheet("SeÃ±ales")
    order = {key: i for i, key in enumerate(SEVERIDADES)}
    signals = sorted(d.get("senales", []), key=lambda x: (order.get(x["severidad"], 9), x.get("transversal", False)))
    rows = [[item["severidad"].capitalize(), item["agente_nombre"], item["titulo"], item.get("descripcion", "")]
            for item in signals]
    hoja(ws2, "SeÃ±ales detectadas", "Informe ejecutivo  /  Alertas para revisiÃ³n",
         ["Severidad", "Ãrea", "SeÃ±al", "DescripciÃ³n"], rows, [16, 22, 48, 78])

    ws3 = wb.create_sheet("Estado por Ã¡rea")
    rows = []
    for item in sorted(d.get("agentes", []), key=lambda a: (a["score"] is None, a["score"] if a["score"] is not None else 999, a["nombre"])):
        signals = item["senales"]
        rows.append([item["nombre"], item["score"] if item["con_info"] else None, item["etiqueta"],
                     signals["crÃ­tica"], signals["alta"], signals["media"], signals["baja"],
                     item["n_omisiones"], item["n_preguntas"], item["n_recomendaciones"]])
    hoja(ws3, "Estado por Ã¡rea", "Informe ejecutivo  /  Resumen de anÃ¡lisis",
         ["Ãrea", "Puntaje", "Estado", "CrÃ­ticas", "Altas", "Medias", "Bajas", "Omisiones", "Preguntas", "Recomend."],
         rows, [22, 11, 26, 11, 11, 11, 11, 13, 13, 13])

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()

def crear_router(get_supabase):
    router = APIRouter()
    aqui = os.path.dirname(os.path.abspath(__file__))

    @router.get("/api/dashboard/{document_id}")
    def api_dashboard(document_id: str, refrescar: int = 0):
        try:
            data = dashboard_cacheado(get_supabase(), document_id, bool(refrescar))
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
            data = dashboard_cacheado(get_supabase(), document_id)
            if data is None:
                return JSONResponse({"ok": False, "error": "Documento no encontrado"}, status_code=404)
            pdf = html_a_pdf(html_pdf_dashboard(data, (payload or {}).get("acciones")))
        except Exception as e:
            print(f"[DASHBOARD] Error PDF: {e}", flush=True)
            return JSONResponse({"ok": False, "error": str(e)}, status_code=500)
        nombre = f"Directa_Dashboard_{datetime.now().strftime('%Y-%m-%d')}.pdf"
        return Response(content=pdf, media_type="application/pdf",
                        headers={"Content-Disposition": f'attachment; filename="{nombre}"'})

    @router.post("/api/dashboard-comparar/{id_a}/{id_b}/pdf")
    def api_comparar_pdf(id_a: str, id_b: str):
        try:
            data = comparar_documentos(get_supabase(), id_a, id_b)
            if data is None:
                return JSONResponse({"ok": False, "error": "Documento no encontrado"}, status_code=404)
            pdf = html_a_pdf(html_pdf_comparacion(data))
        except Exception as e:
            print(f"[DASHBOARD] Error PDF comparación: {e}", flush=True)
            return JSONResponse({"ok": False, "error": str(e)}, status_code=500)
        nombre = f"Directa_Comparacion_{datetime.now().strftime('%Y-%m-%d')}.pdf"
        return Response(content=pdf, media_type="application/pdf",
                        headers={"Content-Disposition": f'attachment; filename="{nombre}"'})

    @router.post("/api/dashboard/{document_id}/excel")
    def api_dashboard_excel(document_id: str, payload: dict = Body(default={})):
        try:
            data = dashboard_cacheado(get_supabase(), document_id)
            if data is None:
                return JSONResponse({"ok": False, "error": "Documento no encontrado"}, status_code=404)
            xlsx = excel_plan(data, (payload or {}).get("acciones"))
        except ImportError:
            return JSONResponse({"ok": False, "error": "Falta instalar openpyxl (pip install openpyxl)"}, status_code=500)
        except Exception as e:
            print(f"[DASHBOARD] Error Excel: {e}", flush=True)
            return JSONResponse({"ok": False, "error": str(e)}, status_code=500)
        nombre = f"Directa_Plan_de_Accion_{datetime.now().strftime('%Y-%m-%d')}.xlsx"
        return Response(content=xlsx, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                        headers={"Content-Disposition": f'attachment; filename="{nombre}"'})

    @router.get("/dashboard.html")
    def pagina_dashboard():
        ruta = os.path.join(aqui, "web", "dashboard.html")
        if os.path.exists(ruta):
            return FileResponse(ruta, media_type="text/html")
        return JSONResponse({"ok": False, "error": "dashboard.html no está en la carpeta web/"}, status_code=404)

    return router