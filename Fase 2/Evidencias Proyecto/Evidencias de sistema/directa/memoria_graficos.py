# -*- coding: utf-8 -*-
"""
DIRECTA - Gráficos del PDF de la Memoria Anual (matplotlib -> PNG).

Reglas de diseño (método dataviz):
  * la forma sale del trabajo del dato: magnitud ordenada (cobertura) -> barras apiladas de UN solo tono;
    categorías sin orden (severidades) -> barras con la etiqueta en el eje, no solo el color;
    comparación entre años -> barras con el valor escrito sobre cada una;
  * color al final: escala secuencial de un tono para la cobertura; para dos series se usan solo los
    puestos 1 (azul) y 2 (naranja) del orden categórico validado con validate_palette.js; las severidades usan
    la paleta de estado corporativa y siempre llevan etiqueta de texto;
  * marcas finas, rejilla tenue, etiquetas directas, nunca dos ejes verticales.
"""
import base64
import io

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

TINTA = "#2B2F36"
TINTA_SUAVE = "#5F6877"
REJILLA = "#E3E7ED"
SUPERFICIE = "#FFFFFF"
AZUL = "#2a78d6"          # categórico 1 (validado)
NARANJA = "#eb6834"       # categórico 2 (validado)
SECUENCIAL = {"fuerte": "#1B4F8F", "debil": "#7BA3D6", "ninguna": "#D3DDEA"}
SEVERIDAD = {"crítica": "#8E1B2E", "alta": "#C2571A", "media": "#A67C00", "baja": "#2F6B4F"}
ETIQ_NIVEL = {"fuerte": "Con evidencia", "debil": "Evidencia débil", "ninguna": "Sin evidencia"}


def _estilo():
    plt.rcParams.update({
        "font.family": "DejaVu Sans", "font.size": 8.5, "text.color": TINTA, "axes.labelcolor": TINTA_SUAVE,
        "axes.edgecolor": REJILLA, "xtick.color": TINTA_SUAVE, "ytick.color": TINTA,
        "axes.facecolor": SUPERFICIE, "figure.facecolor": SUPERFICIE, "axes.spines.top": False,
        "axes.spines.right": False, "axes.linewidth": 0.8,
    })


def _png(fig):
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=170, bbox_inches="tight", facecolor=SUPERFICIE)
    plt.close(fig)
    return buf.getvalue()


def data_uri(png):
    return "data:image/png;base64," + base64.b64encode(png).decode("ascii")


def _corto(t, n=44):
    t = str(t)
    return t if len(t) <= n else t[: n - 1].rstrip() + "…"


def _sin_datos(texto, ancho=6.7, alto=1.0):
    _estilo()
    fig, ax = plt.subplots(figsize=(ancho, alto))
    ax.axis("off")
    ax.text(0.5, 0.5, texto, ha="center", va="center", color=TINTA_SUAVE, fontsize=9)
    return _png(fig)


# ----------------------------------------------------------------------------- 1. cobertura NCG 461
def grafico_cobertura(capitulos):
    """capitulos = [{numero, titulo, temas:[{nivel}]}] -> barras horizontales apiladas por capítulo."""
    filas = []
    for c in capitulos:
        n = {"fuerte": 0, "debil": 0, "ninguna": 0}
        for t in c.get("temas", []):
            n[t.get("nivel", "ninguna")] = n.get(t.get("nivel", "ninguna"), 0) + 1
        filas.append((f"{c['numero']}. {_corto(c['titulo'])}", n))
    if not filas:
        return _sin_datos("Sin capítulos que mostrar")
    _estilo()
    fig, ax = plt.subplots(figsize=(6.7, 0.36 * len(filas) + 1.1))
    y = list(range(len(filas)))[::-1]
    izq = [0] * len(filas)
    for nivel in ("fuerte", "debil", "ninguna"):
        vals = [f[1][nivel] for f in filas]
        ax.barh(y, vals, left=izq, height=0.58, color=SECUENCIAL[nivel], edgecolor=SUPERFICIE, linewidth=1.6, label=ETIQ_NIVEL[nivel])
        for yi, v, l in zip(y, vals, izq):
            if v:
                ax.text(l + v / 2, yi, str(v), ha="center", va="center", fontsize=8,
                        color="#FFFFFF" if nivel != "ninguna" else TINTA, fontweight="bold")
        izq = [a + b for a, b in zip(izq, vals)]
    ax.set_yticks(y)
    ax.set_yticklabels([f[0] for f in filas])
    ax.set_xlim(0, max(izq) + 0.4)
    ax.xaxis.set_major_locator(plt.MaxNLocator(integer=True))
    ax.grid(axis="x", color=REJILLA, linewidth=0.7)
    ax.set_axisbelow(True)
    ax.tick_params(length=0)
    ax.set_xlabel("Temas que pide la norma (cantidad)")
    ax.legend(ncol=3, loc="lower left", bbox_to_anchor=(0, 1.0), frameon=False, handlelength=1.1, fontsize=8)
    return _png(fig)


# ----------------------------------------------------------------------------- 2. señales por severidad
def grafico_senales(senales):
    """senales = [{severidad}] -> cuántas señales de cada gravedad hay en los capítulos."""
    orden = ["crítica", "alta", "media", "baja"]
    cuenta = {s: 0 for s in orden}
    for s in senales:
        cuenta[s.get("severidad", "baja")] = cuenta.get(s.get("severidad", "baja"), 0) + 1
    if not sum(cuenta.values()):
        return _sin_datos("Sin señales de los agentes asociadas a los capítulos", alto=0.9)
    _estilo()
    fig, ax = plt.subplots(figsize=(6.7, 1.9))
    y = list(range(len(orden)))[::-1]
    vals = [cuenta[s] for s in orden]
    ax.barh(y, vals, height=0.52, color=[SEVERIDAD[s] for s in orden], edgecolor=SUPERFICIE)
    for yi, v in zip(y, vals):
        ax.text(v + max(vals) * 0.02 + 0.05, yi, str(v), va="center", fontsize=9, fontweight="bold")
    ax.set_yticks(y)
    ax.set_yticklabels([s.capitalize() for s in orden])
    ax.set_xlim(0, max(vals) * 1.15 + 0.5)
    ax.xaxis.set_major_locator(plt.MaxNLocator(integer=True))
    ax.grid(axis="x", color=REJILLA, linewidth=0.7)
    ax.set_axisbelow(True)
    ax.tick_params(length=0)
    ax.set_xlabel("Señales de los agentes (cantidad)")
    return _png(fig)


# ----------------------------------------------------------------------------- 3. tono histórico
def grafico_tono(por_memoria, borrador=None):
    """por_memoria = {"2022": {palabras_por_oracion, cifras_por_mil, ...}}; borrador = medidas del borrador o None."""
    if not por_memoria:
        return _sin_datos("Aún no hay memorias anteriores medidas para comparar el tono")
    años = sorted(por_memoria.keys())
    medidas = [("palabras_por_oracion", "Palabras por oración"), ("cifras_por_mil", "Cifras por cada 1.000 palabras")]
    _estilo()
    fig, axes = plt.subplots(1, 2, figsize=(6.7, 2.5))
    for ax, (clave, titulo) in zip(axes, medidas):
        etiquetas = list(años) + (["Borrador"] if borrador and borrador.get(clave) is not None else [])
        vals = [por_memoria[a].get(clave, 0) for a in años] + ([borrador[clave]] if borrador and borrador.get(clave) is not None else [])
        colores = [AZUL] * len(años) + ([NARANJA] if len(etiquetas) > len(años) else [])
        x = list(range(len(etiquetas)))
        ax.bar(x, vals, width=0.58, color=colores, edgecolor=SUPERFICIE)
        for xi, v in zip(x, vals):
            ax.text(xi, v + max(vals) * 0.02, f"{v:.1f}".replace(".", ","), ha="center", va="bottom", fontsize=7.5)
        ax.set_xticks(x)
        ax.set_xticklabels(etiquetas, fontsize=7.5, rotation=0)
        ax.set_ylim(0, max(vals) * 1.18)
        ax.set_title(titulo, fontsize=8.5, loc="left", color=TINTA, pad=8)
        ax.grid(axis="y", color=REJILLA, linewidth=0.7)
        ax.set_axisbelow(True)
        ax.tick_params(length=0)
        ax.spines["left"].set_visible(False)
        ax.set_yticks([])
    if borrador:
        from matplotlib.patches import Patch
        fig.legend(handles=[Patch(color=AZUL, label="Memorias anteriores"), Patch(color=NARANJA, label="Este borrador")],
                   loc="lower center", ncol=2, frameon=False, bbox_to_anchor=(0.5, -0.06), fontsize=8)
    fig.tight_layout(w_pad=2.0)
    return _png(fig)


# ----------------------------------------------------------------------------- 4. pendientes por capítulo
def grafico_pendientes(filas):
    """filas = [(etiqueta, cantidad)] -> datos que aún debe entregar un área, por capítulo."""
    if not filas or not any(n for _, n in filas):
        return _sin_datos("Ningún capítulo tiene datos pendientes", alto=0.9)
    _estilo()
    fig, ax = plt.subplots(figsize=(6.7, 0.3 * len(filas) + 0.9))
    y = list(range(len(filas)))[::-1]
    vals = [n for _, n in filas]
    ax.barh(y, vals, height=0.5, color=AZUL, edgecolor=SUPERFICIE)
    for yi, v in zip(y, vals):
        ax.text(v + max(vals) * 0.02 + 0.05, yi, str(v), va="center", fontsize=8.5, fontweight="bold")
    ax.set_yticks(y)
    ax.set_yticklabels([_corto(e) for e, _ in filas])
    ax.set_xlim(0, max(vals) * 1.15 + 0.5)
    ax.xaxis.set_major_locator(plt.MaxNLocator(integer=True))
    ax.grid(axis="x", color=REJILLA, linewidth=0.7)
    ax.set_axisbelow(True)
    ax.tick_params(length=0)
    ax.set_xlabel("Datos por completar (cantidad)")
    return _png(fig)
