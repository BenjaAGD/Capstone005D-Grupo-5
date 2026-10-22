# -*- coding: utf-8 -*-
"""
DIRECTA - Memoria Anual completa: borrador por capítulos con el tono de las memorias anteriores + PDF con dashboard.

Un clic del gerente:  «Armar memoria»  ->  trabajo en segundo plano que
    1. mide la cobertura de los 11 capítulos de la NCG 461 en los documentos elegidos,
    2. redacta cada capítulo con la voz del perfil de tono aprobado (tono_memoria),
    3. revisa cada borrador con CÓDIGO (cada cifra debe estar en la evidencia; la frase con una cifra sin respaldo se
       reemplaza por [COMPLETAR]) y lo compara con el estilo histórico,
    4. guarda los borradores (el gerente puede editarlos; lo editado no se pisa al volver a armar),
    5. entrega un PDF: portada, dashboard con gráficos, índice, capítulos con marcas [COMPLETAR] y anexo de pendientes.
"""
import re
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

import almacen
import memoria
import memoria_graficos as gr
import tono_memoria
from modulos_base import (
    esc_pdf, pagina_pdf, seccion, parrafo, nota_pdf, tiles_pdf, tabla_pdf, color_texto, COLOR_SEV, NAVY,
)

TABLA = "memoria_borradores"
TRABAJADORES = 3
MARCA = re.compile(r"\[COMPLETAR[^\]]*\]")
REEMPLAZO_CIFRA = "[COMPLETAR: confirmar esta cifra con el área responsable]"

JOBS = {}
_LOCK = threading.Lock()


def clave_de(ids):
    return ",".join(sorted(i for i in (ids or []) if i and i != "__todos__")) or "__todos__"


# ----------------------------------------------------------------------------- revisión de un borrador por código
def _oraciones_con(texto, token):
    partes = re.split(r"(?<=[.!?])\s+", texto)
    return [p for p in partes if token in p]


def revisar_borrador(cap, texto):
    """Verifica por código que cada cifra del borrador salga de la evidencia del capítulo; arregla lo que no.
    Devuelve (texto_final, informe)."""
    import verificador
    frags = [{"content": (t.get("fragmento") or {}).get("texto", ""), "page_number": (t.get("fragmento") or {}).get("pagina")}
             for t in cap.get("temas", []) if (t.get("fragmento") or {}).get("texto")]
    if not texto.strip():
        return texto, {"cifras_revisadas": 0, "cifras_reemplazadas": [], "estado": "vacio"}
    if not frags:
        # sin evidencia: cualquier cifra es inventada
        n = verificador.extraer_numeros(texto)
        cifras = [x["token"] for x in n if not x["anio"]]
        for c in cifras:
            for o in _oraciones_con(texto, c):
                texto = texto.replace(o, REEMPLAZO_CIFRA)
        return texto, {"cifras_revisadas": len(n), "cifras_reemplazadas": cifras, "estado": "sin_evidencia"}
    reemplazadas = []
    for _ in range(3):                       # un reemplazo puede dejar otra cifra al descubierto
        r = verificador.verificar_codigo(texto, frags)
        malas = r["cifras_sin_respaldo"] + r["citas_no_literales"]
        if not malas:
            break
        cambio = False
        for m in malas:
            token = re.sub(r"\s*%$", "", m).strip()
            for o in _oraciones_con(texto, token) or _oraciones_con(texto, m):
                texto = texto.replace(o, REEMPLAZO_CIFRA)
                cambio = True
            reemplazadas.append(m)
        if not cambio:
            break
    r = verificador.verificar_codigo(texto, frags)
    return texto, {"cifras_revisadas": r["cifras_revisadas"], "cifras_reemplazadas": sorted(set(reemplazadas)),
                   "estado": "ok" if r["ok"] else "con_reservas", "paginas_citadas": r["paginas_citadas"]}


# ----------------------------------------------------------------------------- guardado
def guardar_borrador(clave, cap_id, texto, pendientes, informe, etiqueta_tono, estado="generado", tono_comp=None):
    fila = {"llave": f"{clave}|{cap_id}", "clave": clave, "capitulo_id": cap_id, "texto": texto, "pendientes": pendientes,
            "revision": informe, "tono": etiqueta_tono, "estado": estado, "comparacion_tono": tono_comp or {},
            "actualizado_en": datetime.now().isoformat(timespec="seconds")}
    return almacen.tabla(TABLA).guardar_unico("llave", fila)


def borradores_guardados(clave):
    return {f["capitulo_id"]: f for f in almacen.tabla(TABLA).listar(orden=None, clave=clave)}


def editar_borrador(clave, cap_id, texto):
    t = almacen.tabla(TABLA)
    previas = t.listar(orden=None, llave=f"{clave}|{cap_id}")
    if not previas:
        return guardar_borrador(clave, cap_id, texto, [], {}, "editado a mano", estado="editado")
    t.actualizar(previas[0]["id"], {"texto": texto, "estado": "editado",
                                    "actualizado_en": datetime.now().isoformat(timespec="seconds")})
    return {**previas[0], "texto": texto, "estado": "editado"}


# ----------------------------------------------------------------------------- trabajo en segundo plano
def _redactar_capitulo(data, cap, clave, tono_txt, etiqueta, est, forzar, previos):
    prev = previos.get(cap["id"])
    if prev and prev.get("estado") == "editado" and not forzar:
        return {"cap": cap["id"], "estado": "conservado", "texto": prev["texto"]}
    r = memoria.sugerir_borrador(data, cap["id"], clave, tono=tono_txt, etiqueta_tono=etiqueta)
    if not r.get("ok") or not r.get("texto"):
        return {"cap": cap["id"], "estado": "error", "error": r.get("error") or "La IA no devolvió texto."}
    texto, informe = revisar_borrador(cap, r["texto"])
    comp = tono_memoria.comparar_con_historico(texto, est)
    pend = list(r.get("pendientes") or [])
    for m in MARCA.findall(texto):
        if m == REEMPLAZO_CIFRA:
            continue                                   # este lo explica la cifra retirada, más abajo
        d = re.sub(r"^\[COMPLETAR:?\s*|\]$", "", m).strip()
        if d and not any(d.lower() == p["dato"].lower() for p in pend):
            pend.append({"dato": d, "quien": ""})
    for c in informe.get("cifras_reemplazadas") or []:
        pend.append({"dato": f"Confirmar la cifra «{c}»: el borrador la mencionaba pero no está en la evidencia", "quien": ""})
    guardar_borrador(clave, cap["id"], texto, pend, informe, etiqueta, tono_comp=comp)
    return {"cap": cap["id"], "estado": "listo", "texto": texto}


def iniciar_borrador_completo(get_sb, ids=None, capitulos=None, forzar=False):
    """Lanza el trabajo y devuelve su id. Se consulta con estado_trabajo(id)."""
    job_id = uuid.uuid4().hex[:12]
    clave = clave_de(ids)
    job = {"id": job_id, "clave": clave, "estado": "corriendo", "total": 0, "hechos": 0, "errores": [],
           "capitulos": {}, "inicio": time.time(), "fin": None, "mensaje": "Midiendo cobertura de la norma…"}
    with _LOCK:
        JOBS[job_id] = job

    def correr():
        try:
            data = memoria.construir_cobertura_cacheada(get_sb(), [i for i in (ids or []) if i != "__todos__"] or None)
            if not data.get("ok"):
                job.update(estado="error", mensaje=data.get("error", "No hay documentos."), fin=time.time())
                return
            perfil, est, etiqueta = tono_memoria.perfil_para_redactar()
            tono_txt = tono_memoria.instruccion_de_tono(perfil, est)
            caps = [c for c in data["capitulos"] if not capitulos or c["id"] in capitulos]
            job.update(total=len(caps), mensaje="Redactando capítulos con el tono de las memorias anteriores…", tono=etiqueta)
            for c in caps:
                job["capitulos"][c["id"]] = "pendiente"
            previos = borradores_guardados(clave)

            def uno(c):
                job["capitulos"][c["id"]] = "redactando"
                try:
                    r = _redactar_capitulo(data, c, clave, tono_txt, etiqueta, est, forzar, previos)
                except Exception as e:           # un capítulo que falla no tumba a los demás
                    r = {"cap": c["id"], "estado": "error", "error": str(e)[:160]}
                job["capitulos"][c["id"]] = r["estado"]
                if r["estado"] == "error":
                    job["errores"].append({"capitulo": c["id"], "error": r.get("error")})
                job["hechos"] += 1
                return r

            with ThreadPoolExecutor(max_workers=TRABAJADORES) as ex:
                list(ex.map(uno, caps))
            job.update(estado="listo", mensaje="Memoria lista para descargar.", fin=time.time())
        except Exception as e:
            job.update(estado="error", mensaje=f"No se pudo armar la memoria: {str(e)[:200]}", fin=time.time())

    threading.Thread(target=correr, daemon=True, name=f"memoria-{job_id}").start()
    return job_id


def estado_trabajo(job_id):
    j = JOBS.get(job_id)
    if not j:
        return None
    return {k: j.get(k) for k in ("id", "clave", "estado", "total", "hechos", "errores", "capitulos", "mensaje", "tono")} | {
        "segundos": round((j.get("fin") or time.time()) - j["inicio"], 1)}


# ----------------------------------------------------------------------------- PDF completo
def _parrafos_html(texto):
    """Párrafos del borrador; las marcas [COMPLETAR…] salen en rojo para que nadie las deje pasar."""
    out = []
    for par in re.split(r"\n\s*\n", (texto or "").strip()):
        par = par.strip()
        if not par:
            continue
        html, pos = "", 0
        for m in MARCA.finditer(par):
            html += esc_pdf(par[pos:m.start()]) + f"<span style='color:#8E1B2E;font-weight:bold;'>{esc_pdf(m.group(0))}</span>"
            pos = m.end()
        html += esc_pdf(par[pos:])
        out.append(f"<p>{html}</p>")
    return "".join(out) or "<p class='muted small'>(Sin texto todavía.)</p>"


def _img(png, ancho=650):   # xhtml2pdf mide en px (96 por pulgada): 650 px llenan los 17,2 cm útiles
    return f"<img src='{gr.data_uri(png)}' width='{ancho}' /><br/>"


def datos_dashboard(data, borradores):
    """Cifras y series del dashboard (también las usa la pantalla del gerente)."""
    caps = data["capitulos"]
    r = data["resumen"]
    senales, vistas = [], set()
    for c in caps:
        for a in c["agentes"]:
            for s in a["senales"]:
                k = (s.get("agente"), s.get("titulo"))
                if k not in vistas:
                    vistas.add(k)
                    senales.append(s)
    pend_por_cap = []
    n_pend = 0
    for c in caps:
        b = borradores.get(c["id"]) or {}
        n = len(b.get("pendientes") or [])
        n_pend += n
        pend_por_cap.append((f"{c['numero']}. {c['titulo']}", n))
    con_borrador = sum(1 for c in caps if (borradores.get(c["id"]) or {}).get("texto"))
    return {"capitulos": len(caps), "con_borrador": con_borrador, "temas_total": r["temas_total"],
            "temas_con_evidencia": r["fuertes"] + r["debiles"], "evidencia_debil": r["debiles"], "sin_evidencia": r["sin_evidencia"],
            "senales": senales, "pendientes_total": n_pend, "pendientes_por_capitulo": pend_por_cap}


def html_memoria_completa(data, borradores, tono_info=None, empresa=""):
    tono_info = tono_info or {}
    perfil, est, etiqueta = tono_info.get("perfil"), tono_info.get("est") or {}, tono_info.get("etiqueta", "sin perfil")
    d = datos_dashboard(data, borradores)
    caps = data["capitulos"]
    # medidas del borrador completo, para compararlo con las memorias anteriores
    texto_total = "\n\n".join((borradores.get(c["id"]) or {}).get("texto", "") for c in caps)
    medidas = tono_memoria.estadisticas(re.sub(MARCA, "", texto_total)) if texto_total.strip() else None

    cuerpo = seccion(1, "Dashboard de la memoria")
    cuerpo += tiles_pdf([
        (f"{d['con_borrador']}/{d['capitulos']}", "Capítulos con borrador", None),
        (f"{d['temas_con_evidencia']}/{d['temas_total']}", "Temas con evidencia", None),
        (d["pendientes_total"], "Datos por completar", COLOR_SEV["media"] if d["pendientes_total"] else None),
        (d["sin_evidencia"], "Temas sin evidencia", COLOR_SEV["crítica"] if d["sin_evidencia"] else None),
    ])
    cuerpo += "<h3>Cobertura de la norma por capítulo</h3>"
    cuerpo += _img(gr.grafico_cobertura(caps))
    cuerpo += "<h3>Señales de los agentes asociadas a los capítulos</h3>"
    cuerpo += _img(gr.grafico_senales(d["senales"]), 600)
    cuerpo += "<pdf:nextpage />"
    cuerpo += "<h3>Tono: este borrador frente a las memorias anteriores</h3>"
    cuerpo += _img(gr.grafico_tono(est.get("por_memoria") or {}, medidas))
    if est.get("por_memoria"):
        cuerpo += nota_pdf("Las medidas de las memorias anteriores se calcularon por código sobre su texto (no son una opinión de la IA) y son "
                           "aproximadas porque el texto de un PDF trae tablas y columnas. Perfil de tono usado: " + etiqueta + ".")
    else:
        cuerpo += nota_pdf("No hay memorias anteriores medidas: el borrador se redactó sin perfil de tono. Sube las memorias de años anteriores para fijarlo.")
    cuerpo += "<h3>Datos que debe entregar cada área</h3>"
    cuerpo += _img(gr.grafico_pendientes(d["pendientes_por_capitulo"]))

    cuerpo += "<pdf:nextpage />" + seccion(2, "Índice de la memoria")
    cuerpo += tabla_pdf(["N°", "Capítulo", "Estado del borrador", "Por completar"],
                        [[str(c["numero"]), f"<b>{esc_pdf(c['titulo'])}</b>",
                          {"editado": "Editado por el gerente", "generado": "Borrador automático"}.get((borradores.get(c["id"]) or {}).get("estado"), "Sin borrador"),
                          str(len((borradores.get(c["id"]) or {}).get("pendientes") or []))] for c in caps],
                        ["8%", "52%", "26%", "14%"], num_cols=(3,))

    cuerpo += "<pdf:nextpage />" + seccion(3, "Capítulos")
    for c in caps:
        b = borradores.get(c["id"]) or {}
        cuerpo += f"<h3>Capítulo {c['numero']}. {esc_pdf(c['titulo'])}</h3>"
        cuerpo += f"<p class='small muted'>{esc_pdf(c['descripcion'])}</p>"
        cuerpo += _parrafos_html(b.get("texto"))
        rev = b.get("revision") or {}
        if rev.get("cifras_reemplazadas") and b.get("estado") != "editado":
            cuerpo += (f"<p class='small muted'>Revisión por código: se retiró o marcó {len(rev['cifras_reemplazadas'])} cifra(s) que no estaban "
                       "en la evidencia del documento.</p>")
        filas = []
        for t in c["temas"]:
            pg = ", ".join(f"pág. {p['pagina'] if p['pagina'] is not None else '?'}" for p in t["paginas"][:4])
            ev = {"fuerte": color_texto("Con evidencia", "#2F6B4F"), "debil": color_texto("Débil", "#A67C00"),
                  "ninguna": color_texto("Sin evidencia", "#8E1B2E")}.get(t["nivel"], "")
            filas.append([esc_pdf(t["nombre"]), ev, esc_pdf(pg) or "-"])
        cuerpo += tabla_pdf(["Tema que pide la norma", "Evidencia", "Dónde mirar"], filas, ["54%", "20%", "26%"])

    cuerpo += "<pdf:nextpage />" + seccion(4, "Anexo: datos pendientes por completar")
    filas = []
    for c in caps:
        for p in (borradores.get(c["id"]) or {}).get("pendientes") or []:
            filas.append([str(c["numero"]), esc_pdf(p.get("dato", "")), esc_pdf(p.get("quien") or "por definir")])
    cuerpo += (tabla_pdf(["Cap.", "Dato que falta", "Área que lo entrega"], filas, ["8%", "62%", "30%"]) if filas
               else "<p class='muted small'>No hay datos pendientes registrados.</p>")

    cuerpo += seccion(5, "Alcance y limitaciones")
    cuerpo += nota_pdf("Este documento es un BORRADOR para el equipo que redacta la memoria. Cada capítulo se escribió solo con los fragmentos "
                       "de los documentos revisados; las cifras fueron comprobadas por código contra esa evidencia y las marcas [COMPLETAR] indican lo "
                       "que falta. " + data.get("aviso", "") + " " + data.get("referencia", ""))
    meta = [("Documentos revisados", ", ".join(f["nombre"] for f in data["fuentes"])[:300]),
            ("Fecha de emisión", datetime.now().strftime("%d/%m/%Y %H:%M")),
            ("Perfil de tono", etiqueta), ("Norma de referencia", "NCG 461 (CMF)")]
    return pagina_pdf(f"Memoria Anual{(' - ' + empresa) if empresa else ''}: borrador con dashboard",
                      "Redactada con el tono de las memorias anteriores", cuerpo, meta, "Memoria Anual (borrador)")
