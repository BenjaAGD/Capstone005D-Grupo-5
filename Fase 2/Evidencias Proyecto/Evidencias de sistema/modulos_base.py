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
def info_documento(sb, document_id):
    try:
        r = sb.table("documentos").select("*").eq("id", document_id).execute()
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
    r = sb.table("analisis").select("agente, resultado").eq("document_id", document_id).execute()
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
        r = (sb.table("document_chunks").select("id, content, page_number")
             .eq("document_id", document_id).order("id")
             .range(desde, desde + PAGINA_SUPABASE - 1).execute())
        lote = r.data or []
        out.extend(lote)
        if len(lote) < PAGINA_SUPABASE:
            return out
        desde += PAGINA_SUPABASE


def listar_documentos(sb):
    r = (sb.table("documentos").select("id, titulo, nombre_archivo, total_paginas, estado, creado_en")
         .order("creado_en", desc=True).execute())
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
    "\u00a0": " ",
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


CSS_PDF = """
@page { size: A4; margin: 1.6cm 1.5cm 1.8cm 1.5cm; }
body { font-family: Helvetica; font-size: 9pt; color: #1b2430; }
h1 { font-size: 18pt; margin: 0 0 2pt 0; color: #0b1220; }
h2 { font-size: 12pt; margin: 14pt 0 5pt 0; padding-bottom: 3pt; border-bottom: 1.5pt solid #0E7490; color: #0b1220; }
h3 { font-size: 10pt; margin: 9pt 0 3pt 0; color: #0b1220; }
p { margin: 2pt 0 4pt 0; }
.muted { color: #5b6677; }
.small { font-size: 8pt; }
table { width: 100%; border-collapse: collapse; }
th { background-color: #eef2f6; color: #3d4757; font-size: 8pt; text-align: left; padding: 3pt 4pt; border-bottom: 1pt solid #c9d1db; }
td { padding: 3pt 4pt; border-bottom: 0.5pt solid #e1e6ed; vertical-align: top; }
.num { text-align: right; }
.kpi td { text-align: center; border: 0.5pt solid #d7dde6; padding: 5pt 3pt; }
.big { font-size: 20pt; font-weight: bold; }
.crit { color: #c4153c; font-weight: bold; } .alta { color: #b83a3a; font-weight: bold; }
.media { color: #a9611a; font-weight: bold; } .baja { color: #2b8a52; font-weight: bold; }
.pie { margin-top: 14pt; padding-top: 5pt; border-top: 0.5pt solid #c9d1db; font-size: 7.5pt; color: #7a8494; text-align: center; }
"""


def pagina_pdf(titulo, subtitulo, cuerpo):
    return (f"<html><head><meta charset='utf-8'/><style>{CSS_PDF}</style></head><body>"
            f"<h1>{esc_pdf(titulo)}</h1><p class='muted'>{esc_pdf(subtitulo)}</p>{cuerpo}"
            f"<div class='pie'>Documento generado por DIRECTA v2 con los análisis ya guardados (sin IA nueva).</div></body></html>")