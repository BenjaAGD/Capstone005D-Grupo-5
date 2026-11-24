# -*- coding: utf-8 -*-
"""Motor de PDF de DIRECTA (ReportLab).

Reemplaza a xhtml2pdf, que no entiende CSS moderno y dejaba los PDF apretados y feos.
Tiene dos partes:

1. `html_a_pdf_directa(html)`: toma el mismo HTML simple que ya arman Dashboard, Comparación, Indicadores,
   Informe IA y Preparar reunión (tablas .dat, .tile, .nota, .meta, h2, p...) y lo dibuja con el diseño nuevo
   (cabecera, tarjetas de cifras, tablas con cebra, avisos). Así todos los PDF cambian de una vez.
2. `memoria_pdf(ctx, tipo, diseno)`: la Memoria anual con tres portadas (navy editorial, papel claro y
   foto + bandas), apertura de capítulo, índice con páginas, carta, indicadores y cobertura de la norma.

Solo usa tipografías estándar de PDF (Helvetica y Times), así no depende de fuentes del servidor.
"""
import base64
import io
import os
import re
import unicodedata
from datetime import datetime
from html.parser import HTMLParser
from xml.sax.saxutils import escape as _esc

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT, TA_RIGHT, TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas as _rl_canvas
from reportlab.platypus import (BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle,
                                PageBreak, Image, Flowable, KeepTogether, NextPageTemplate, CondPageBreak)
from reportlab.platypus.tableofcontents import TableOfContents

PW, PH = A4
LM = RM = 1.9 * cm
TM = 2.3 * cm
BM = 2.1 * cm
ANCHO = PW - LM - RM

NAVY = colors.HexColor("#1B2F4B")
CYAN = colors.HexColor("#18B9D2")
TEAL = colors.HexColor("#0E7490")
GOLD = colors.HexColor("#C9A24A")
CREMA = colors.HexColor("#FAF8F3")
TINTA = colors.HexColor("#2B2F36")
GRIS = colors.HexColor("#5F6877")
GRIS_CLARO = colors.HexColor("#8A94A6")
LINEA = colors.HexColor("#D9E0E8")
ZEBRA = colors.HexColor("#F3F6F9")
AVISO_BG = colors.HexColor("#EAF6FA")

CLASIFICACION = "Confidencial - uso interno de la Gerencia General y el Directorio"

_REEMPLAZOS = {
    "→": "->", "≥": ">=", "≤": "<=", "…": "...", "▸": ">", "✓": "OK", " ": " ",
    "【": "(", "】": ")", "■": "", "□": "", "•": "•", "·": "·",
    "−": "-", "‑": "-", "​": "", "﻿": "",
}


def _t(s):
    """Texto apto para las fuentes estándar del PDF (Latin-1 / WinAnsi)."""
    s = unicodedata.normalize("NFC", str(s if s is not None else ""))
    for a, b in _REEMPLAZOS.items():
        s = s.replace(a, b)
    return s.encode("cp1252", "replace").decode("cp1252")


def _hex(c, default="#2B2F36"):
    c = str(c or "").strip()
    return c if re.match(r"^#[0-9A-Fa-f]{6}$", c) else default


# ---------------------------------------------------------------------------------------------
# Estilos
# ---------------------------------------------------------------------------------------------
def _ps(name, **kw):
    base = dict(fontName="Helvetica", fontSize=9.2, leading=13, textColor=TINTA, spaceBefore=0, spaceAfter=0)
    base.update(kw)
    return ParagraphStyle(name, **base)


S = {
    "cuerpo": _ps("cuerpo", spaceAfter=6, leading=13.4),
    "titulo": _ps("titulo", fontName="Times-Bold", fontSize=26, leading=29, textColor=NAVY),
    "subtit": _ps("subtit", fontSize=10, leading=14, textColor=GRIS, spaceAfter=2),
    "eyebrow": _ps("eyebrow", fontName="Helvetica-Bold", fontSize=7.4, leading=10, textColor=TEAL, spaceAfter=6),
    "h2": _ps("h2", fontName="Helvetica-Bold", fontSize=12.5, leading=15, textColor=NAVY),
    "h3": _ps("h3", fontName="Times-Bold", fontSize=11, leading=14, textColor=NAVY, spaceBefore=8, spaceAfter=3),
    "celda": _ps("celda", fontSize=8.3, leading=10.6),
    "celda_h": _ps("celda_h", fontName="Helvetica-Bold", fontSize=7.4, leading=9.5, textColor=colors.white),
    "tema": _ps("tema", fontName="Helvetica-Bold", fontSize=7.5, leading=10, textColor=TEAL),
    "preg": _ps("preg", fontName="Helvetica-Bold", fontSize=10.5, leading=13.5, textColor=NAVY, spaceBefore=3, spaceAfter=4),
    "resp": _ps("resp", fontSize=9.2, leading=13.2),
    "verif": _ps("verif", fontSize=8, leading=10.5, spaceBefore=5),
    "pend": _ps("pend", fontSize=8.5, leading=11.5, textColor=colors.HexColor("#8A5A00"), spaceBefore=4),
    "li": _ps("li", leftIndent=12, bulletIndent=2, spaceAfter=2),
    "nota": _ps("nota", fontSize=8.6, leading=12, textColor=colors.HexColor("#273650")),
    "pie": _ps("pie", fontSize=7.2, leading=9, textColor=GRIS),
}


# ---------------------------------------------------------------------------------------------
# Árbol HTML mínimo
# ---------------------------------------------------------------------------------------------
class Nodo:
    __slots__ = ("tag", "attrs", "kids", "padre")

    def __init__(self, tag, attrs=None, padre=None):
        self.tag = tag
        self.attrs = dict(attrs or [])
        self.kids = []
        self.padre = padre

    @property
    def clases(self):
        return set((self.attrs.get("class") or "").split())

    @property
    def estilo(self):
        out = {}
        for parte in (self.attrs.get("style") or "").split(";"):
            if ":" in parte:
                k, v = parte.split(":", 1)
                out[k.strip().lower()] = v.strip()
        return out

    def texto(self):
        if isinstance(self, str):
            return self
        out = []
        for k in self.kids:
            out.append(k if isinstance(k, str) else ("\n" if k.tag == "br" else k.texto()))
        return "".join(out)


_VOID = {"br", "img", "hr", "meta", "link", "input"}
_IGNORAR = {"head", "style", "script", "title"}


class _Parser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.raiz = Nodo("root")
        self.actual = self.raiz
        self._ign = 0

    def handle_starttag(self, tag, attrs):
        if tag in _IGNORAR:
            self._ign += 1
            return
        if self._ign:
            return
        n = Nodo(tag, attrs, self.actual)
        self.actual.kids.append(n)
        if tag not in _VOID and not tag.startswith("pdf:"):
            self.actual = n

    def handle_startendtag(self, tag, attrs):
        if tag in _IGNORAR or self._ign:
            return
        self.actual.kids.append(Nodo(tag, attrs, self.actual))

    def handle_endtag(self, tag):
        if tag in _IGNORAR:
            self._ign = max(0, self._ign - 1)
            return
        if self._ign or tag in _VOID:
            return
        n = self.actual
        while n is not None and n.tag != tag:
            n = n.padre
        if n is not None and n.padre is not None:
            self.actual = n.padre

    def handle_data(self, data):
        if self._ign:
            return
        self.actual.kids.append(data)


def _parse(html):
    p = _Parser()
    p.feed(html)
    p.close()
    return p.raiz


_INLINE = {"b", "strong", "i", "em", "u", "span", "font", "a", "br", "small", "sup", "sub", "code"}


def _es_inline(k):
    return isinstance(k, str) or k.tag in _INLINE


# ---------------------------------------------------------------------------------------------
# Texto en línea (marcado de Paragraph)
# ---------------------------------------------------------------------------------------------
def _inline(kids):
    if isinstance(kids, (str, Nodo)):
        kids = [kids]
    out = []
    for k in kids:
        if isinstance(k, str):
            out.append(_esc(_t(re.sub(r"\s+", " ", k))))
            continue
        tag = k.tag
        if tag == "br":
            out.append("<br/>")
        elif tag in ("b", "strong"):
            out.append("<b>" + _inline(k.kids) + "</b>")
        elif tag in ("i", "em"):
            out.append("<i>" + _inline(k.kids) + "</i>")
        elif tag == "u":
            out.append("<u>" + _inline(k.kids) + "</u>")
        elif tag in ("span", "font", "small", "a", "code", "sub", "sup"):
            est, cl = k.estilo, k.clases
            interior = _inline(k.kids)
            attrs = []
            col = est.get("color")
            if col and re.match(r"^#[0-9A-Fa-f]{6}$", col):
                attrs.append(f'color="{col}"')
            elif "muted" in cl:
                attrs.append('color="#66738A"')
            bg = est.get("background-color")
            if bg and re.match(r"^#[0-9A-Fa-f]{6}$", bg):
                attrs.append(f'backColor="{bg}"')
            if "small" in cl or tag == "small":
                attrs.append('size="7.4"')
            m = re.match(r"^([\d.]+)pt$", est.get("font-size", ""))
            if m:
                attrs.append(f'size="{m.group(1)}"')
            if "big" in cl:
                attrs.append('size="19"')
            if attrs:
                interior = f"<font {' '.join(attrs)}>{interior}</font>"
            if "neg" in cl or "bold" in est.get("font-weight", "") or "big" in cl:
                interior = f"<b>{interior}</b>"
            out.append(interior)
        else:
            # bloque dentro de texto en línea: se separa con salto
            out.append(_inline(k.kids) + "<br/>")
    return "".join(out)


def _para(kids, estilo):
    marca = _inline(kids).strip()
    marca = re.sub(r"^(<br/>)+|(<br/>)+$", "", marca)
    if not re.sub(r"<[^>]+>", "", marca).strip():
        return None
    try:
        return Paragraph(marca, estilo)
    except Exception:  # marcado roto: texto plano
        plano = _esc(_t(re.sub(r"\s+", " ", "".join(k if isinstance(k, str) else k.texto() for k in (
            kids if isinstance(kids, list) else [kids])))))
        return Paragraph(plano, estilo)


# ---------------------------------------------------------------------------------------------
# Flowables propios
# ---------------------------------------------------------------------------------------------
class Seccion(Flowable):
    """Título de sección: texto navy con trazo cian."""

    def __init__(self, texto, ancho=ANCHO):
        super().__init__()
        self.p = Paragraph(_esc(_t(texto)), S["h2"])
        self.ancho = ancho
        self.keepWithNext = 1

    def wrap(self, aw, ah):
        w, h = self.p.wrap(aw, ah)
        self.h_txt = h
        self.width, self.height = aw, h + 16 + 9
        return self.width, self.height

    def draw(self):
        self.p.drawOn(self.canv, 0, 9)
        c = self.canv
        c.setFillColor(CYAN)
        c.rect(0, 3, 26, 2.4, stroke=0, fill=1)
        c.setStrokeColor(LINEA)
        c.setLineWidth(0.6)
        c.line(30, 4.2, self.width, 4.2)

    def split(self, aw, ah):
        return []


class Linea(Flowable):
    def __init__(self, color=LINEA, grosor=0.6, espacio=6):
        super().__init__()
        self.color, self.grosor, self.espacio = color, grosor, espacio

    def wrap(self, aw, ah):
        self.width = aw
        return aw, self.espacio * 2

    def draw(self):
        self.canv.setStrokeColor(self.color)
        self.canv.setLineWidth(self.grosor)
        self.canv.line(0, self.espacio, self.width, self.espacio)


class Marca(Flowable):
    """Flowable invisible que registra una entrada del índice."""

    def __init__(self, texto, nivel=0):
        super().__init__()
        self.texto, self.nivel = texto, nivel

    def wrap(self, aw, ah):
        return 0, 0

    def draw(self):
        pass


def _imagen_b64(src, ancho_max=ANCHO, alto_max=11 * cm):
    m = re.match(r"^data:image/[a-zA-Z+]+;base64,(.+)$", src or "", re.S)
    if not m:
        return None
    try:
        datos = base64.b64decode(re.sub(r"\s+", "", m.group(1)))
        w, h = ImageReader(io.BytesIO(datos)).getSize()
        esc = min(ancho_max / float(w), alto_max / float(h), 1e9)
        return Image(io.BytesIO(datos), width=w * esc, height=h * esc, hAlign="CENTER")
    except Exception:  # noqa: BLE001
        return None


# ---------------------------------------------------------------------------------------------
# Conversión de bloques HTML -> flowables
# ---------------------------------------------------------------------------------------------
def _porcentaje(nodo):
    w = nodo.estilo.get("width") or nodo.attrs.get("width") or ""
    m = re.match(r"^([\d.]+)%$", w.strip())
    return float(m.group(1)) / 100 if m else None


def _filas(tabla):
    """Devuelve [[celda, ...], ...] aplanando tbody/thead."""
    out = []

    def rec(n):
        for k in n.kids:
            if isinstance(k, str):
                continue
            if k.tag == "tr":
                out.append([c for c in k.kids if not isinstance(c, str) and c.tag in ("td", "th")])
            elif k.tag in ("tbody", "thead", "tfoot"):
                rec(k)
    rec(tabla)
    return out


def _tabla_datos(tabla, ancho):
    filas = _filas(tabla)
    if not filas:
        return []
    enc = filas[0] if all(c.tag == "th" for c in filas[0]) else None
    cuerpo = filas[1:] if enc else filas
    ncol = max(len(f) for f in filas)
    fr = [_porcentaje(c) for c in (enc or filas[0])]
    if all(f for f in fr) and len(fr) == ncol:
        tot = sum(fr)
        anchos = [ancho * f / tot for f in fr]
    else:
        anchos = [ancho / ncol] * ncol
    datos, estilo = [], [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LINEBELOW", (0, 0), (-1, -1), 0.5, LINEA),
    ]
    fila_i = 0
    if enc:
        fila_i = 1
        fila = []
        for i, c in enumerate(enc):
            st = ParagraphStyle("h", parent=S["celda_h"], alignment=TA_RIGHT if "num" in c.clases else TA_LEFT)
            fila.append(_para(c.kids, st) or Paragraph("", st))
        fila += [""] * (ncol - len(fila))
        datos.append(fila)
        estilo += [("BACKGROUND", (0, 0), (-1, 0), NAVY), ("LINEBELOW", (0, 0), (-1, 0), 0, NAVY),
                   ("TOPPADDING", (0, 0), (-1, 0), 6), ("BOTTOMPADDING", (0, 0), (-1, 0), 6)]
    for n, f in enumerate(cuerpo):
        fila = []
        for i, c in enumerate(f):
            st = ParagraphStyle("c", parent=S["celda"], alignment=TA_RIGHT if "num" in c.clases else TA_LEFT)
            bloques = _bloques(c.kids, anchos[i] - 12) if any(
                not _es_inline(k) for k in c.kids) else None
            if bloques:
                fila.append(bloques)
            else:
                fila.append(_para(c.kids, st) or Paragraph("", st))
        fila += [""] * (ncol - len(fila))
        datos.append(fila)
        r = n + fila_i
        if n % 2 == 1:
            estilo.append(("BACKGROUND", (0, r), (-1, r), ZEBRA))
    t = Table(datos, colWidths=anchos, repeatRows=1 if enc else 0)
    t.setStyle(TableStyle(estilo))
    return [t, Spacer(1, 8)]


def _tabla_cifras(tabla, ancho):
    celdas = [c for f in _filas(tabla) for c in f]
    items = []
    for c in celdas:
        valor, color, etiqueta = "", None, []
        for k in c.kids:
            if not isinstance(k, str) and "big" in k.clases:
                valor = k.texto().strip()
                color = k.estilo.get("color")
            elif isinstance(k, str):
                if k.strip():
                    etiqueta.append(k.strip())
            elif k.tag != "br":
                etiqueta.append(k.texto().strip())
        items.append((valor, _hex(color, "#1B2F4B"), " ".join(etiqueta)))
    if not items:
        return []
    por_fila = 3 if len(items) in (5, 6) and len(items) != 4 else min(len(items), 4)
    if len(items) == 5:
        por_fila = 5
    out = []
    for i in range(0, len(items), por_fila):
        trozo = items[i:i + por_fila]
        n = len(trozo)
        hueco = 8
        w = (ancho - hueco * (n - 1)) / n
        fila, anchos, est = [], [], [("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0),
                                      ("RIGHTPADDING", (0, 0), (-1, -1), 0), ("TOPPADDING", (0, 0), (-1, -1), 6),
                                      ("BOTTOMPADDING", (0, 0), (-1, -1), 6)]
        for j, (v, col, et) in enumerate(trozo):
            if j:
                fila.append("")
                anchos.append(hueco)
            idx = len(fila)
            vp = Paragraph(_esc(_t(v)), _ps("v", fontName="Times-Bold", fontSize=20, leading=23, textColor=colors.HexColor(col)))
            ep = Paragraph(_esc(_t(et)), _ps("e", fontSize=7.4, leading=9.2, textColor=GRIS))
            fila.append([vp, ep])
            anchos.append(w)
            est.append(("LINEABOVE", (idx, 0), (idx, 0), 2.2, colors.HexColor(col)))
        t = Table([fila], colWidths=anchos)
        t.setStyle(TableStyle(est))
        out += [t, Spacer(1, 6)]
    return out + [Spacer(1, 4)]


def _tabla_aviso(tabla, ancho):
    celdas = [c for f in _filas(tabla) for c in f]
    p = _para(celdas[0].kids, S["nota"]) if celdas else None
    if not p:
        return []
    t = Table([[p]], colWidths=[ancho])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), AVISO_BG), ("LINEBEFORE", (0, 0), (0, -1), 3, CYAN),
                           ("LEFTPADDING", (0, 0), (-1, -1), 11), ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                           ("TOPPADDING", (0, 0), (-1, -1), 8), ("BOTTOMPADDING", (0, 0), (-1, -1), 8)]))
    return [t, Spacer(1, 10)]


def _tabla_meta(tabla, ancho):
    pares = []
    for f in _filas(tabla):
        i = 0
        while i < len(f):
            if "k" in f[i].clases and i + 1 < len(f):
                pares.append((f[i].texto().strip(), f[i + 1].texto().strip()))
                i += 2
            else:
                i += 1
    pares = [(k, v) for k, v in pares if k or v]
    if not pares:
        return []
    filas = []
    for i in range(0, len(pares), 2):
        fila = []
        for k, v in pares[i:i + 2]:
            fila += [Paragraph(_esc(_t(k)), _ps("k", fontName="Helvetica-Bold", fontSize=7.4, leading=9.5, textColor=GRIS)),
                     Paragraph(_esc(_t(v)), _ps("v", fontSize=8.6, leading=11, textColor=TINTA))]
        while len(fila) < 4:
            fila += ["", ""]
        filas.append(fila)
    t = Table(filas, colWidths=[ancho * 0.16, ancho * 0.34, ancho * 0.16, ancho * 0.34])
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#F6F8FB")),
                           ("LINEBELOW", (0, 0), (-1, -1), 0.5, LINEA), ("TOPPADDING", (0, 0), (-1, -1), 6),
                           ("BOTTOMPADDING", (0, 0), (-1, -1), 6), ("LEFTPADDING", (0, 0), (-1, -1), 8),
                           ("RIGHTPADDING", (0, 0), (-1, -1), 8)]))
    return [t, Spacer(1, 12)]


def _tabla_portada(tabla):
    ey = ti = su = ""
    for n in _walk(tabla):
        if isinstance(n, str):
            continue
        cl = n.clases
        if "eyebrow" in cl:
            ey = n.texto().strip()
        elif "tit" in cl:
            ti = n.texto().strip()
        elif "subtit" in cl:
            su = n.texto().strip()
    out = []
    if ey:
        out.append(Paragraph(_esc(_t(ey.replace("|", " / "))), S["eyebrow"]))
    if ti:
        out.append(Paragraph(_esc(_t(ti)), S["titulo"]))
    if su:
        out.append(Spacer(1, 3))
        out.append(Paragraph(_esc(_t(su)), S["subtit"]))
    out += [Spacer(1, 6), Linea(CYAN, 2.2, 3), Spacer(1, 6)]
    return out


def _walk(n):
    for k in n.kids:
        yield k
        if not isinstance(k, str):
            yield from _walk(k)


def _est(nodo, base):
    """Estilo de párrafo con las sobreescrituras en línea del nodo (tamaño, color, negrita, alineación)."""
    est = nodo.estilo
    kw = {}
    m = re.match(r"^([\d.]+)pt$", est.get("font-size", ""))
    if m:
        kw["fontSize"] = float(m.group(1))
        kw["leading"] = float(m.group(1)) * 1.3
    col = est.get("color")
    if col and re.match(r"^#[0-9A-Fa-f]{6}$", col):
        kw["textColor"] = colors.HexColor(col)
    if "bold" in est.get("font-weight", "") and base.fontName == "Helvetica":
        kw["fontName"] = "Helvetica-Bold"
    al = (est.get("text-align") or nodo.attrs.get("align") or "").lower()
    if al == "right":
        kw["alignment"] = TA_RIGHT
    elif al == "center":
        kw["alignment"] = TA_CENTER
    return ParagraphStyle("e", parent=base, **kw) if kw else base


def _color_attr(nodo, clave_attr, clave_css):
    v = nodo.attrs.get(clave_attr) or nodo.estilo.get(clave_css) or ""
    return colors.HexColor(v) if re.match(r"^#[0-9A-Fa-f]{6}$", v.strip()) else None


def _borde_izq(nodo):
    m = re.match(r"^([\d.]+)pt\s+solid\s+(#[0-9A-Fa-f]{6})", nodo.estilo.get("border-left", ""))
    return (float(m.group(1)), colors.HexColor(m.group(2))) if m else None


def _tabla_generica(tabla, ancho):
    """Tablas de maquetación: barras de color, filas de cifras, tarjetas con borde, etc."""
    filas = _filas(tabla)
    if not filas:
        return []
    ncol = max(len(f) for f in filas)
    tarjeta = "pregunta" in tabla.clases
    fr = [_porcentaje(c) for c in filas[0]]
    if len(fr) == ncol and all(fr):
        anchos = [ancho * f / sum(fr) for f in fr]
    elif len(fr) == ncol and any(fr):
        fijo = sum(f for f in fr if f)
        libres = [i for i, f in enumerate(fr) if not f]
        resto = max(0.0, 1 - fijo)
        anchos = [ancho * (f if f else resto / max(1, len(libres))) for f in fr]
    else:
        anchos = [ancho / ncol] * ncol
    es_barra = all(
        c.texto().replace("\xa0", "").strip() == "" and _color_attr(c, "bgcolor", "background-color") is not None
        for f in filas for c in f)
    if es_barra and len(filas) == 1:
        t = Table([[""] * len(filas[0])], colWidths=anchos[:len(filas[0])], rowHeights=[5])
        t.setStyle(TableStyle([("BACKGROUND", (i, 0), (i, 0), _color_attr(c, "bgcolor", "background-color"))
                               for i, c in enumerate(filas[0])] + [("LEFTPADDING", (0, 0), (-1, -1), 0),
                                                                    ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                                                                    ("TOPPADDING", (0, 0), (-1, -1), 0),
                                                                    ("BOTTOMPADDING", (0, 0), (-1, -1), 0)]))
        return [t, Spacer(1, 3)]
    datos, est = [], [("VALIGN", (0, 0), (-1, -1), "TOP")]
    for r, f in enumerate(filas):
        fila = []
        for i, c in enumerate(f):
            if all(_es_inline(k) for k in c.kids):
                p = _para(c.kids, _est(c, S["cuerpo"]))
                fila.append(p or "")
            else:
                fila.append(_bloques(c.kids, anchos[i] - (24 if tarjeta else 12)) or "")
            bg = _color_attr(c, "bgcolor", "background-color")
            if bg is not None:
                est.append(("BACKGROUND", (i, r), (i, r), bg))
            bi = _borde_izq(c)
            if bi:
                est.append(("LINEBEFORE", (i, r), (i, r), bi[0], bi[1]))
        fila += [""] * (ncol - len(fila))
        datos.append(fila)
    if tarjeta:
        est += [("BOX", (0, 0), (-1, -1), 0.75, LINEA), ("BACKGROUND", (0, 0), (-1, -1), colors.white),
                ("LINEBEFORE", (0, 0), (0, -1), 3, CYAN), ("LEFTPADDING", (0, 0), (-1, -1), 12),
                ("RIGHTPADDING", (0, 0), (-1, -1), 12), ("TOPPADDING", (0, 0), (-1, -1), 10),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 10)]
    else:
        est += [("LEFTPADDING", (0, 0), (-1, -1), 6), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]
    t = Table(datos, colWidths=anchos)
    t.setStyle(TableStyle(est))
    return [t, Spacer(1, 10 if tarjeta else 4)]



_CLASE_DIV = {"tema": "tema", "preg": "preg", "respuesta": "resp", "verif": "verif", "pendiente": "pend"}


def _bloques(kids, ancho=ANCHO):
    out, buf = [], []

    def vaciar(estilo=S["cuerpo"]):
        if buf:
            p = _para(list(buf), estilo)
            if p:
                out.append(p)
            buf.clear()

    for k in kids:
        if _es_inline(k):
            buf.append(k)
            continue
        vaciar()
        tag, cl = k.tag, k.clases
        if str(k.attrs.get("id") or "").startswith("pdf_"):
            continue
        if tag == "h1":
            out.append(Paragraph(_inline(k.kids), S["titulo"]))
        elif tag == "h2":
            out += [CondPageBreak(5.5 * cm), Seccion(k.texto().strip(), ancho)]
        elif tag in ("h3", "h4"):
            out.append(Paragraph(_inline(k.kids), _est(k, S["h3"])))
            if "border-bottom" in (k.attrs.get("style") or ""):
                out.append(Linea(LINEA, 0.6, 2))
        elif tag == "p":
            p = _para(k.kids, _est(k, S["cuerpo"]))
            if p:
                out.append(p)
        elif tag in ("ul", "ol"):
            n = 0
            for li in k.kids:
                if isinstance(li, str) or li.tag != "li":
                    continue
                n += 1
                p = _para(li.kids, S["li"])
                if p:
                    p.bulletText = "•" if tag == "ul" else f"{n}."
                    out.append(p)
            out.append(Spacer(1, 4))
        elif tag == "table":
            if "brand" in cl or "cover" in cl:
                continue
            if "portada" in cl:
                out += _tabla_portada(k)
            elif "band" in cl:
                continue
            elif "meta" in cl:
                out += _tabla_meta(k, ancho)
            elif "tile" in cl:
                out += _tabla_cifras(k, ancho)
            elif "nota" in cl:
                out += _tabla_aviso(k, ancho)
            elif "dat" in cl:
                fl = _tabla_datos(k, ancho)
                out += [KeepTogether(fl)] if "keep" in cl else fl
            else:
                out += _tabla_generica(k, ancho)
        elif tag == "img":
            im = _imagen_b64(k.attrs.get("src", ""), ancho)
            if im:
                out += [im, Spacer(1, 8)]
        elif tag == "pdf:nextpage":
            out.append(PageBreak())
        elif tag == "hr":
            out.append(Linea())
        elif tag in ("div", "section", "article", "blockquote", "li", "td", "th", "body", "html", "center"):
            if any(not _es_inline(x) for x in k.kids):
                out += _bloques(k.kids, ancho)
            else:
                clave = next((v for c, v in _CLASE_DIV.items() if c in cl), None)
                st = S[clave] if clave else S["cuerpo"]
                if clave == "verif":
                    col = _hex(k.estilo.get("color"), "#A67C00")
                    st = ParagraphStyle("vv", parent=S["verif"], textColor=colors.HexColor(col))
                p = _para(k.kids, _est(k, st))
                if p:
                    out.append(p)
        else:
            if any(not _es_inline(x) for x in k.kids):
                out += _bloques(k.kids, ancho)
            else:
                p = _para(k.kids, S["cuerpo"])
                if p:
                    out.append(p)
    vaciar()
    return out


# ---------------------------------------------------------------------------------------------
# Lienzo: cabecera y pie con "Página n de N"
# ---------------------------------------------------------------------------------------------
def _canvas_con_pie(cfg):
    class _C(_rl_canvas.Canvas):
        def __init__(self, *a, **k):
            super().__init__(*a, **k)
            self._guardadas = []

        def showPage(self):
            self._guardadas.append(dict(self.__dict__))
            self._startPage()

        def save(self):
            total = len(self._guardadas)
            for estado in self._guardadas:
                self.__dict__.update(estado)
                if not getattr(self, "_sin_pie", False):
                    cfg["pie"](self, self._pageNumber, total)
                _rl_canvas.Canvas.showPage(self)
            _rl_canvas.Canvas.save(self)
    return _C


def _cab_generica(c, doc):
    c._sin_pie = False
    c.saveState()
    c.setFillColor(NAVY)
    c.setFont("Helvetica-Bold", 8)
    c.drawString(LM, PH - 1.25 * cm, "DIRECTA")
    c.setFillColor(GRIS)
    c.setFont("Helvetica", 7.4)
    c.drawString(LM + 40, PH - 1.25 * cm, "/  INTELIGENCIA PARA DIRECTORIOS")
    c.drawRightString(PW - RM, PH - 1.25 * cm, "GERENCIA GENERAL")
    c.setStrokeColor(LINEA)
    c.setLineWidth(0.6)
    c.line(LM, PH - 1.5 * cm, PW - RM, PH - 1.5 * cm)
    c.setFillColor(CYAN)
    c.rect(LM, PH - 1.55 * cm, 34, 1.6, stroke=0, fill=1)
    c.restoreState()


def _pie_generico(c, n, total):
    c.saveState()
    c.setStrokeColor(LINEA)
    c.setLineWidth(0.5)
    c.line(LM, 1.55 * cm, PW - RM, 1.55 * cm)
    c.setFont("Helvetica", 7.2)
    c.setFillColor(GRIS)
    c.drawString(LM, 1.1 * cm, _t(CLASIFICACION))
    c.drawRightString(PW - RM, 1.1 * cm, f"Pagina {n} de {total}".replace("Pagina", "Página"))
    c.restoreState()


def html_a_pdf_directa(html):
    """HTML simple de los generadores de DIRECTA -> bytes de PDF."""
    raiz = _parse(html)
    flow = _bloques(raiz.kids, ANCHO)
    if not flow:
        flow = [Paragraph("Sin contenido.", S["cuerpo"])]
    buf = io.BytesIO()
    doc = BaseDocTemplate(buf, pagesize=A4, leftMargin=LM, rightMargin=RM, topMargin=TM, bottomMargin=BM,
                          title="DIRECTA", author="DIRECTA - Gerencia General")
    marco = Frame(LM, BM, ANCHO, PH - TM - BM, leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    doc.addPageTemplates([PageTemplate(id="n", frames=[marco], onPage=_cab_generica)])
    doc.build(flow, canvasmaker=_canvas_con_pie({"pie": _pie_generico}))
    return buf.getvalue()


# ===============================================================================================
# MEMORIA ANUAL
# ===============================================================================================
TIPOS = {
    "integrada": {
        "nombre": "Memoria integrada (NCG 461)",
        "descripcion": "Completa, con todos los capítulos que pide la norma de la CMF.",
        "kicker": "MEMORIA ANUAL INTEGRADA", "titular": "Un año de gestión responsable",
        "subtitulo": "Resultados, gobierno corporativo y cumplimiento normativo del ejercicio.",
        "capitulos": None, "extras": ["indicadores", "panorama", "cobertura", "revision"], "carta": True, "resumir": 0,
    },
    "ejecutiva": {
        "nombre": "Memoria ejecutiva",
        "descripcion": "Corta: carta, perfil, estrategia, negocio y cifras clave del año.",
        "kicker": "MEMORIA EJECUTIVA", "titular": "Lo esencial del año",
        "subtitulo": "Una lectura breve de los resultados y las decisiones del ejercicio.",
        "capitulos": ["perfil", "estrategia", "negocios", "financieros"], "extras": ["panorama", "indicadores", "revision"],
        "carta": True, "resumir": 650,
    },
    "sostenibilidad": {
        "nombre": "Sostenibilidad y ESG",
        "descripcion": "Personas, proveedores, estrategia climática e indicadores de sostenibilidad.",
        "kicker": "INFORME DE SOSTENIBILIDAD", "titular": "Impacto y sostenibilidad",
        "subtitulo": "Desempeño ambiental, social y de gobernanza del ejercicio.",
        "capitulos": ["estrategia", "personas", "proveedores", "indicadores", "gobierno"],
        "extras": ["indicadores", "panorama", "revision"], "carta": True, "resumir": 0,
    },
    "financiera": {
        "nombre": "Memoria financiera",
        "descripcion": "Resultados, hechos relevantes, negocio e informes financieros.",
        "kicker": "MEMORIA FINANCIERA", "titular": "Resultados del ejercicio",
        "subtitulo": "Desempeño financiero, hechos relevantes y perspectivas.",
        "capitulos": ["financieros", "hechos", "negocios", "estrategia", "comentarios"],
        "extras": ["indicadores", "panorama", "revision"], "carta": True, "resumir": 0,
    },
    "gobierno": {
        "nombre": "Gobierno corporativo y riesgos",
        "descripcion": "Directorio, comités, gestión de riesgos y cumplimiento de la norma.",
        "kicker": "GOBIERNO CORPORATIVO", "titular": "Gobierno y gestión de riesgos",
        "subtitulo": "Cómo se dirige, controla y supervisa la organización.",
        "capitulos": ["perfil", "gobierno", "comentarios", "hechos"], "extras": ["panorama", "cobertura", "revision"],
        "carta": True, "resumir": 0,
    },
    "directorio": {
        "nombre": "Informe para el directorio",
        "descripcion": "Breve, con decisiones pendientes: gobierno, finanzas y hechos relevantes.",
        "kicker": "INFORME PARA EL DIRECTORIO", "titular": "Lo que el directorio debe saber",
        "subtitulo": "Resumen de la gestión y puntos para decisión.",
        "capitulos": ["gobierno", "financieros", "hechos"], "extras": ["panorama", "revision"], "carta": True, "resumir": 650,
    },
}
DISENOS = {
    "navy": {"nombre": "Navy editorial", "descripcion": "Portada azul profundo, tipografía serif, trazo dorado."},
    "claro": {"nombre": "Papel claro", "descripcion": "Fondo crema, título grande y año destacado."},
    "foto": {"nombre": "Foto + bandas", "descripcion": "Foto a sangre arriba, banda cian y bloque de color de marca."},
}


def catalogo():
    return {"tipos": [{"id": k, "nombre": v["nombre"], "descripcion": v["descripcion"], "capitulos": v["capitulos"],
                       "kicker": v["kicker"], "titular": v.get("titular", ""), "subtitulo": v.get("subtitulo", "")} for k, v in TIPOS.items()],
            "disenos": [{"id": k, **v} for k, v in DISENOS.items()]}


def _recortar(texto, limite):
    """Resumen corto: primeros párrafos hasta el límite de caracteres (sin cortar una frase)."""
    texto = str(texto or "").strip()
    if not limite or len(texto) <= limite:
        return texto
    corte = texto[:limite]
    punto = max(corte.rfind(". "), corte.rfind(".\n"))
    return corte[:punto + 1] if punto > limite * 0.5 else corte.rstrip() + "..."


def _marca_texto(texto):
    h = _esc(_t(texto))
    return re.sub(r"\[COMPLETAR:([^\]]*)\]",
                  r'<font color="#7A5200" backColor="#FFF1C2">[COMPLETAR:\1]</font>', h)


def _parrafos_memoria(texto, estilo):
    out = []
    for p in re.split(r"\n\s*\n", str(texto or "").strip()):
        p = " ".join(p.split())
        if p:
            out.append(Paragraph(_marca_texto(p), estilo))
    return out or [Paragraph("<font color='#8A94A6'>Sin texto.</font>", estilo)]


class AperturaCapitulo(Flowable):
    """Cabecera de capítulo a todo el ancho de la página (según el diseño elegido)."""
    ALTO = 5.4 * cm

    def __init__(self, numero, titulo, entrada, diseno, color_marca):
        super().__init__()
        self.numero, self.titulo, self.entrada = numero, titulo, entrada
        self.diseno, self.color = diseno, color_marca

    def wrap(self, aw, ah):
        self.width, self.height = PW, self.ALTO - 0.01
        return self.width, self.height

    def draw(self):
        c = self.canv
        c.saveState()
        c.translate(0, 0)
        claro = self.diseno == "claro"
        fondo = CREMA if claro else (self.color if self.diseno == "foto" else NAVY)
        c.setFillColor(fondo)
        c.rect(0, 0, PW, self.ALTO, stroke=0, fill=1)
        c.setFillColor(GOLD if self.diseno != "foto" else CYAN)
        c.rect(0, 0, PW, 4, stroke=0, fill=1)
        num_col = TEAL if claro else colors.HexColor("#6DD7E8")
        tit_col = NAVY if claro else colors.white
        c.setFillColor(num_col)
        c.setFont("Times-Bold", 74)
        c.drawString(LM, self.ALTO / 2 - 20, f"{int(self.numero):02d}")
        x = LM + 118
        lineas = _partir(_t(self.titulo), "Times-Bold", 25, PW - x - RM)[:3]
        bloque = 18 + 28 * len(lineas)
        y_top = self.ALTO / 2 + bloque / 2
        c.setFont("Helvetica-Bold", 7.5)
        c.drawString(x, y_top - 8, "CAPÍTULO")
        c.setFillColor(tit_col)
        c.setFont("Times-Bold", 25)
        y = y_top - 36
        for ln in lineas:
            c.drawString(x, y, ln)
            y -= 28
        c.restoreState()


def _partir(texto, fuente, tam, ancho):
    from reportlab.pdfbase.pdfmetrics import stringWidth
    out, ln = [], ""
    for w in texto.split():
        prueba = (ln + " " + w).strip()
        if stringWidth(prueba, fuente, tam) <= ancho:
            ln = prueba
        else:
            if ln:
                out.append(ln)
            ln = w
    if ln:
        out.append(ln)
    return out or [""]


def _logo_reader(data_uri):
    m = re.match(r"^data:image/[a-zA-Z+]+;base64,(.+)$", data_uri or "", re.S)
    if not m:
        return None
    try:
        return ImageReader(io.BytesIO(base64.b64decode(re.sub(r"\s+", "", m.group(1)))))
    except Exception:  # noqa: BLE001
        return None


def _dibujar_logo(c, logo, x, y, w_max, h_max, borde=None):
    if not logo:
        return
    iw, ih = logo.getSize()
    esc = min(w_max / float(iw), h_max / float(ih))
    w, h = iw * esc, ih * esc
    if borde is not None:
        c.setFillColor(colors.white)
        c.roundRect(x - 6, y - 6, w + 12, h + 12, 4, stroke=0, fill=1)
    c.drawImage(logo, x, y, w, h, mask="auto")


def _portada(c, ctx, tipo, diseno, foto_path):
    m = ctx["marca"]
    empresa = (m["nombre"] or ctx.get("empresa") or "La empresa").upper()
    color = colors.HexColor(_hex(m["color"], "#1B2F4B"))
    t = TIPOS[tipo]
    titulo = m["titulo"] if m["titulo"] and m["titulo"] != "Memoria anual" else t["titular"]
    anio = str(ctx["anio"])
    destinatario = m.get("destinatario") or "Gerencia General"
    logo = _logo_reader(m.get("logo"))
    c._sin_pie = True
    c.saveState()
    if diseno == "claro":
        c.setFillColor(CREMA)
        c.rect(0, 0, PW, PH, stroke=0, fill=1)
        c.setFillColor(color)
        c.setFont("Helvetica-Bold", 8.5)
        c.drawString(2.4 * cm, PH - 3.2 * cm, empresa)
        _dibujar_logo(c, logo, PW - 2.4 * cm - 2.6 * cm, PH - 4.2 * cm, 2.6 * cm, 1.6 * cm)
        c.setFillColor(TEAL)
        c.setFont("Helvetica-Bold", 8)
        c.drawString(2.4 * cm, PH - 8.4 * cm, t["kicker"])
        c.setFillColor(color)
        y = PH - 10.4 * cm
        for ln in _partir(_t(titulo), "Times-Bold", 46, PW - 4.8 * cm)[:4]:
            c.setFont("Times-Bold", 46)
            c.drawString(2.4 * cm, y, ln)
            y -= 52
        c.setFillColor(GOLD)
        c.rect(2.4 * cm, y - 6, 56, 3, stroke=0, fill=1)
        c.setFillColor(GRIS)
        c.setFont("Helvetica", 11.5)
        yy = y - 34
        for ln in _partir(_t(t["subtitulo"]), "Helvetica", 11.5, 11 * cm)[:3]:
            c.drawString(2.4 * cm, yy, ln)
            yy -= 16
        c.setFillColor(TEAL)
        c.setFont("Times-Bold", 84)
        c.drawString(2.4 * cm, 3.6 * cm, anio)
        c.setFillColor(GRIS)
        c.setFont("Helvetica", 8.6)
        c.drawRightString(PW - 2.4 * cm, 4.9 * cm, "Dirigida a la")
        c.setFillColor(NAVY)
        c.setFont("Helvetica-Bold", 8.6)
        c.drawRightString(PW - 2.4 * cm, 4.5 * cm, _t(destinatario))
        c.setFillColor(GRIS)
        c.setFont("Helvetica", 8.6)
        c.drawRightString(PW - 2.4 * cm, 4.1 * cm, "Preparada con DIRECTA")
    elif diseno == "foto":
        c.setFillColor(colors.white)
        c.rect(0, 0, PW, PH, stroke=0, fill=1)
        alto_foto = PH * 0.50
        if foto_path and os.path.exists(foto_path):
            try:
                c.saveState()
                p = c.beginPath()
                p.rect(0, PH - 1.6 * cm - alto_foto, PW, alto_foto)
                c.clipPath(p, stroke=0, fill=0)
                img = ImageReader(foto_path)
                iw, ih = img.getSize()
                esc = max(PW / float(iw), alto_foto / float(ih))
                c.drawImage(img, (PW - iw * esc) / 2, PH - 1.6 * cm - alto_foto - (ih * esc - alto_foto) / 2,
                            iw * esc, ih * esc)
                c.restoreState()
            except Exception:  # noqa: BLE001
                c.setFillColor(colors.HexColor("#C9D0DA"))
                c.rect(0, PH - 1.6 * cm - alto_foto, PW, alto_foto, stroke=0, fill=1)
        else:
            c.setFillColor(colors.HexColor("#C9D0DA"))
            c.rect(0, PH - 1.6 * cm - alto_foto, PW, alto_foto, stroke=0, fill=1)
        c.setFillColor(color)
        c.setFont("Helvetica-Bold", 8.5)
        c.drawString(2 * cm, PH - 1.0 * cm, empresa)
        c.setFillColor(GRIS)
        c.setFont("Helvetica", 8.5)
        c.drawRightString(PW - 2 * cm, PH - 1.0 * cm, _t(f"Memoria anual {anio}"))
        y_banda = PH - 1.6 * cm - alto_foto
        c.setFillColor(CYAN)
        c.rect(0, y_banda - 8, PW, 8, stroke=0, fill=1)
        c.setFillColor(color)
        c.rect(0, 0, PW, y_banda - 8, stroke=0, fill=1)
        c.setFillColor(colors.HexColor("#8DE4F0"))
        c.setFont("Helvetica-Bold", 8.5)
        c.drawString(2 * cm, y_banda - 2.1 * cm, t["kicker"])
        c.setFillColor(colors.white)
        y = y_banda - 3.9 * cm
        for ln in _partir(_t(titulo), "Times-Bold", 40, PW - 4 * cm)[:3]:
            c.setFont("Times-Bold", 40)
            c.drawString(2 * cm, y, ln)
            y -= 44
        c.setFillColor(colors.HexColor("#6DD7E8"))
        c.setFont("Times-Bold", 38)
        c.drawString(2 * cm, y - 6, anio)
        c.setFillColor(colors.HexColor("#E6EEF7"))
        c.setFont("Helvetica", 10.5)
        yy = 3.6 * cm
        for ln in _partir(_t(t["subtitulo"]), "Helvetica", 10.5, 12 * cm)[:2]:
            c.drawString(2 * cm, yy, ln)
            yy -= 14
        c.setFont("Helvetica", 8.4)
        c.drawString(2 * cm, 1.7 * cm, _t(f"Dirigida a {destinatario}"))
        _dibujar_logo(c, logo, PW - 2 * cm - 2.6 * cm, 1.5 * cm, 2.6 * cm, 1.5 * cm, borde=True)
    else:  # navy editorial
        c.setFillColor(color if _hex(m["color"], "#1B2F4B") != "#1B2F4B" else NAVY)
        c.rect(0, 0, PW, PH, stroke=0, fill=1)
        c.setFillColor(CYAN)
        c.rect(0, PH * 0.34, 10, PH * 0.38, stroke=0, fill=1)
        c.setFillColor(colors.white)
        c.setFont("Helvetica-Bold", 8.5)
        c.drawString(2.4 * cm, PH - 3.2 * cm, empresa)
        _dibujar_logo(c, logo, PW - 2.4 * cm - 2.6 * cm, PH - 4.3 * cm, 2.6 * cm, 1.6 * cm, borde=True)
        c.setFillColor(colors.HexColor("#8DE4F0"))
        c.setFont("Helvetica-Bold", 8.5)
        c.drawString(2.4 * cm, PH - 9.0 * cm, t["kicker"])
        c.setFillColor(colors.white)
        y = PH - 11.2 * cm
        for ln in _partir(_t(titulo), "Times-Bold", 54, PW - 4.8 * cm)[:3]:
            c.setFont("Times-Bold", 54)
            c.drawString(2.4 * cm, y, ln)
            y -= 58
        c.setFillColor(GOLD)
        c.rect(2.4 * cm, y - 4, 56, 3, stroke=0, fill=1)
        c.setFillColor(colors.HexColor("#6DD7E8"))
        c.setFont("Times-Bold", 34)
        c.drawString(2.4 * cm, y - 48, anio)
        c.setFillColor(colors.HexColor("#E6EEF7"))
        c.setFont("Helvetica", 11)
        yy = 5.2 * cm
        for ln in _partir(_t(t["subtitulo"]), "Helvetica", 11, 12 * cm)[:3]:
            c.drawString(2.4 * cm, yy, ln)
            yy -= 15
        c.setFont("Helvetica", 8.6)
        c.setFillColor(colors.HexColor("#B9C6D8"))
        c.drawString(2.4 * cm, 2.6 * cm, _t(f"Dirigida a {destinatario}  |  Preparada con DIRECTA"))
    c.restoreState()


def memoria_pdf(ctx, tipo="integrada", diseno="navy", html_tabla=None):
    """PDF de la Memoria anual. `ctx` es el mismo contexto que arma memoria_pdf.generar().
    `html_tabla(fragmento_html)` convierte los fragmentos con tablas ya existentes."""
    tipo = tipo if tipo in TIPOS else "integrada"
    diseno = diseno if diseno in DISENOS else "navy"
    t = TIPOS[tipo]
    html_tabla = html_tabla or fragmento_a_flowables
    m = ctx["marca"]
    color_hex = _hex(m["color"], "#1B2F4B")
    color = colors.HexColor(color_hex)
    empresa = (m["nombre"] or ctx.get("empresa") or "La empresa")
    anio = ctx["anio"]
    foto = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "memoria_portada_edificio.jpg")
    claro = diseno == "claro"
    titulo_doc = m["titulo"] if m["titulo"] and m["titulo"] != "Memoria anual" else t["nombre"].split(" (")[0]

    def fondo(c):
        if claro:
            c.setFillColor(CREMA)
            c.rect(0, 0, PW, PH, stroke=0, fill=1)

    def on_portada(c, doc):
        _portada(c, ctx, tipo, diseno, foto)

    def cabecera(c, doc):
        c._sin_pie = False
        fondo(c)
        c.saveState()
        c.setFillColor(color)
        c.setFont("Helvetica-Bold", 7.6)
        c.drawString(LM, PH - 1.15 * cm, _t(empresa.upper()))
        c.setFillColor(GRIS)
        c.setFont("Helvetica", 7.6)
        c.drawRightString(PW - RM, PH - 1.15 * cm, _t(f"{titulo_doc} {anio}"))
        c.setStrokeColor(LINEA)
        c.setLineWidth(0.5)
        c.line(LM, PH - 1.4 * cm, PW - RM, PH - 1.4 * cm)
        c.restoreState()

    def cab_capitulo(c, doc):
        c._sin_pie = False
        fondo(c)
        c.saveState()
        c.setFillColor(color)
        c.setFont("Helvetica-Bold", 7.6)
        c.drawString(LM, PH - 0.75 * cm, _t(empresa.upper()))
        c.setFillColor(GRIS)
        c.setFont("Helvetica", 7.6)
        c.drawRightString(PW - RM, PH - 0.75 * cm, _t(f"{titulo_doc} {anio}"))
        c.restoreState()

    def pie(c, n, total):
        c.saveState()
        c.setStrokeColor(LINEA)
        c.setLineWidth(0.5)
        c.line(LM, 1.5 * cm, PW - RM, 1.5 * cm)
        c.setFont("Helvetica", 7.2)
        c.setFillColor(GRIS)
        c.drawString(LM, 1.05 * cm, "Generado con DIRECTA · Gerencia General")
        c.drawRightString(PW - RM, 1.05 * cm, str(n))
        c.restoreState()

    class _Doc(BaseDocTemplate):
        def afterFlowable(self, fl):
            if isinstance(fl, AperturaCapitulo):
                self.notify("TOCEntry", (0, f"{int(fl.numero)}. {fl.titulo}", self.page))
            elif isinstance(fl, Marca):
                self.notify("TOCEntry", (fl.nivel, fl.texto, self.page))

    buf = io.BytesIO()
    doc = _Doc(buf, pagesize=A4, leftMargin=LM, rightMargin=RM, topMargin=TM, bottomMargin=BM,
               title=f"{titulo_doc} {anio}", author=_t(empresa))
    marco_n = Frame(LM, BM, ANCHO, PH - 2.0 * cm - BM, leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0, id="n")
    marco_p = Frame(0, 0, PW, PH, 0, 0, 0, 0, id="p")
    alto_ap = AperturaCapitulo.ALTO
    y_ap = PH - 1.1 * cm - alto_ap
    marco_a1 = Frame(0, y_ap, PW, alto_ap, 0, 0, 0, 0, id="a1")
    marco_a2 = Frame(LM, BM, ANCHO, y_ap - BM - 0.6 * cm, 0, 0, 0, 0, id="a2")
    doc.addPageTemplates([
        PageTemplate(id="portada", frames=[marco_p], onPage=on_portada),
        PageTemplate(id="n", frames=[marco_n], onPage=cabecera),
        PageTemplate(id="cap", frames=[marco_a1, marco_a2], onPage=cab_capitulo),
    ])

    cuerpo = _ps("m_cuerpo", fontSize=10, leading=15, spaceAfter=8)
    lead = _ps("m_lead", fontName="Times-Roman", fontSize=14, leading=20, textColor=NAVY, spaceAfter=10)
    meta = _ps("m_meta", fontSize=7.8, leading=10.5, textColor=GRIS, spaceAfter=8)
    tit_sec = _ps("m_tit", fontName="Times-Bold", fontSize=22, leading=26, textColor=color, spaceAfter=10)

    def conv(fragmento):
        return html_tabla(fragmento) if html_tabla else []

    flow = [Spacer(1, 1), NextPageTemplate("n"), PageBreak()]

    # Índice con páginas
    toc = TableOfContents()
    toc.levelStyles = [
        _ps("toc0", fontSize=10.5, leading=22, textColor=TINTA, leftIndent=0, rightIndent=30),
        _ps("toc1", fontSize=9.5, leading=18, textColor=GRIS, leftIndent=16, rightIndent=30),
    ]
    toc.dotsMinLevel = 0
    flow += [Paragraph("Índice", tit_sec), Linea(GOLD if diseno != "foto" else CYAN, 2, 2), Spacer(1, 6), toc]

    # Carta
    if t["carta"]:
        flow += [PageBreak(), Marca("Carta del Gerente General"), Paragraph("Carta del Gerente General", tit_sec),
                 Linea(GOLD if diseno != "foto" else CYAN, 2, 2), Spacer(1, 8)]
        texto = _recortar(ctx["carta"], t["resumir"] and 1100)
        parrafos = _parrafos_memoria(texto, cuerpo)
        if parrafos:
            flow += _parrafos_memoria(re.split(r"\n\s*\n", texto.strip())[0], lead) + parrafos[1:]

    # Capítulos
    elegidos = [c for c in ctx["capitulos"] if t["capitulos"] is None or c.get("id") in t["capitulos"]]
    cob_por_num = {c["numero"]: c for c in ctx.get("cobertura_capitulos", [])}
    for cap in elegidos:
        if t["resumir"]:  # versión corta: capítulos seguidos, sin página de apertura
            flow += [CondPageBreak(7 * cm), Marca(f"{cap['numero']}. {cap['titulo']}"), Spacer(1, 10),
                     Paragraph(_esc(_t(f"{int(cap['numero']):02d}  {cap['titulo']}")),
                               _ps("m_cap", fontName="Times-Bold", fontSize=18, leading=22, textColor=color)),
                     Linea(GOLD if diseno != "foto" else CYAN, 1.6, 2), Spacer(1, 4)]
        else:
            flow += [NextPageTemplate("cap"), PageBreak(),
                     NextPageTemplate("n"),
                     AperturaCapitulo(cap["numero"], cap["titulo"], cap.get("descripcion", ""), diseno, color),
                     Spacer(1, 4)]
        texto = _recortar(cap["texto"], t["resumir"])
        trozos = re.split(r"\n\s*\n", texto.strip()) if texto.strip() else []
        if trozos:
            flow += _parrafos_memoria(trozos[0], lead)
            for extra in trozos[1:]:
                flow += _parrafos_memoria(extra, cuerpo)
        else:
            flow += _parrafos_memoria("", cuerpo)
        flow.append(Paragraph(_esc(_t(f"{cap.get('descripcion', '')}  ·  Origen del texto: {cap.get('origen', '')}")), meta))
        cob = cob_por_num.get(cap["numero"])
        if cob:
            temas = cob.get("temas", [])
            fuertes = sum(1 for x in temas if x["nivel"] == "fuerte")
            debiles = sum(1 for x in temas if x["nivel"] == "debil")
            ningunas = sum(1 for x in temas if x["nivel"] == "ninguna")
            cel = []
            for val, et, col in ((fuertes, "Temas con evidencia", "#1B2F4B"), (debiles, "Evidencia débil", "#A67C00"),
                                 (ningunas, "Sin evidencia", "#8E1B2E")):
                cel.append([Paragraph(str(val), _ps("v", fontName="Times-Bold", fontSize=24, leading=26,
                                                    textColor=colors.HexColor(col))),
                            Paragraph(_esc(_t(et)), _ps("e", fontSize=7.8, leading=10, textColor=GRIS))])
            tt = Table([cel], colWidths=[ANCHO / 3] * 3)
            tt.setStyle(TableStyle([("LINEABOVE", (0, 0), (-1, 0), 2, color), ("VALIGN", (0, 0), (-1, -1), "TOP"),
                                    ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 14),
                                    ("TOPPADDING", (0, 0), (-1, -1), 8)]))
            flow += [Spacer(1, 6), tt]
        if cap.get("pendientes"):
            filas = [[_esc(_t(p.get("dato", ""))), _esc(_t(p.get("quien", "") or "-"))] for p in cap["pendientes"]]
            fr = ("<table class='dat' width='100%'><tr><th style='width:70%'>Dato pendiente</th><th style='width:30%'>Quién lo aporta</th></tr>"
                  + "".join(f"<tr><td>{a}</td><td>{b}</td></tr>" for a, b in filas) + "</table>")
            flow += [Spacer(1, 8)] + conv(fr)

    def seccion_nueva(titulo):
        return [NextPageTemplate("n"), PageBreak(), Marca(titulo), Paragraph(_esc(_t(titulo)), tit_sec),
                Linea(GOLD if diseno != "foto" else CYAN, 2, 2), Spacer(1, 8)]

    extras = t["extras"]
    if "indicadores" in extras:
        flow += seccion_nueva("Indicadores")
        if ctx.get("graf_indicadores"):
            im = _imagen_b64("data:image/png;base64," + ctx["graf_indicadores"])
            if im:
                flow += [im, Spacer(1, 8)]
        if ctx.get("tabla_indicadores_html"):
            flow += conv(ctx["tabla_indicadores_html"])
        else:
            flow.append(Paragraph("No hay indicadores con valor y meta.", cuerpo))
    if "panorama" in extras:
        flow += seccion_nueva("Panorama del ejercicio")
        if ctx.get("tiles_html"):
            flow += conv(ctx["tiles_html"])
        for k in ("graf_senales", "graf_areas", "graf_evolucion"):
            if ctx.get(k):
                im = _imagen_b64("data:image/png;base64," + ctx[k], alto_max=7.5 * cm)
                if im:
                    flow += [im, Spacer(1, 6)]
        flow.append(Paragraph("Puntajes y señales calculados por DIRECTA a partir del análisis de los agentes sobre los "
                              "documentos del año; no son cifras de los estados financieros.", meta))
    if "cobertura" in extras:
        flow += seccion_nueva("Cobertura de la NCG 461")
        if ctx.get("tabla_cobertura_html"):
            flow += conv(ctx["tabla_cobertura_html"])
    if "revision" in extras:
        flow += seccion_nueva("Revisión de cifras")
        if ctx.get("tabla_revision_html"):
            flow += conv(ctx["tabla_revision_html"])
        else:
            flow.append(Paragraph("Todas las cifras de los textos aparecen en los documentos del año o se recalculan con ellos.", cuerpo))
        flow.append(Paragraph(_esc(_t(
            "La revisión comprueba que cada cifra esté en los documentos del año y marca las que solo aparecen en "
            "documentos de años anteriores. No comprueba que los documentos sean correctos. Documentos del año: "
            + ", ".join(d["nombre"] for d in ctx.get("documentos", [])))), meta))

    doc.multiBuild(flow, canvasmaker=_canvas_con_pie({"pie": pie}))
    return buf.getvalue()


def fragmento_a_flowables(fragmento_html):
    """Convierte un fragmento HTML (tabla, tarjetas, párrafos) en flowables para componer documentos a medida."""
    return _bloques(_parse(fragmento_html).kids, ANCHO)
