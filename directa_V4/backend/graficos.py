# -*- coding: utf-8 -*-
"""Gráficos para los PDF (Frente D2). Se dibujan en el servidor con matplotlib como imágenes PNG y se
insertan en el HTML que convierte xhtml2pdf (que no ejecuta JavaScript ni SVG complejo).

Criterios de diseño (guía de visualización del proyecto):
- un solo eje por gráfico; medidas de distinta escala se indexan a una base común (% de la meta);
- marcas delgadas, grilla tenue y sin bordes innecesarios;
- el texto va en tinta neutra; los colores de estado (severidad, semáforo) siempre con su etiqueta escrita;
- una serie no lleva leyenda (la nombra el título); dos o más sí.
"""
import base64
import io

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

TINTA = "#2B2F36"
TINTA_2 = "#5F6877"
GRILLA = "#E3E7EE"
SERIE_1 = "#2a78d6"            # azul (categórica 1)
META = "#2B2F36"
COLOR_SEV = {"crítica": "#8E1B2E", "alta": "#C2571A", "media": "#A67C00", "baja": "#2F6B4F"}
COLOR_SEM = {"verde": "#2F6B4F", "amarillo": "#A67C00", "rojo": "#8E1B2E", "sin_dato": "#9AA3B0"}
ETQ_SEM = {"verde": "En meta", "amarillo": "Atención", "rojo": "Fuera de meta", "sin_dato": "Sin dato"}

plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 9, "axes.edgecolor": GRILLA, "axes.labelcolor": TINTA_2,
    "xtick.color": TINTA_2, "ytick.color": TINTA, "axes.titlesize": 10.5, "axes.titleweight": "bold",
    "axes.titlecolor": TINTA, "axes.titlelocation": "left", "axes.titlepad": 10,
})


def _png(fig):
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=170, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return base64.b64encode(buf.getvalue()).decode("ascii")


def img_html(b64, ancho_cm=16.5):
    """<img> para xhtml2pdf (acepta data URI)."""
    return f"<img src='data:image/png;base64,{b64}' style='width:{ancho_cm}cm;'/>"


def _limpiar(ax, eje_valores="x"):
    for lado in ("top", "right", "left" if eje_valores == "x" else "bottom"):
        ax.spines[lado].set_visible(False)
    ax.grid(axis=eje_valores, color=GRILLA, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.tick_params(length=0)


def senales_por_severidad(conteo, titulo="Señales por severidad"):
    """Barras verticales: cantidad de señales por severidad (color de estado + etiqueta escrita)."""
    sevs = ["crítica", "alta", "media", "baja"]
    vals = [int(conteo.get(s, 0) or 0) for s in sevs]
    fig, ax = plt.subplots(figsize=(6.4, 2.6))
    barras = ax.bar([s.capitalize() for s in sevs], vals, width=0.5, color=[COLOR_SEV[s] for s in sevs])
    for b, v in zip(barras, vals):
        ax.annotate(str(v), (b.get_x() + b.get_width() / 2, v), xytext=(0, 3), textcoords="offset points",
                    ha="center", va="bottom", color=TINTA, fontsize=9, fontweight="bold")
    ax.set_ylim(0, max(vals + [1]) * 1.25)
    ax.set_title(titulo)
    ax.set_yticks([])
    _limpiar(ax, "y")
    ax.spines["left"].set_visible(False)
    return _png(fig)


def puntaje_por_area(areas, titulo="Puntaje por área (0 a 100; más alto es mejor)"):
    """Barras horizontales de una sola serie, con el valor escrito al final de cada barra.
    `areas`: [(nombre, puntaje)] solo de las áreas con información."""
    areas = sorted([(n, int(s)) for n, s in areas if s is not None], key=lambda x: x[1])
    if not areas:
        return None
    alto = max(2.0, 0.32 * len(areas) + 0.8)
    fig, ax = plt.subplots(figsize=(6.4, alto))
    nombres = [n for n, _ in areas]
    vals = [s for _, s in areas]
    ax.barh(nombres, vals, height=0.55, color=SERIE_1)
    for i, v in enumerate(vals):
        ax.annotate(str(v), (v, i), xytext=(4, 0), textcoords="offset points", va="center", color=TINTA, fontsize=8.5)
    ax.set_xlim(0, 105)
    ax.set_title(titulo)
    _limpiar(ax, "x")
    return _png(fig)


def cumplimiento_indicadores(indicadores, titulo="Indicadores: avance respecto de la meta (100% = meta)"):
    """Cada indicador en % de su meta (base común, un solo eje). KPI: valor/meta; KRI: meta/valor.
    El color es el del semáforo y la etiqueta escrita dice el estado."""
    filas = []
    for i in indicadores:
        try:
            v, m = float(i.get("valor")), float(i.get("meta"))
        except (TypeError, ValueError):
            continue
        if i.get("direccion") == "menor":
            pct = 100.0 if v <= m else (100.0 * m / v if v else 0.0)
        else:
            pct = 100.0 * v / m if m else (100.0 if v >= m else 0.0)
        filas.append((str(i.get("nombre") or "")[:42], max(0.0, min(150.0, pct)), i.get("estado") or "sin_dato"))
    if not filas:
        return None
    alto = max(2.0, 0.34 * len(filas) + 0.9)
    fig, ax = plt.subplots(figsize=(6.4, alto))
    nombres = [f[0] for f in filas]
    ax.barh(nombres, [f[1] for f in filas], height=0.55, color=[COLOR_SEM.get(f[2], COLOR_SEM["sin_dato"]) for f in filas])
    ax.axvline(100, color=META, linewidth=1.2, linestyle=(0, (3, 2)))
    for i, f in enumerate(filas):
        ax.annotate(f"{f[1]:.0f}% · {ETQ_SEM.get(f[2], '')}", (f[1], i), xytext=(4, 0), textcoords="offset points",
                    va="center", color=TINTA, fontsize=8)
    ax.set_xlim(0, 175)
    ax.set_xticks([0, 50, 100, 150])
    ax.set_xticklabels(["0%", "50%", "100% = meta", "150%"])
    ax.set_title(titulo)
    _limpiar(ax, "x")
    return _png(fig)


def evolucion(puntos, titulo="Evolución del puntaje global de preparación"):
    """Línea de una sola serie entre documentos o años: [(etiqueta, valor)]."""
    puntos = [(str(e), float(v)) for e, v in puntos if v is not None]
    if len(puntos) < 2:
        return None
    fig, ax = plt.subplots(figsize=(6.4, 2.5))
    xs = list(range(len(puntos)))
    ys = [p[1] for p in puntos]
    ax.plot(xs, ys, color=SERIE_1, linewidth=2, marker="o", markersize=6, markeredgecolor="white", markeredgewidth=1.5)
    for x, y in zip(xs, ys):
        ax.annotate(f"{y:.0f}", (x, y), xytext=(0, 7), textcoords="offset points", ha="center", color=TINTA, fontsize=8.5)
    ax.set_xticks(xs)
    ax.set_xticklabels([p[0] for p in puntos])
    ax.set_ylim(0, 105)
    ax.set_title(titulo)
    _limpiar(ax, "y")
    return _png(fig)
