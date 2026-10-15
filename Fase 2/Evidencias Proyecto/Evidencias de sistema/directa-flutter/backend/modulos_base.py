# -*- coding: utf-8 -*-
"""
DIRECTA v2 — utilidades comunes de los módulos Dashboard y Memoria Anual.

Estos módulos NO llaman a ninguna IA: solo leen lo que main.py ya guardó en Supabase
(tablas `documentos`, `analisis` y `document_chunks`) y calculan sobre eso.
"""
import io
import re
import html as _html
import hashlib
import unicodedata
from functools import lru_cache

from agentes import AGENTES, obtener_agente

SEVERIDADES = ("crítica", "alta", "media", "baja")
PAGINA_SUPABASE = 1000


def normalizar(texto):
    """Minúsculas y sin tildes."""
    t = unicodedata.normalize("NFD", (texto or "").lower())
    return "".join(ch for ch in t if unicodedata.category(ch) != "Mn")


def norm_sev(valor):
    """Misma regla que main._norm_sev: siempre 'crítica' | 'alta' | 'media' | 'baja'."""
    t = normalizar(str(valor or ""))
    if "|" in t:
        return "media"
    if "crit" in t:
        return "crítica"
    if "alt" in t:
        return "alta"
    if "baj" in t:
        return "baja"
    return "media"


def etiqueta_score(s):
    """Mismas bandas que el PDF del informe."""
    if s >= 90: return "Sin observaciones"
    if s >= 75: return "Menor atención"
    if s >= 55: return "Requiere revisión"
    if s >= 40: return "Observaciones serias"
    return "Observaciones críticas"


def banda_score(s):
    if s >= 90: return "ok"
    if s >= 75: return "leve"
    if s >= 55: return "revision"
    if s >= 40: return "serio"
    return "critico"


def es_integrador(key):
    try:
        return obtener_agente(key).get("tipo") == "integrador"
    except Exception:
        return False


def agentes_analizables():
    """Claves de los agentes que producen análisis (todos menos el chat general), en orden estable:
    primero los productores por ola y al final los integradores."""
    prod = [(a.get("ola", 0), k) for k, a in AGENTES.items() if a["tipo"] == "productor"]
    integ = [(a.get("ola", 0), k) for k, a in AGENTES.items() if a["tipo"] == "integrador"]
    return [k for _, k in sorted(prod)] + [k for _, k in sorted(integ)]


def nombre_agente(key):
    try:
        return obtener_agente(key)["nombre"]
    except Exception:
        return key


def nombre_corto(key):
    """'Agente Riesgos (RSK)' -> 'Riesgos'."""
    n = nombre_agente(key)
    n = re.sub(r"^Agente\s+", "", n)
    n = re.sub(r"\s*\([^)]*\)\s*$", "", n)
    return n.strip() or key


def id_estable(*partes):
    return hashlib.sha1("|".join(str(p) for p in partes).encode("utf-8")).hexdigest()[:12]


def _texto(item, *claves):
    if isinstance(item, dict):
        for c in claves:
            v = item.get(c)
            if v:
                return str(v).strip()
        return ""
    return str(item or "").strip()


def lista_textos(valor, *claves):
    out = []
    for it in (valor or []):
        t = _texto(it, *claves)
        if t:
            out.append(t)
    return out


def tiene_info(resultado):
    """Mismo criterio que el PDF: un agente cuenta si tiene hallazgos o señales."""
    return bool(isinstance(resultado, dict) and (resultado.get("hallazgos") or resultado.get("senales")))


def score_de(resultado):
    try:
        return max(0, min(100, int(round(float((resultado or {}).get("score", 0))))))
    except (TypeError, ValueError):
        return 0


# --------------------------------------------------------------------------- lectura de Supabase
def _con_reintento(fn, intentos=3):
    """Si Supabase corta la conexión ("Server disconnected"), vuelve a intentar sin molestar al usuario."""
    import time
    for n in range(1, intentos + 1):
        try:
            return fn()
        except Exception as e:
            t = (type(e).__name__ + " " + str(e)).lower()
            if n == intentos or not any(x in t for x in ("disconnected", "remoteprotocol", "readerror", "connecterror", "reset", "timeout", "timed out", "closed")):
                raise
            time.sleep(0.6 * n)


def info_documento(sb, document_id):
    try:
        r = _con_reintento(lambda: sb.table("documentos").select("*").eq("id", document_id).execute())
        d = (r.data or [None])[0]
    except Exception:
        d = None
    if not d:
        return None
    return {
        "id": d.get("id"),
        "nombre": d.get("titulo") or d.get("nombre_archivo") or str(document_id),
        "archivo": d.get("nombre_archivo"),
        "paginas": d.get("total_paginas"),
        "estado": d.get("estado"),
        "creado_en": d.get("creado_en"),
    }


def cargar_analisis(sb, document_id):
    """{agente: resultado} de un documento."""
    r = _con_reintento(lambda: sb.table("analisis").select("agente, resultado").eq("document_id", document_id).execute())
    out = {}
    for row in (r.data or []):
        res = row.get("resultado")
        if isinstance(res, dict):
            out[row.get("agente")] = res
    return out


def cargar_chunks(sb, document_id):
    """Todos los fragmentos de un documento (paginado, por si hay más de 1000)."""
    out, desde = [], 0
    while True:
        r = _con_reintento(lambda: (sb.table("document_chunks").select("id, content, page_number")
                                    .eq("document_id", document_id).order("id")
                                    .range(desde, desde + PAGINA_SUPABASE - 1).execute()))
        lote = r.data or []
        out.extend(lote)
        if len(lote) < PAGINA_SUPABASE:
            return out
        desde += PAGINA_SUPABASE


def listar_documentos(sb):
    r = _con_reintento(lambda: (sb.table("documentos").select("id, titulo, nombre_archivo, total_paginas, estado, creado_en")
                                .order("creado_en", desc=True).execute()))
    return r.data or []


# --------------------------------------------------------------------------- señales
def senales_de(key, resultado):
    out = []
    for s in (resultado.get("senales") or []):
        if not isinstance(s, dict):
            continue
        titulo = _texto(s, "titulo")
        if not titulo:
            continue
        out.append({
            "agente": key, "agente_nombre": nombre_corto(key), "transversal": es_integrador(key),
            "titulo": titulo, "descripcion": _texto(s, "descripcion"),
            "severidad": norm_sev(s.get("severidad")),
        })
    return out


@lru_cache(maxsize=4096)
def _tokens(titulo):
    return frozenset(w for w in re.findall(r"[a-z0-9]+", normalizar(titulo)) if len(w) > 3)


def similitud_titulos(a, b):
    ta, tb = _tokens(a), _tokens(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


# ---------------------------------------------------------------------------
# PDF (se genera en el servidor con xhtml2pdf, el mismo que usa el Informe IA)
# ---------------------------------------------------------------------------
_REEMPLAZOS_PDF = {
    "\u2014": "-", "\u2013": "-", "\u00b7": "-", "\u2022": "-", "\u2192": "->", "\u2265": ">=", "\u2264": "<=",
    "\u2026": "...", "\u201c": '"', "\u201d": '"', "\u2018": "'", "\u2019": "'", "\u25b8": ">", "\u2713": "OK",
    "\u00a0": " ", "\u3010": "(", "\u3011": ")", "\u25a0": "", "\u25a1": "",
}


def esc_pdf(texto):
    """Texto seguro para el HTML del PDF: escapa y reemplaza los símbolos que la fuente del PDF no trae."""
    t = str(texto if texto is not None else "")
    for a, b in _REEMPLAZOS_PDF.items():
        t = t.replace(a, b)
    return _html.escape(t, quote=True).replace("\n", "<br/>")


def html_a_pdf(html):
    """Devuelve los bytes del PDF. Lanza RuntimeError si falta xhtml2pdf o falla la conversión."""
    try:
        from xhtml2pdf import pisa
    except Exception as e:  # pragma: no cover
        raise RuntimeError("Falta instalar xhtml2pdf (pip install xhtml2pdf)") from e
    # tildes y ñ como entidades numéricas: así no dependen de la codificación de la fuente
    seguro = html.encode("ascii", "xmlcharrefreplace").decode("ascii")
    buf = io.BytesIO()
    estado = pisa.CreatePDF(src=seguro, dest=buf, encoding="utf-8")
    if estado.err:
        raise RuntimeError("No se pudo generar el PDF")
    return buf.getvalue()


# ---------------------------------------------------------------------------
# Diseño corporativo común de todos los PDF (Dashboard, Comparación, Memoria, Indicadores, Informe)
# ---------------------------------------------------------------------------
NAVY = "#1B2F4B"
GRIS_TXT = "#2B2F36"
GRIS_SUAVE = "#5F6877"
LINEA = "#C9D0DA"
ZEBRA = "#F3F5F8"
COLOR_SEV = {"crítica": "#8E1B2E", "alta": "#C2571A", "media": "#A67C00", "baja": "#2F6B4F"}
COLOR_SEM = {"verde": "#2F6B4F", "amarillo": "#A67C00", "rojo": "#8E1B2E", "sin_dato": "#5F6877"}
CLASIFICACION = "Confidencial - uso interno de la Gerencia General y el Directorio"

CSS_PDF = """
@page { size: A4; margin: 3.1cm 1.9cm 2.5cm 1.9cm;
  @frame cab { -pdf-frame-content: pdf_cab; left: 1.9cm; top: 1.1cm; width: 17.2cm; height: 1.5cm; }
  @frame pie { -pdf-frame-content: pdf_pie; left: 1.9cm; top: 27.6cm; width: 17.2cm; height: 1.3cm; }
}
body { font-family: Helvetica; font-size: 9.5pt; color: #2B2F36; line-height: 1.35; }
h1 { font-size: 20pt; margin: 0; color: #FFFFFF; }
h2 { font-size: 12pt; margin: 14pt 0 5pt 0; padding-bottom: 3pt; color: #1B2F4B; border-bottom: 1pt solid #1B2F4B; }
h3 { font-size: 10pt; margin: 12pt 0 4pt 0; color: #1B2F4B; }
p { margin: 3pt 0 6pt 0; }
.muted { color: #5F6877; }
.small { font-size: 8pt; }
.neg { font-weight: bold; }
.cab { font-size: 8pt; color: #5F6877; border-bottom: 0.75pt solid #1B2F4B; }
.cab b { color: #1B2F4B; letter-spacing: 1pt; }
.pie { font-size: 7.5pt; color: #5F6877; border-top: 0.5pt solid #C9D0DA; padding-top: 3pt; }
.portada td { background-color: #1B2F4B; padding: 7pt 12pt; }
.tit { font-size: 15pt; font-weight: bold; color: #FFFFFF; }
.eyebrow { font-size: 7pt; color: #AFC0D6; letter-spacing: 1.2pt; }
.subtit { font-size: 8.5pt; color: #D7E0EC; }
.meta td { padding: 4pt 6pt; border-bottom: 0.5pt solid #C9D0DA; font-size: 9pt; }
.meta td.k { color: #5F6877; width: 22%; background-color: #F3F5F8; }
table.dat { width: 100%; border-collapse: collapse; margin: 4pt 0 8pt 0; }
table.dat th { background-color: #1B2F4B; color: #FFFFFF; font-size: 8pt; text-align: left; padding: 4pt 5pt; }
table.dat td { padding: 4pt 5pt; border-bottom: 0.5pt solid #C9D0DA; vertical-align: top; font-size: 8.5pt; }
table.dat th.num { text-align: right; }
table.keep { page-break-inside: avoid; }
table.dat td.z { background-color: #F3F5F8; }
.num { text-align: right; }
.ctr { text-align: center; }
.tile td { text-align: center; border: 0.75pt solid #C9D0DA; padding: 7pt 3pt; background-color: #F8F9FB; font-size: 8pt; color: #5F6877; }
.big { font-size: 20pt; font-weight: bold; color: #1B2F4B; }
.nota td { background-color: #F3F5F8; border-left: 3pt solid #1B2F4B; padding: 6pt 9pt; font-size: 8.5pt; color: #2B2F36; }
"""


def _meta_html(meta):
    if not meta:
        return ""
    filas = []
    for k, v in meta:
        filas.append((k, v))
    out = "<table class='meta' width='100%'>"
    for i in range(0, len(filas), 2):
        par = filas[i:i + 2]
        out += "<tr>"
        for k, v in par:
            out += f"<td class='k'>{esc_pdf(k)}</td><td>{esc_pdf(v)}</td>"
        if len(par) == 1:
            out += "<td class='k'></td><td></td>"
        out += "</tr>"
    return out + "</table>"


def pagina_pdf(titulo, subtitulo, cuerpo, meta=None, titulo_corto=None):
    """Documento corporativo: encabezado y pie en todas las páginas, portada con título y ficha del documento."""
    from datetime import datetime
    corto = titulo_corto or titulo
    cab = (f"<div id='pdf_cab'><table width='100%'><tr><td class='cab'><b>DIRECTA</b> &nbsp;|&nbsp; Gerencia General</td>"
           f"<td class='cab' align='right'>{esc_pdf(corto)}</td></tr></table></div>")
    pie = (f"<div id='pdf_pie'><table width='100%'><tr><td class='pie'>{esc_pdf(CLASIFICACION)}</td>"
           f"<td class='pie' align='right'>P&aacute;gina <pdf:pagenumber/> de <pdf:pagecount/></td></tr></table></div>")
    portada = (f"<table class='portada' width='100%'><tr><td><span class='eyebrow'>GERENCIA GENERAL &nbsp;|&nbsp; DIRECTA</span><br/>"
               f"<span class='tit'>{esc_pdf(titulo)}</span><br/><span class='subtit'>{esc_pdf(subtitulo)}</span></td></tr></table><br/>")
    return (f"<html><head><meta charset='utf-8'/><style>{CSS_PDF}</style></head><body>{cab}{pie}{portada}"
            f"{_meta_html(meta)}{cuerpo}</body></html>")


def seccion(numero, titulo):
    return f"<h2>{numero}. {esc_pdf(titulo)}</h2>"


def parrafo(texto):
    return f"<p>{esc_pdf(texto)}</p>"


def nota_pdf(texto):
    return f"<table class='nota' width='100%'><tr><td>{esc_pdf(texto)}</td></tr></table><br/>"


def tiles_pdf(items):
    """items = [(valor, etiqueta, color_hex_o_None)] -> fila de cifras destacadas."""
    celdas = ""
    for valor, etiqueta, color in items:
        estilo = f" style='color:{color}'" if color else ""
        celdas += f"<td><span class='big'{estilo}>{esc_pdf(valor)}</span><br/>{esc_pdf(etiqueta)}</td>"
    return f"<table class='tile' width='100%'><tr>{celdas}</tr></table><br/>"


def tabla_pdf(encabezados, filas, anchos=None, num_cols=()):
    """encabezados: textos. filas: listas de HTML ya seguro (usa esc_pdf al armarlas). num_cols: índices alineados a la derecha."""
    anchos = anchos or [None] * len(encabezados)
    ths = ""
    for i, (h, a) in enumerate(zip(encabezados, anchos)):
        cls = " class='num'" if i in num_cols else ""
        ancho = f" style='width:{a}'" if a else ""
        ths += f"<th{cls}{ancho}>{esc_pdf(h)}</th>"
    trs = ""
    for n, fila in enumerate(filas):
        z = " z" if n % 2 else ""
        celdas = ""
        for i, c in enumerate(fila):
            cls = ("num " if i in num_cols else "") + z.strip()
            celdas += f"<td class='{cls.strip()}'>{c}</td>"
        trs += f"<tr>{celdas}</tr>"
    clase = "dat keep" if len(filas) <= 6 else "dat"
    return f"<table class='{clase}' width='100%'><tr>{ths}</tr>{trs}</table>"


def color_texto(texto, color, negrita=True):
    return f"<span style='color:{color};{'font-weight:bold;' if negrita else ''}'>{esc_pdf(texto)}</span>"