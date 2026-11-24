"""Reportes con el mismo lenguaje visual de la Memoria (portada a página completa, capítulos con
número grande, cifras en serif, tarjetas con barra de color). Lo usan Dashboard, Comparación,
Indicadores, Informe del directorio y Preparar reunión.

Uso: `reporte_pdf(portada, capitulos)` donde cada capítulo es (titulo, entrada, [bloques]) y cada
bloque se arma con las funciones `parrafo`, `cifras`, `barras`, `tarjetas`, `tabla`, `nota`."""
import io
from datetime import datetime

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.platypus import (BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle,
                                NextPageTemplate, PageBreak, Flowable, KeepTogether, CondPageBreak)

import pdf_directa as P

PW, PH = A4
LM = RM = 1.9 * cm
ANCHO = PW - LM - RM
NAVY, CYAN, TEAL, GOLD, GRIS, TINTA, LINEA = P.NAVY, P.CYAN, P.TEAL, P.GOLD, P.GRIS, P.TINTA, P.LINEA
_ps = P._ps
_t = P._t

import os

# Paletas para portada y capítulos: (nombre, fondo, acento/número, título, línea, texto suave)
PALETAS = {
    "cafe": ("Papel café", "#F6F1E7", "#8A5A2B", "#3B2A1A", "#C9A24A", "#7A6A58"),
    "crema": ("Crema y azul", "#FAF8F3", "#0E7490", "#1B2F4B", "#C9A24A", "#5F6877"),
    "arena": ("Arena y verde", "#F4F1EA", "#2F6B4F", "#22352B", "#B8955A", "#6B7068"),
    "perla": ("Perla y vino", "#F7F4F2", "#8E1B2E", "#3A1F25", "#C9A24A", "#77686B"),
    "hielo": ("Hielo y marino", "#EEF4F9", "#0E4F6B", "#0B1F33", "#18B9D2", "#5F6877"),
    "lavanda": ("Lavanda", "#F3F2F8", "#5B4B9A", "#24203F", "#C9A24A", "#6E6A80"),
    "grafito": ("Grafito", "#F2F2F0", "#2B2B2B", "#111111", "#D9A441", "#6B6B6B"),
    "terracota": ("Terracota", "#FBF3EE", "#B5532D", "#3D2218", "#D9A441", "#7E6559"),
}
PALETA = os.getenv("REPORTES_PALETA", "cafe")


def _pal(nombre=None):
    k = nombre or PALETA
    _, fondo, acento, titulo, linea, suave = PALETAS.get(k, PALETAS["cafe"])
    return {k2: colors.HexColor(v) for k2, v in (("fondo", fondo), ("acento", acento), ("titulo", titulo), ("linea", linea), ("suave", suave))}


def _e(x):
    return P._esc(_t(str(x if x is not None else "")))

SEV = {"crítica": ("#8E1B2E", "#F6DDE2"), "critica": ("#8E1B2E", "#F6DDE2"), "alta": ("#C2571A", "#FCE9DF"),
       "media": ("#A67C00", "#FBF2DC"), "baja": ("#2F6B4F", "#E3F1E9")}
BANDA = [(90, "#2F6B4F", "Sin observaciones"), (75, "#2F6B4F", "Menor atención"), (55, "#A67C00", "Requiere revisión"),
         (40, "#C2571A", "Observaciones serias"), (0, "#8E1B2E", "Observaciones críticas")]


def color_puntaje(p):
    if p is None:
        return "#8A94A6", "Sin dato"
    for lim, col, txt in BANDA:
        if p >= lim:
            return col, txt
    return BANDA[-1][1], BANDA[-1][2]


ST = {
    "lead": _ps("r_lead", fontName="Times-Roman", fontSize=12.5, leading=18, textColor=NAVY, spaceAfter=10),
    "cuerpo": _ps("r_cuerpo", fontName="Times-Roman", fontSize=11, leading=16, textColor=TINTA, spaceAfter=7),
    "h": _ps("r_h", fontName="Times-Bold", fontSize=14, leading=18, textColor=NAVY, spaceBefore=12, spaceAfter=6),
    "eti": _ps("r_eti", fontName="Helvetica-Bold", fontSize=7.4, leading=9.5, textColor=GRIS),
    "tit": _ps("r_tit", fontName="Times-Bold", fontSize=12.5, leading=16, textColor=NAVY, spaceAfter=2),
    "txt": _ps("r_txt", fontSize=10, leading=14, textColor=colors.HexColor("#3A4250")),
    "pie": _ps("r_pie", fontSize=8.2, leading=11, textColor=GRIS, spaceBefore=3),
    "celda": _ps("r_celda", fontSize=9.6, leading=13, textColor=TINTA),
    "celda_b": _ps("r_celda_b", fontName="Helvetica-Bold", fontSize=9, leading=12, textColor=NAVY),
    "th": _ps("r_th", fontName="Helvetica-Bold", fontSize=7.4, leading=9.5, textColor=GRIS),
}


# ----------------------------------------------------------------------------------- bloques
def parrafo(texto, lead=False):
    out = []
    for i, p in enumerate([x for x in str(texto or "").split("\n\n") if x.strip()]):
        out.append(Paragraph(P._marca_texto(" ".join(p.split())).replace("**", ""), ST["lead"] if lead and i == 0 else ST["cuerpo"]))
    return out


def subtitulo(texto):
    return [CondPageBreak(4 * cm), Paragraph(_e(texto), ST["h"])]


def cifras(items):
    """items: [(valor, etiqueta, color_hex)] → fila de cifras grandes en serif con línea superior de color."""
    cel = []
    for val, et, col in items:
        cel.append([Paragraph(_e(val), _ps("v", fontName="Times-Bold", fontSize=26, leading=28, textColor=colors.HexColor(col))),
                    Paragraph(_e(et).upper(), _ps("e", fontName="Helvetica-Bold", fontSize=6.8, leading=9, textColor=GRIS))])
    t = Table([cel], colWidths=[ANCHO / len(items)] * len(items))
    estilo = [("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 10),
              ("TOPPADDING", (0, 0), (-1, -1), 8), ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]
    for i, (_, _, col) in enumerate(items):
        estilo.append(("LINEABOVE", (i, 0), (i, 0), 2, colors.HexColor(col)))
    t.setStyle(TableStyle(estilo))
    return [Spacer(1, 4), t, Spacer(1, 10)]


class _Barra(Flowable):
    def __init__(self, valor, color, ancho, alto=5):
        super().__init__()
        self.valor, self.color, self.w, self.h = valor, color, ancho, alto

    def wrap(self, aw, ah):
        return self.w, self.h + 4

    def draw(self):
        c = self.canv
        c.setFillColor(colors.HexColor("#E6EAF0"))
        c.roundRect(0, 2, self.w, self.h, self.h / 2, stroke=0, fill=1)
        if self.valor:
            c.setFillColor(colors.HexColor(self.color))
            c.roundRect(0, 2, max(self.h, self.w * min(self.valor, 100) / 100.0), self.h, self.h / 2, stroke=0, fill=1)


def barras(filas):
    """filas: [(nombre, puntaje|None, detalle)] → barras por área con su estado."""
    datos = []
    for nombre, p, det in filas:
        col, txt = color_puntaje(p)
        datos.append([Paragraph(f"<b>{_e(nombre)}</b>" + (f"<br/><font size='7.4' color='#8A94A6'>{_e(det)}</font>" if det else ""), ST["celda"]),
                      _Barra(p, col, ANCHO * 0.42),
                      Paragraph(f"<font name='Times-Bold' size='13' color='{col}'>{'-' if p is None else p}</font>", ST["celda"]),
                      Paragraph(f"<font color='{col}'><b>{_e(txt).upper()}</b></font>", _ps("ch", fontSize=6.8, leading=9))])
    t = Table(datos, colWidths=[ANCHO * 0.27, ANCHO * 0.45, ANCHO * 0.08, ANCHO * 0.2])
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("LINEBELOW", (0, 0), (-1, -1), 0.5, LINEA),
                           ("LEFTPADDING", (0, 0), (-1, -1), 0), ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]))
    return [t, Spacer(1, 8)]


def tarjetas(items):
    """items: dicts con sev (o color), etiqueta, titulo, texto, pie → tarjetas con barra lateral de color."""
    out = []
    for it in items:
        col, fondo = SEV.get(str(it.get("sev", "")).lower(), (it.get("color", "#1B2F4B"), "#F3F6FA"))
        cab = f"<font color='{col}'><b>{_e(it.get('etiqueta') or it.get('sev', '')).upper()}</b></font>"
        if it.get("area"):
            cab += f"<font color='#8A94A6'>  ·  {_e(it['area'])}</font>"
        cont = [Paragraph(cab, _ps("cab", fontSize=7.4, leading=10, spaceAfter=3)), Paragraph(_e(it.get("titulo")), ST["tit"])]
        if it.get("texto"):
            cont.append(Paragraph(P._marca_texto(str(it["texto"])).replace("**", ""), ST["txt"]))
        if it.get("pie"):
            cont.append(Paragraph(_e(it["pie"]), ST["pie"]))
        t = Table([["", cont]], colWidths=[4, ANCHO - 4])
        t.setStyle(TableStyle([("BACKGROUND", (0, 0), (0, 0), colors.HexColor(col)), ("BACKGROUND", (1, 0), (1, 0), colors.HexColor("#FAFBFD")),
                               ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#E3E8EF")),
                               ("LEFTPADDING", (1, 0), (1, 0), 12), ("RIGHTPADDING", (1, 0), (1, 0), 12),
                               ("TOPPADDING", (1, 0), (1, 0), 9), ("BOTTOMPADDING", (1, 0), (1, 0), 10),
                               ("LEFTPADDING", (0, 0), (0, 0), 0), ("RIGHTPADDING", (0, 0), (0, 0), 0)]))
        out += [KeepTogether([t]), Spacer(1, 7)]
    return out


def tabla(encabezados, filas, anchos):
    data = [[Paragraph(_e(h).upper(), ST["th"]) for h in encabezados]]
    for f in filas:
        data.append([x if isinstance(x, Flowable) else Paragraph(str(x), ST["celda"]) for x in f])
    t = Table(data, colWidths=[ANCHO * a for a in anchos], repeatRows=1)
    t.setStyle(TableStyle([("LINEBELOW", (0, 0), (-1, 0), 1.4, NAVY), ("LINEBELOW", (0, 1), (-1, -1), 0.5, LINEA),
                           ("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 3),
                           ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6)]))
    return [t, Spacer(1, 8)]


def chip(texto, sev=None, color=None):
    col, fondo = SEV.get(str(sev or "").lower(), (color or "#1B2F4B", "#EEF2F7"))
    t = Table([[Paragraph(f"<font color='{col}'><b>{_e(texto).upper()}</b></font>", _ps("chip", fontSize=6.8, leading=8.5))]])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), colors.HexColor(fondo)), ("LEFTPADDING", (0, 0), (-1, -1), 5),
                           ("RIGHTPADDING", (0, 0), (-1, -1), 5), ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]))
    t.hAlign = "LEFT"
    return t


def nota(texto):
    t = Table([[Paragraph(_e(texto), _ps("nota", fontSize=8.8, leading=12.5, textColor=colors.HexColor("#273650")))]], colWidths=[ANCHO])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#EEF4F9")), ("LINEBEFORE", (0, 0), (0, -1), 3, CYAN),
                           ("LEFTPADDING", (0, 0), (-1, -1), 10), ("TOPPADDING", (0, 0), (-1, -1), 8), ("BOTTOMPADDING", (0, 0), (-1, -1), 8)]))
    return [t, Spacer(1, 8)]


# ----------------------------------------------------------------------------------- documento
class _Apertura(Flowable):
    ALTO = 3.4 * cm

    def __init__(self, numero, titulo, entrada="", paleta=None):
        super().__init__()
        self.numero, self.titulo, self.entrada, self.pal = numero, titulo, entrada, _pal(paleta)

    def wrap(self, aw, ah):
        return PW, self.ALTO

    def draw(self):
        c, pal = self.canv, self.pal
        c.saveState()
        c.setFillColor(pal["fondo"])
        c.rect(-LM, 0, PW, self.ALTO, stroke=0, fill=1)
        c.setFillColor(pal["linea"])
        c.rect(-LM, 0, PW, 2.5, stroke=0, fill=1)
        c.setFillColor(pal["acento"])
        c.setFont("Times-Bold", 52)
        c.drawString(0, self.ALTO / 2 - 16, f"{int(self.numero):02d}")
        c.setFont("Helvetica-Bold", 7)
        c.drawString(86, self.ALTO / 2 + 14, "SECCIÓN")
        c.setFillColor(pal["titulo"])
        c.setFont("Times-Bold", 21)
        c.drawString(86, self.ALTO / 2 - 8, _t(self.titulo)[:52])
        if self.entrada:
            c.setFillColor(pal["suave"])
            c.setFont("Helvetica", 8.4)
            c.drawString(86, self.ALTO / 2 - 24, _t(self.entrada)[:110])
        c.restoreState()


def _portada(c, p, paleta=None):
    """Portada estilo "Papel claro" de la Memoria (la favorita), con la paleta elegida."""
    pal = _pal(paleta)
    c.saveState()
    c.setFillColor(pal["fondo"])
    c.rect(0, 0, PW, PH, stroke=0, fill=1)
    c.setFillColor(pal["titulo"])
    c.setFont("Helvetica-Bold", 8.5)
    c.drawString(2.4 * cm, PH - 3.0 * cm, "DIRECTA  ·  GERENCIA GENERAL")
    c.setFillColor(pal["suave"])
    c.setFont("Helvetica", 8.5)
    c.drawRightString(PW - 2.4 * cm, PH - 3.0 * cm, _t(p.get("fecha") or datetime.now().strftime("%d/%m/%Y")))
    c.setFillColor(pal["acento"])
    c.setFont("Helvetica-Bold", 8.5)
    c.drawString(2.4 * cm, PH - 8.6 * cm, _t(p.get("kicker", "")).upper())
    c.setFillColor(pal["titulo"])
    y = PH - 10.6 * cm
    for ln in P._partir(_t(p.get("titulo", "")), "Times-Bold", 44, PW - 4.8 * cm)[:3]:
        c.setFont("Times-Bold", 44)
        c.drawString(2.4 * cm, y, ln)
        y -= 50
    c.setFillColor(pal["linea"])
    c.rect(2.4 * cm, y - 2, 56, 3, stroke=0, fill=1)
    c.setFillColor(pal["suave"])
    c.setFont("Helvetica", 11)
    yy = y - 30
    for ln in P._partir(_t(p.get("subtitulo", "")), "Helvetica", 11, PW - 4.8 * cm)[:3]:
        c.drawString(2.4 * cm, yy, ln)
        yy -= 15
    if p.get("cifra"):
        valor, etiqueta = p["cifra"]
        c.setFillColor(pal["acento"])
        c.setFont("Times-Bold", 72)
        c.drawString(2.4 * cm, 4.6 * cm, _t(valor))
        c.setFillColor(pal["suave"])
        c.setFont("Helvetica-Bold", 8)
        c.drawString(2.4 * cm, 3.9 * cm, _t(etiqueta).upper())
    c.setStrokeColor(pal["linea"])
    c.setLineWidth(0.6)
    c.line(2.4 * cm, 3.0 * cm, PW - 2.4 * cm, 3.0 * cm)
    c.setFillColor(pal["suave"])
    c.setFont("Helvetica", 8.2)
    c.drawString(2.4 * cm, 2.4 * cm, _t(f"Documento: {p.get('documento', '')}")[:95])
    c.drawRightString(PW - 2.4 * cm, 2.4 * cm, "Confidencial")
    c.restoreState()


def reporte_pdf(portada, capitulos, titulo_corto="", paleta=None):
    """portada: {kicker, titulo, subtitulo, documento, fecha, cifra:(valor, etiqueta)}
    capitulos: [(titulo, entrada, [flowables])]"""
    buf = io.BytesIO()
    corto = titulo_corto or portada.get("titulo", "")

    def on_portada(c, doc):
        c._sin_pie = True
        _portada(c, portada, paleta)

    def cabecera(c, doc):
        c._sin_pie = False
        c.saveState()
        c.setFillColor(NAVY)
        c.setFont("Helvetica-Bold", 7.6)
        c.drawString(LM, PH - 1.1 * cm, "DIRECTA")
        c.setFillColor(GRIS)
        c.setFont("Helvetica", 7.6)
        c.drawString(LM + 40, PH - 1.1 * cm, "·  Gerencia General")
        c.drawRightString(PW - RM, PH - 1.1 * cm, _t(corto))
        c.restoreState()

    def pie(c, n, total):
        c.saveState()
        c.setStrokeColor(LINEA)
        c.setLineWidth(0.5)
        c.line(LM, 1.5 * cm, PW - RM, 1.5 * cm)
        c.setFont("Helvetica", 7.2)
        c.setFillColor(GRIS)
        c.drawString(LM, 1.05 * cm, "Confidencial · uso interno de la Gerencia General y el Directorio")
        c.drawRightString(PW - RM, 1.05 * cm, f"{n}")
        c.restoreState()

    doc = BaseDocTemplate(buf, pagesize=A4, leftMargin=LM, rightMargin=RM, topMargin=1.8 * cm, bottomMargin=2.0 * cm,
                          title=_t(portada.get("titulo", "")), author="DIRECTA")
    doc.addPageTemplates([
        PageTemplate(id="portada", frames=[Frame(0, 0, PW, PH, 0, 0, 0, 0)], onPage=on_portada),
        PageTemplate(id="n", frames=[Frame(LM, 2.0 * cm, ANCHO, PH - 3.6 * cm, 0, 0, 0, 0)], onPage=cabecera),
    ])
    flow = [Spacer(1, 1), NextPageTemplate("n"), PageBreak()]
    for i, (tit, entrada, bloques) in enumerate(capitulos, 1):
        if i > 1:
            flow.append(PageBreak())
        flow += [_Apertura(i, tit, entrada, paleta), Spacer(1, 16)] + list(bloques)
    doc.build(flow, canvasmaker=P._canvas_con_pie({"pie": pie}))
    return buf.getvalue()
