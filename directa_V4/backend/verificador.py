# -*- coding: utf-8 -*-
"""Verificación doble de las respuestas (Frente B del plan).

Ninguna respuesta debe llegar al gerente sin que un revisor distinto del que la escribió compruebe
que cada afirmación está respaldada por el documento. Tres capas:

  Capa 1 · comprobaciones por código (sin IA, gratis y rápidas)
      cifras que no aparecen en los fragmentos (formato chileno: MM$ 1.500, 12,5%), porcentajes y
      variaciones que se pueden recalcular, páginas citadas que no existen, citas textuales que no
      son literales y plazos anteriores a la fecha de corte del documento.
  Capa 2 · verificador de evidencia (IA, otro modelo)
      divide la respuesta en afirmaciones y marca cada una como respaldada, parcial, no respaldada o
      contradicha, citando el fragmento. Trabaja como tres sub-agentes (cifras, evidencia, período y
      alcance) que absorben las reglas (a) a (n) de agentes.py.
  Capa 3 · resolución
      si hay afirmaciones sin respaldo, el agente que escribió corrige solo esas, una sola vez; lo que
      siga sin respaldo queda marcado.

Qué NO verifica: que el documento sea cierto en el mundo real. Solo que la respuesta sea fiel al documento.
"""
import json
import os
import re
import threading
import unicodedata
from datetime import date, datetime, timedelta

import ia_config as _ia

# ---------------------------------------------------------------------------
# Configuración (variables de entorno)
# ---------------------------------------------------------------------------
VERIFICAR_CHAT = os.getenv("VERIFICAR_CHAT", "1").strip().lower() not in ("0", "false", "no")
VERIFICAR_ANALISIS = os.getenv("VERIFICAR_ANALISIS", "1").strip().lower() not in ("0", "false", "no")
# "unificado": una sola llamada con los tres revisores (más barato). "separado": tres llamadas en paralelo.
MODO_SUBAGENTES = os.getenv("VERIFICADOR_SUBAGENTES", "unificado").strip().lower()
MAX_AFIRMACIONES = 12
MAX_CHARS_FRAGMENTO = 1100
MAX_FRAGMENTOS = 14

ESTADOS = ("respaldada", "parcial", "no_respaldada", "contradicha")
SELLOS = {
    "verificada": "Verificada",
    "con_reservas": "Con reservas",
    "no_verificable": "No verificable",
}

# Marcas que reconoce la IA simulada del modo demo (demo/demo_ia.py)
MARCA_VERIFICADOR = "[VERIFICADOR DIRECTA]"
MARCA_CORRECCION = "[CORRECCION DIRECTA]"
MARCA_VERIF_SENALES = "[VERIFICADOR SENALES DIRECTA]"


# ---------------------------------------------------------------------------
# Utilidades de texto
# ---------------------------------------------------------------------------
def normalizar(texto):
    """Minúsculas, sin tildes, sin guiones de corte de línea y con espacios simples."""
    t = str(texto or "").replace("\u0002", "").replace("­", "")
    t = re.sub(r"(\w)-\s*\n\s*(\w)", r"\1\2", t)
    t = unicodedata.normalize("NFD", t.lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    t = t.replace("“", '"').replace("”", '"').replace("«", '"').replace("»", '"').replace("’", "'")
    return re.sub(r"\s+", " ", t).strip()


def _solo_palabras(texto):
    return re.sub(r"[^a-z0-9 ]+", " ", normalizar(texto)).split()


_PALABRAS_NUM = {
    "cero": 0, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7,
    "ocho": 8, "nueve": 9, "diez": 10, "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15,
    "dieciseis": 16, "diecisiete": 17, "dieciocho": 18, "diecinueve": 19, "veinte": 20, "treinta": 30,
    "cuarenta": 40, "cincuenta": 50, "sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90, "cien": 100,
}

_MESES = {"enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
          "septiembre": 9, "setiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12}

# Número en formato chileno (1.234.567,8), simple (388,3 · 12) o con punto decimal (8.1); con % opcional.
_RE_NUM = re.compile(
    r"(?<![\w.,/])(?P<par>\()?(?P<signo>[-−–]\s?)?"
    r"(?P<num>\d{1,3}(?:\.\d{3})+(?:,\d+)?|\d+,\d+|\d+\.\d+|\d+)"
    r"(?P<pct>\s?%)?(?!\w)")
_RE_LISTA = re.compile(r"^\s*\d{1,2}[.)]\s")


class Cifra:
    __slots__ = ("texto", "valores", "alternos", "decimales", "pct", "inicio", "fin", "anio", "pequeno")

    def __init__(self, texto, valores, decimales, pct, inicio, fin, alternos=()):
        self.texto = texto
        self.valores = valores          # lectura principal
        self.alternos = list(alternos)  # lecturas posibles menos probables (1.140 leído como 1,14)
        self.decimales = decimales
        self.pct = pct
        self.inicio = inicio
        self.fin = fin
        v = valores[0]
        self.anio = (not pct and decimales == 0 and float(v).is_integer() and 1900 <= v <= 2100
                     and re.fullmatch(r"\d{4}", texto.strip("%() ")) is not None)
        self.pequeno = (not pct and decimales == 0 and v < 10)

    def tolerancia(self):
        return 0.5 * (10 ** -self.decimales) + 1e-9


def _interpretar(num):
    """Devuelve (valores, alternos, decimales mostrados)."""
    if re.fullmatch(r"\d{1,3}(?:\.\d{3})+(?:,\d+)?", num):
        entero, _, dec = num.partition(",")
        v = float(entero.replace(".", "") + ("." + dec if dec else ""))
        alternos = [float(num)] if (not dec and num.count(".") == 1) else []   # "1.140" en formato inglés
        return [v], alternos, len(dec)
    if "," in num:
        a, b = num.split(",", 1)
        alternos = [float(a + b)] if len(b) == 3 else []                      # "1,234" en formato inglés
        return [float(a + "." + b)], alternos, len(b)
    if "." in num:
        return [float(num)], [], len(num.split(".", 1)[1])
    return [float(num)], [], 0


def extraer_cifras(texto, omitir_listas=True):
    """Cifras de un texto, sin marcadores de lista ni números de página citados."""
    out = []
    texto = str(texto or "")
    paginas = [(m.start(), m.end()) for m in _RE_PAGINA.finditer(texto)]
    lineas_lista = set()
    if omitir_listas:
        pos = 0
        for linea in texto.split("\n"):
            m = _RE_LISTA.match(linea)
            if m:
                lineas_lista.add(pos + m.start())
            pos += len(linea) + 1
    for m in _RE_NUM.finditer(texto):
        ini = m.start("num")
        if any(a <= ini < b for a, b in paginas):
            continue
        if omitir_listas and any(ini - 4 <= p <= ini for p in lineas_lista) and len(m.group("num")) <= 2 and not m.group("pct"):
            continue
        valores, alternos, dec = _interpretar(m.group("num"))
        out.append(Cifra(m.group(0).strip(), valores, dec, bool(m.group("pct")), m.start(), m.end(), alternos))
    return out


def _cifras_fragmentos(fragmentos):
    """Todas las cifras de los fragmentos (incluidos los números escritos en palabras: 'siete miembros')."""
    lista = []
    for i, f in enumerate(fragmentos):
        texto = f.get("content") or ""
        for c in extraer_cifras(texto, omitir_listas=False):
            lista.append((i, c))
        for w in _solo_palabras(texto):
            if w in _PALABRAS_NUM:
                lista.append((i, Cifra(w, [float(_PALABRAS_NUM[w])], 0, False, 0, 0)))
    return lista


def _coincide(c, valor_frag, escalas):
    for x in c.valores:
        for s in escalas:
            y = valor_frag * s
            if abs(x - y) <= max(c.tolerancia(), abs(x) * 1e-6):
                return True
    return False


def _valores_frag(c, f):
    """Lecturas de la cifra del fragmento que se comparan: las alternativas solo si la cifra buscada tiene decimales."""
    return f.valores + (f.alternos if c.decimales else [])


_ESCALAS_AMPLIAS = (1, 1e-3, 1e3, 1e-6, 1e6)


def _buscar_en_fragmentos(c, cifras_frag):
    """Índice del fragmento que contiene la cifra (o None)."""
    # Un porcentaje entero ("12%") solo se valida contra otro porcentaje; uno con decimales ("33,3%")
    # también contra la cifra sin el signo, porque en los cuadros el % suele ir solo en el encabezado.
    pasadas = ((True, False) if c.decimales else (True,)) if c.pct else (False,)
    for exigir_pct in pasadas:
        for i, f in cifras_frag:
            if exigir_pct and not f.pct:
                continue
            if c.pct or c.pequeno or c.anio or (c.decimales == 0 and c.valores[0] < 100):
                escalas = (1,)
            else:
                escalas = _ESCALAS_AMPLIAS
            if any(_coincide(c, v, escalas) for v in _valores_frag(c, f)):
                return i
    return None


def _calculable(c, base, cifras_pct, ancla=None):
    """¿La cifra sale de un cálculo con otras cifras? (variación %, proporción o diferencia en puntos).
    `ancla`: si se da, al menos uno de los dos operandos debe ser una de esas cifras (las que cita la
    respuesta). Así no se 'valida' una cifra inventada con una coincidencia entre dos números cualesquiera."""
    v = abs(c.valores[0])
    tol = max(c.tolerancia() + 0.01, abs(v) * 0.002)
    nums = [abs(x.valores[0]) for x in base if not x.pct and not x.anio and x.valores[0] != 0]
    nums = list(dict.fromkeys(nums))[:60]

    def anclado(a, b):
        return ancla is None or any(abs(a - z) <= 1e-9 * max(1, a) or abs(b - z) <= 1e-9 * max(1, b) for z in ancla)

    if c.pct:
        for a in nums:
            for b in nums:
                if a == b or not anclado(a, b):
                    continue
                candidatos = []
                if 0.2 <= a / b <= 5:          # variación entre cifras de magnitud parecida (mismo indicador)
                    candidatos.append((a / b - 1) * 100)
                if a <= b:                     # proporción: una parte sobre el total
                    candidatos.append(a / b * 100)
                for r in candidatos:
                    if abs(abs(r) - v) <= tol:
                        return f"{_fmt(a)} / {_fmt(b)}"
        if ancla is None:
            pcts = list(dict.fromkeys(abs(x.valores[0]) for x in cifras_pct))[:30]
            for a in pcts:
                for b in pcts:
                    if a != b and abs(abs(a - b) - v) <= tol:
                        return f"{_fmt(a)}% - {_fmt(b)}%"
        return None
    if ancla is not None:
        return None
    for a in nums:
        for b in nums:
            if a == b:
                continue
            for r, op in ((a - b, "-"), (a + b, "+")):
                if abs(abs(r) - v) <= tol:
                    return f"{_fmt(a)} {op} {_fmt(b)}"
    return None


def _fmt(x):
    if float(x).is_integer():
        return f"{int(x):,}".replace(",", ".")
    return f"{x:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")


# ---------------------------------------------------------------------------
# Páginas, citas y plazos
# ---------------------------------------------------------------------------
_RE_PAGINA = re.compile(r"\bp[áa]g(?:ina)?s?\.?\s*(\d{1,4})(?:\s*(?:[-–]|y|a|,)\s*(\d{1,4}))?", re.I)
_RE_CITA = re.compile(r"[“\"«]([^”\"»\n]{12,400})[”\"»]")


def _paginas_citadas(texto):
    out = []
    for m in _RE_PAGINA.finditer(texto or ""):
        a = int(m.group(1))
        b = int(m.group(2)) if m.group(2) else None
        out.append((m.group(0), [a] + ([b] if b else [])))
    return out


def _texto_fragmentos_norm(fragmentos):
    return " ".join(" ".join(_solo_palabras(f.get("content") or "")) for f in fragmentos)


def _revisar_cita(cita, corpus_norm):
    palabras = _solo_palabras(cita)
    if len(palabras) < 4:
        return "ok"
    frase = " ".join(palabras)
    if frase in corpus_norm:
        return "ok"
    tejas = [" ".join(palabras[i:i + 4]) for i in range(0, max(1, len(palabras) - 3))]
    halladas = sum(1 for t in tejas if t in corpus_norm)
    return "aproximada" if halladas / max(1, len(tejas)) >= 0.6 else "no_literal"


_RE_CLAVE_PLAZO = re.compile(r"\b(?:recomiend\w*|recomendam\w*|sugier\w*|suger\w*|propon\w*|propong\w*|deber[íi]a\w*|"
                             r"se debe|plazo|fecha l[íi]mite|a m[áa]s tardar|antes de|comprometer|presentar|implementar|"
                             r"calendarizar|programar)\b", re.I)
_MES_RE = "|".join(_MESES)
_RE_FECHA = [
    (re.compile(rf"(?:(\d{{1,2}})\s+de\s+)?({_MES_RE})\s+(?:de|del)?\s*(\d{{4}})", re.I), "mes"),
    (re.compile(r"(primer|segundo|tercer|cuarto)\s+(trimestre|semestre)\s+(?:de|del)\s+(\d{4})", re.I), "periodo"),
    (re.compile(r"\b([QT])([1-4])\s*[-/ ]?\s*(\d{4})\b"), "q"),
    (re.compile(r"\b(\d{1,2})/(\d{1,2})/(\d{4})\b"), "dmy"),
]


def _fin_de_mes(y, m):
    if m == 12:
        return date(y, 12, 31)
    return date(y, m + 1, 1) - timedelta(days=1)


def _fechas_en(oracion):
    out = []
    for rx, tipo in _RE_FECHA:
        for m in rx.finditer(oracion):
            try:
                if tipo == "mes":
                    y, mes = int(m.group(3)), _MESES[m.group(2).lower()]
                    d = date(y, mes, int(m.group(1))) if m.group(1) else _fin_de_mes(y, mes)
                elif tipo == "periodo":
                    n = {"primer": 1, "segundo": 2, "tercer": 3, "cuarto": 4}[m.group(1).lower()]
                    y = int(m.group(3))
                    meses = 3 if m.group(2).lower() == "trimestre" else 6
                    d = _fin_de_mes(y, min(12, n * meses))
                elif tipo == "q":
                    y = int(m.group(3))
                    d = _fin_de_mes(y, int(m.group(2)) * 3)
                else:
                    d = date(int(m.group(3)), int(m.group(2)), int(m.group(1)))
                out.append((m.group(0), d))
            except (ValueError, KeyError):
                continue
    return out


def inferir_fecha_corte(fragmentos):
    """Fecha de corte del documento: el mayor '31 de diciembre de AAAA' que aparezca; si no, el mayor
    año del texto que no sea futuro. Devuelve un date o None."""
    texto = " ".join(normalizar(f.get("content") or "") for f in fragmentos)
    hoy = date.today()
    anios = [int(y) for y in re.findall(r"31 de diciembre (?:de |del )?(\d{4})", texto) if int(y) <= hoy.year]
    if anios:
        return date(max(anios), 12, 31)
    anios = [int(y) for y in re.findall(r"(?:ejercicio|ano|memoria(?: anual| integrada)?)\s+(\d{4})", texto)
             if 1990 <= int(y) <= hoy.year]
    if anios:
        return date(max(anios), 12, 31)
    return None


def _oraciones(texto):
    partes = re.split(r"(?<=[.!?])\s+|\n+", str(texto or ""))
    return [p.strip() for p in partes if p and p.strip()]


# ---------------------------------------------------------------------------
# CAPA 1
# ---------------------------------------------------------------------------
def capa1(respuesta, fragmentos, fecha_corte=None, hoy=None):
    """Comprobaciones por código. `fragmentos`: lista de dicts con 'content' y 'page_number'.
    Devuelve {"cifras": [...], "problemas": [...], "fecha_corte": "AAAA-MM-DD" | None}."""
    respuesta = str(respuesta or "")
    fragmentos = [f for f in (fragmentos or []) if isinstance(f, dict) and (f.get("content") or "").strip()]
    hoy = hoy or date.today()
    if fecha_corte is None:
        fecha_corte = inferir_fecha_corte(fragmentos)
    elif isinstance(fecha_corte, str):
        try:
            fecha_corte = datetime.strptime(fecha_corte[:10], "%Y-%m-%d").date()
        except ValueError:
            fecha_corte = inferir_fecha_corte(fragmentos)

    cifras_frag = _cifras_fragmentos(fragmentos)
    cifras_resp = extraer_cifras(respuesta)
    pct_resp = [c for c in cifras_resp if c.pct]
    cifras, problemas = [], []

    for c in cifras_resp:
        i = _buscar_en_fragmentos(c, cifras_frag)
        if i is not None:
            cifras.append({"cifra": c.texto, "estado": "encontrada", "pagina": fragmentos[i].get("page_number")})
            continue
        formula = _calculable(c, [x for x in cifras_resp if x is not c], pct_resp)
        if formula is None and c.pct:
            ancla = [abs(x.valores[0]) for x in cifras_resp if not x.pct and x is not c]
            for j, f in enumerate(fragmentos):
                propias = [x for k, x in cifras_frag if k == j]
                formula = _calculable(c, propias, [x for x in propias if x.pct], ancla=ancla)
                if formula:
                    formula += f" (pág. {f.get('page_number') or '?'})"
                    break
        if formula:
            cifras.append({"cifra": c.texto, "estado": "calculada", "formula": formula})
            continue
        gravedad = "baja" if c.pequeno else ("media" if c.anio else "alta")
        cifras.append({"cifra": c.texto, "estado": "no_encontrada"})
        contexto = respuesta[max(0, c.inicio - 60): c.fin + 40].replace("\n", " ").strip()
        problemas.append({"tipo": "cifra_no_encontrada", "gravedad": gravedad, "texto": c.texto,
                          "detalle": f"La cifra «{c.texto}» no aparece en los fragmentos revisados ni se obtiene "
                                     f"recalculando otras cifras. Contexto: …{contexto}…"})

    paginas_frag = {f.get("page_number") for f in fragmentos if f.get("page_number") is not None}
    if paginas_frag:
        for texto_pag, nums in _paginas_citadas(respuesta):
            faltan = [n for n in nums if n not in paginas_frag]
            if faltan and len(faltan) == len(nums):
                problemas.append({"tipo": "pagina_inexistente", "gravedad": "media", "texto": texto_pag,
                                  "detalle": f"Se cita «{texto_pag}», pero los fragmentos revisados son de las páginas "
                                             f"{', '.join(str(p) for p in sorted(paginas_frag)[:12])}."})

    corpus = _texto_fragmentos_norm(fragmentos)
    for m in _RE_CITA.finditer(respuesta):
        r = _revisar_cita(m.group(1), corpus)
        if r == "no_literal":
            problemas.append({"tipo": "cita_no_literal", "gravedad": "alta", "texto": m.group(1)[:160],
                              "detalle": "Va entre comillas como si fuera textual, pero no aparece así en los fragmentos."})
        elif r == "aproximada":
            problemas.append({"tipo": "cita_aproximada", "gravedad": "baja", "texto": m.group(1)[:160],
                              "detalle": "La cita entre comillas no es literal: es una paráfrasis cercana del documento."})

    for oracion in _oraciones(respuesta):
        if not _RE_CLAVE_PLAZO.search(oracion):
            continue
        for texto_fecha, d in _fechas_en(oracion):
            if fecha_corte and d <= fecha_corte:
                problemas.append({"tipo": "plazo_anterior_al_corte", "gravedad": "alta", "texto": texto_fecha,
                                  "detalle": f"Se propone un plazo ({texto_fecha}) anterior o igual a la fecha de corte del "
                                             f"documento ({fecha_corte.strftime('%d/%m/%Y')})."})
            elif d < hoy:
                problemas.append({"tipo": "plazo_vencido", "gravedad": "media", "texto": texto_fecha,
                                  "detalle": f"El plazo propuesto ({texto_fecha}) ya pasó (hoy es {hoy.strftime('%d/%m/%Y')})."})

    return {"cifras": cifras, "problemas": problemas,
            "fecha_corte": fecha_corte.isoformat() if fecha_corte else None}


def cifras_de_otros_periodos(texto, fragmentos_actuales, fragmentos_anteriores):
    """Cifras del texto que SOLO aparecen en documentos de años anteriores (no en los del año actual).
    Sirve para que el borrador de la memoria no arrastre cifras del pasado como si fueran del año."""
    act = _cifras_fragmentos(fragmentos_actuales or [])
    ant = _cifras_fragmentos(fragmentos_anteriores or [])
    out = []
    for c in extraer_cifras(texto):
        if c.pequeno or c.anio:
            continue
        if _buscar_en_fragmentos(c, act) is None:
            i = _buscar_en_fragmentos(c, ant)
            if i is not None:
                f = (fragmentos_anteriores or [])[i]
                out.append({"cifra": c.texto, "documento": f.get("documento") or f.get("document_id"),
                            "pagina": f.get("page_number")})
    return out


# ---------------------------------------------------------------------------
# Reglas (a)-(n) de agentes.py repartidas en los tres sub-agentes
# ---------------------------------------------------------------------------
def _reglas_por_letra():
    try:
        import agentes
        texto = getattr(agentes, "REGLAS_BASE_ANALISIS", "") or ""
    except Exception:
        texto = ""
    partes = re.split(r"\(([a-n])\)\s", texto)
    reglas = {}
    for i in range(1, len(partes) - 1, 2):
        reglas[partes[i]] = " ".join(partes[i + 1].split()).strip()
    return reglas


SUBAGENTES = {
    "cifras": {
        "nombre": "Revisor de cifras",
        "foco": "Montos, unidades (MM$, MUS$, US$ millones), porcentajes, variaciones y base de comparación. "
                "Recalcula cada variación con las cifras del fragmento.",
        "reglas": ("b", "h", "i", "n"),
    },
    "evidencia": {
        "nombre": "Revisor de evidencia",
        "foco": "Que cada hecho, cada cita textual y cada 'no consta' tengan respaldo en los fragmentos. "
                "Una ausencia declarada solo es válida si de verdad no aparece en los fragmentos.",
        "reglas": ("a", "c", "d", "e", "g"),
    },
    "periodo": {
        "nombre": "Revisor de período y alcance",
        "foco": "Ejercicio que cubre el documento, norma vigente en esa fecha, plazos posteriores a la fecha de "
                "corte y severidad proporcional a la evidencia.",
        "reglas": ("f", "j", "k", "l", "m"),
    },
}


def _bloque_subagentes(claves):
    reglas = _reglas_por_letra()
    out = []
    for k in claves:
        s = SUBAGENTES[k]
        detalle = " ".join(f"({l}) {reglas[l]}" for l in s["reglas"] if l in reglas)
        out.append(f"- {k.upper()} · {s['nombre']}: {s['foco']}" + (f"\n  Reglas: {detalle}" if detalle else ""))
    return "\n".join(out)


def _prompt_verificador(claves):
    return (
        f"{MARCA_VERIFICADOR}\n"
        "Eres el VERIFICADOR de DIRECTA. No escribiste la respuesta que vas a revisar: la escribió otro agente para el "
        "Gerente General. Tu trabajo es comprobar, afirmación por afirmación, si está respaldada por los FRAGMENTOS del "
        "documento. No juzgas si el documento es cierto en el mundo real, solo si la respuesta es fiel al documento. "
        "Los análisis previos de otros agentes NO son evidencia: solo lo son los fragmentos.\n\n"
        "Revisas con estos revisores:\n" + _bloque_subagentes(claves) + "\n\n"
        f"Divide la respuesta en afirmaciones verificables (máximo {MAX_AFIRMACIONES}). Omite saludos, frases de "
        "transición, preguntas y recomendaciones de criterio que no afirman datos. Cada afirmación va con un solo "
        "revisor (el más pertinente).\n"
        "Estados:\n"
        "- respaldada: un fragmento lo dice o se calcula exactamente con sus cifras.\n"
        "- parcial: el fondo es correcto, pero hay un detalle impreciso (redondeo que cambia el sentido, base de "
        "comparación omitida o cambiada, alcance exagerado, período mal indicado).\n"
        "- no_respaldada: no aparece en los fragmentos.\n"
        "- contradicha: un fragmento dice otra cosa.\n"
        "Para cada una indica el fragmento (F1, F2…) y copia la frase breve del fragmento que la respalda o la contradice. "
        "Si no está respaldada, es parcial o contradicha, escribe en 'correccion' cómo debería decirse según el documento "
        "(o 'eliminar' si no hay base).\n"
        "Las alertas de la revisión automática son pistas: confírmalas o descártalas con los fragmentos.\n\n"
        "Responde ÚNICAMENTE con este JSON:\n"
        '{"afirmaciones":[{"texto":"afirmación tal como aparece","revisor":"cifras|evidencia|periodo",'
        '"estado":"respaldada|parcial|no_respaldada|contradicha","fragmento":"F1","cita":"frase literal breve del fragmento",'
        '"correccion":""}]}'
    )


def _formatear_fragmentos(fragmentos):
    partes = []
    for i, f in enumerate(fragmentos[:MAX_FRAGMENTOS], 1):
        partes.append(f"[F{i} · Página {f.get('page_number') or '?'}]\n{(f.get('content') or '')[:MAX_CHARS_FRAGMENTO]}")
    return "\n\n".join(partes)


def _alertas_capa1(c1):
    lineas = [f"- {p['detalle']}" for p in c1.get("problemas", []) if p.get("gravedad") in ("alta", "media")]
    return "\n".join(lineas[:10]) or "- (sin alertas)"


def _normalizar_afirmaciones(data, fragmentos, revisor_defecto=None):
    lista = data.get("afirmaciones") if isinstance(data, dict) else None
    out = []
    for a in (lista or [])[:MAX_AFIRMACIONES]:
        if not isinstance(a, dict) or not str(a.get("texto") or "").strip():
            continue
        estado = normalizar(a.get("estado")).replace(" ", "_")
        if estado not in ESTADOS:
            estado = "no_respaldada" if "no" in estado else ("contradicha" if "contra" in estado else
                                                             ("parcial" if "parc" in estado else "respaldada"))
        revisor = normalizar(a.get("revisor"))
        revisor = next((k for k in SUBAGENTES if revisor.startswith(k[:4])), revisor_defecto or "evidencia")
        frag = str(a.get("fragmento") or "").upper().strip()
        pagina = None
        m = re.search(r"F(\d+)", frag)
        if m and 1 <= int(m.group(1)) <= len(fragmentos):
            pagina = fragmentos[int(m.group(1)) - 1].get("page_number")
        out.append({
            "texto": str(a.get("texto")).strip()[:400],
            "revisor": revisor,
            "estado": estado,
            "fragmento": frag if m else "",
            "pagina": pagina,
            "cita": str(a.get("cita") or "").strip()[:300],
            "correccion": str(a.get("correccion") or "").strip()[:400],
        })
    return out


def _llamar_verificador(sistema, usuario, max_tokens=1800):
    texto, proveedor = _ia.llamar_llm_verificador(sistema, usuario, temperatura=0.0, max_tokens=max_tokens, json_mode=True)
    return _ia.parsear_json_respuesta(texto), proveedor


def capa2(pregunta, respuesta, fragmentos, c1):
    """Verificador de evidencia (IA). Devuelve (afirmaciones, proveedor). Lanza excepción si falla."""
    usuario = (
        f"PREGUNTA DEL GERENTE: {pregunta or '(sin pregunta)'}\n"
        f"FECHA DE CORTE ESTIMADA DEL DOCUMENTO: {c1.get('fecha_corte') or 'no identificada'}\n"
        f"FECHA DE HOY: {date.today().strftime('%d/%m/%Y')}\n\n"
        f"RESPUESTA A REVISAR:\n<<<\n{respuesta}\n>>>\n\n"
        f"FRAGMENTOS DEL DOCUMENTO:\n{_formatear_fragmentos(fragmentos)}\n\n"
        f"ALERTAS DE LA REVISIÓN AUTOMÁTICA (capa 1):\n{_alertas_capa1(c1)}\n\n"
        "Devuelve el JSON."
    )
    if MODO_SUBAGENTES == "separado":
        resultados, errores = {}, []

        def correr(k):
            try:
                resultados[k] = _llamar_verificador(_prompt_verificador([k]), usuario)
            except Exception as e:  # noqa: BLE001
                errores.append(f"{k}: {e}")

        hilos = [threading.Thread(target=correr, args=(k,)) for k in SUBAGENTES]
        for h in hilos:
            h.start()
        for h in hilos:
            h.join()
        if not resultados:
            raise Exception("; ".join(errores) or "el verificador no respondió")
        afirm, proveedores = [], set()
        for k in SUBAGENTES:
            if k in resultados:
                data, prov = resultados[k]
                proveedores.add(prov)
                afirm.extend(_normalizar_afirmaciones(data, fragmentos, k))
        vistos, unicas = set(), []
        for a in afirm:
            clave = normalizar(a["texto"])[:120]
            if clave not in vistos:
                vistos.add(clave)
                unicas.append(a)
        return unicas[:MAX_AFIRMACIONES], "+".join(sorted(proveedores))
    data, proveedor = _llamar_verificador(_prompt_verificador(list(SUBAGENTES)), usuario)
    return _normalizar_afirmaciones(data, fragmentos), proveedor


# ---------------------------------------------------------------------------
# CAPA 3
# ---------------------------------------------------------------------------
def _prompt_correccion():
    return (
        f"{MARCA_CORRECCION}\n"
        "Eres el agente que escribió esta respuesta para el Gerente General. Un verificador independiente encontró "
        "afirmaciones sin respaldo en los fragmentos del documento. Reescribe la respuesta completa cambiando SOLO esas "
        "afirmaciones: corrígelas con lo que dicen los fragmentos o elimínalas si no tienen base. No agregues datos "
        "nuevos, no cambies lo que ya estaba respaldado y conserva el formato (viñetas, negritas y citas de página). "
        "Responde ÚNICAMENTE con este JSON:\n"
        '{"respuesta":"texto corregido completo","cambios":[{"id":1,"accion":"corregida|eliminada|sin_cambio"}]}'
    )


def capa3(pregunta, respuesta, fragmentos, afirmaciones, c1):
    """Corrección única. Devuelve (respuesta_corregida | None, {id: accion})."""
    malas = [(i, a) for i, a in enumerate(afirmaciones, 1) if a["estado"] in ("no_respaldada", "contradicha")]
    graves_c1 = [p for p in c1.get("problemas", []) if p.get("gravedad") == "alta"]
    if not malas and not graves_c1:
        return None, {}
    lista = "\n".join(
        f"{i}. «{a['texto']}» -> {a['estado'].replace('_', ' ')}"
        + (f". Según el documento: {a['correccion']}" if a.get("correccion") else "")
        + (f" (fragmento {a['fragmento']}: \"{a['cita']}\")" if a.get("cita") else "")
        for i, a in malas)
    extra = "\n".join(f"- {p['detalle']}" for p in graves_c1[:6])
    usuario = (
        f"PREGUNTA: {pregunta}\n\nRESPUESTA ORIGINAL:\n<<<\n{respuesta}\n>>>\n\n"
        f"AFIRMACIONES A CORREGIR:\n{lista or '(ninguna marcada por el verificador)'}\n\n"
        + (f"ALERTAS AUTOMÁTICAS:\n{extra}\n\n" if extra else "")
        + f"FRAGMENTOS DEL DOCUMENTO:\n{_formatear_fragmentos(fragmentos)}\n\nDevuelve el JSON."
    )
    texto = _ia.llamar_llm_chat(_prompt_correccion(), usuario, temperatura=0.1, max_tokens=1600, json_mode=True)
    data = _ia.parsear_json_respuesta(texto)
    nueva = str((data or {}).get("respuesta") or "").strip()
    if len(nueva) < 15:
        return None, {}
    acciones = {}
    for c in (data.get("cambios") or []):
        if isinstance(c, dict):
            try:
                acciones[int(c.get("id"))] = normalizar(c.get("accion"))
            except (TypeError, ValueError):
                continue
    return nueva, acciones


# ---------------------------------------------------------------------------
# Orquestación
# ---------------------------------------------------------------------------
def _sello(afirmaciones, c1, error=None):
    if error:
        return "no_verificable"
    if not afirmaciones:
        return "no_verificable"
    graves = [p for p in c1.get("problemas", []) if p.get("gravedad") in ("alta",)]
    estados = [a.get("estado_final") or a["estado"] for a in afirmaciones]
    if all(e == "respaldada" for e in estados) and not graves:
        return "verificada"
    return "con_reservas"


def _resumen(afirmaciones, sello, corregida):
    if sello == "no_verificable" and not afirmaciones:
        return "No se pudo verificar la respuesta."
    n = len(afirmaciones)
    finales = [a.get("estado_final") or a["estado"] for a in afirmaciones]
    ok = finales.count("respaldada")
    partes = [f"{ok} de {n} afirmaciones respaldadas por el documento"]
    if finales.count("corregida"):
        partes.append(f"{finales.count('corregida')} corregida{'s' if finales.count('corregida') > 1 else ''}")
    if finales.count("eliminada"):
        partes.append(f"{finales.count('eliminada')} eliminada{'s' if finales.count('eliminada') > 1 else ''}")
    if finales.count("parcial"):
        partes.append(f"{finales.count('parcial')} con detalle impreciso")
    sin = finales.count("no_respaldada") + finales.count("contradicha")
    if sin:
        partes.append(f"{sin} sin respaldo")
    return "; ".join(partes) + "."


def verificar_respuesta(pregunta, respuesta, fragmentos, fecha_corte=None, corregir=True, mismo_modelo_que=None):
    """Verifica una respuesta del chat contra los fragmentos que usó el agente.
    Devuelve el objeto 'verificacion' que consumen la app, la web y el informe."""
    inicio = datetime.now()
    fragmentos = [f for f in (fragmentos or []) if isinstance(f, dict) and (f.get("content") or "").strip()]
    base = {"version": 1, "fecha": inicio.isoformat(timespec="seconds"), "capas": []}
    if not fragmentos:
        return {**base, "estado": "no_verificable", "etiqueta": SELLOS["no_verificable"],
                "motivo": "No hubo fragmentos del documento para comprobar la respuesta.",
                "resumen": "Sin fragmentos para comprobar.", "afirmaciones": [], "capa1": {"cifras": [], "problemas": []}}

    c1 = capa1(respuesta, fragmentos, fecha_corte)
    base["capas"].append("codigo")
    afirmaciones, proveedor, error = [], None, None
    try:
        afirmaciones, proveedor = capa2(pregunta, respuesta, fragmentos, c1)
        base["capas"].append("ia")
    except Exception as e:  # noqa: BLE001
        error = str(e)[:300]
        print(f"[VERIFICADOR] Capa 2 falló: {error}", flush=True)

    respuesta_final, original = respuesta, None
    if corregir and not error and afirmaciones:
        try:
            nueva, acciones = capa3(pregunta, respuesta, fragmentos, afirmaciones, c1)
        except Exception as e:  # noqa: BLE001
            nueva, acciones = None, {}
            print(f"[VERIFICADOR] Capa 3 falló: {e}", flush=True)
        if nueva and normalizar(nueva) != normalizar(respuesta):
            base["capas"].append("correccion")
            original, respuesta_final = respuesta, nueva
            malas = [i for i, a in enumerate(afirmaciones, 1) if a["estado"] in ("no_respaldada", "contradicha")]
            for i in malas:
                accion = acciones.get(i, "corregida")
                a = afirmaciones[i - 1]
                if accion.startswith("elim"):
                    a["estado_final"] = "eliminada"
                elif accion.startswith("corr"):
                    a["estado_final"] = "corregida"
            c1 = capa1(respuesta_final, fragmentos, fecha_corte)

    sello = _sello(afirmaciones, c1, error)
    mismo = bool(proveedor and mismo_modelo_que and proveedor == mismo_modelo_que)
    out = {
        **base,
        "estado": sello,
        "etiqueta": SELLOS[sello],
        "resumen": _resumen(afirmaciones, sello, original is not None) if not error else
                   "El verificador no respondió; solo se aplicaron las comprobaciones por código.",
        "afirmaciones": afirmaciones,
        "capa1": c1,
        "modelo_verificador": proveedor,
        "mismo_modelo": mismo,
        "segundos": round((datetime.now() - inicio).total_seconds(), 1),
    }
    if error:
        out["motivo"] = "El verificador (capa 2) no respondió: " + error
    if original is not None:
        out["respuesta_corregida"] = respuesta_final
        out["respuesta_original"] = original
    return out


def verificacion_solo_codigo(respuesta, fragmentos, fecha_corte=None):
    """Solo la capa 1 (sin IA), para textos breves que se generan en lote: respuestas sugeridas de
    'Preparar mi reunión' y borradores de memoria. No promete 'Verificada': solo dice si las cifras calzan."""
    fragmentos = [f for f in (fragmentos or []) if isinstance(f, dict) and (f.get("content") or "").strip()]
    c1 = capa1(respuesta, fragmentos, fecha_corte)
    graves = [p for p in c1["problemas"] if p["gravedad"] in ("alta", "media")]
    hay_cifras = any(not x.pequeno and not x.anio for x in extraer_cifras(respuesta))
    if graves:
        estado, etiqueta, resumen = "con_reservas", "Revisar cifras", f"{len(graves)} alerta(s) en cifras, citas o plazos."
    elif hay_cifras:
        estado, etiqueta, resumen = "cifras_ok", "Cifras comprobadas", "Todas las cifras aparecen en el documento o se recalculan con él."
    else:
        estado, etiqueta, resumen = "no_verificable", "Sin cifras que comprobar", "El texto no trae cifras; revisa el fondo con el documento."
    return {"version": 1, "estado": estado, "etiqueta": etiqueta, "capas": ["codigo"], "resumen": resumen,
            "afirmaciones": [], "capa1": c1}


# ---------------------------------------------------------------------------
# Verificación de las señales del análisis (solo severidad alta o crítica)
# ---------------------------------------------------------------------------
def _prompt_verif_senales():
    return (
        f"{MARCA_VERIF_SENALES}\n"
        "Eres el VERIFICADOR de DIRECTA. Otros agentes levantaron estas señales graves (severidad alta o crítica) sobre "
        "un documento para el directorio. Comprueba cada una contra los FRAGMENTOS: ¿el hecho y las cifras que la "
        "sostienen aparecen en el documento? No juzgas si la severidad es la que tú pondrías, salvo que el documento "
        "la contradiga (por ejemplo, el tema ya tiene plan, responsable y fecha, o la cifra no supera el umbral).\n"
        "Revisores:\n" + _bloque_subagentes(list(SUBAGENTES)) + "\n\n"
        "Estados: respaldada, parcial, no_respaldada, contradicha (mismos criterios que para una respuesta).\n"
        "Responde ÚNICAMENTE con este JSON:\n"
        '{"senales":[{"id":"S1","estado":"respaldada|parcial|no_respaldada|contradicha","fragmento":"F1",'
        '"cita":"frase literal breve","nota":"explicación en una frase"}]}'
    )


def verificar_senales(resultados, fragmentos, fecha_corte=None):
    """Revisa las señales altas y críticas de un grupo de agentes y anota el resultado en cada una.
    Una señal contradicha por el documento baja a severidad 'baja' (se guarda la original).
    Modifica `resultados` en el lugar y devuelve un resumen."""
    fragmentos = [f for f in (fragmentos or []) if isinstance(f, dict) and (f.get("content") or "").strip()]
    objetivo = []
    for ag, r in (resultados or {}).items():
        for s in (r.get("senales") or []):
            if isinstance(s, dict) and s.get("severidad") in ("crítica", "alta"):
                objetivo.append((ag, s))
    resumen = {"revisadas": len(objetivo), "respaldadas": 0, "parciales": 0, "no_respaldadas": 0,
               "contradichas": 0, "no_verificables": 0, "modelo": None}
    if not objetivo:
        return resumen
    fc = fecha_corte or inferir_fecha_corte(fragmentos)
    for ag, s in objetivo:
        c1 = capa1(f"{s.get('titulo', '')}. {s.get('descripcion', '')}", fragmentos, fc)
        s["verificacion"] = {"estado": "no_verificable", "capa1": [p for p in c1["problemas"] if p["gravedad"] != "baja"]}
    lista = "\n".join(f"S{i} [{ag}] ({s.get('severidad')}) {s.get('titulo', '')}: {s.get('descripcion', '')}"
                      for i, (ag, s) in enumerate(objetivo, 1))
    usuario = (f"FECHA DE CORTE ESTIMADA: {fc.isoformat() if fc else 'no identificada'}\n\nSEÑALES A REVISAR:\n{lista}\n\n"
               f"FRAGMENTOS DEL DOCUMENTO:\n{_formatear_fragmentos(fragmentos)}\n\nDevuelve el JSON.")
    try:
        texto, proveedor = _ia.llamar_llm_verificador(_prompt_verif_senales(), usuario, temperatura=0.0,
                                                      max_tokens=1800, json_mode=True)
        data = _ia.parsear_json_respuesta(texto)
        resumen["modelo"] = proveedor
    except Exception as e:  # noqa: BLE001
        print(f"[VERIFICADOR] Señales sin verificar: {e}", flush=True)
        resumen["no_verificables"] = len(objetivo)
        resumen["error"] = str(e)[:200]
        return resumen
    por_id = {}
    for x in (data.get("senales") or []) if isinstance(data, dict) else []:
        if isinstance(x, dict):
            m = re.search(r"(\d+)", str(x.get("id") or ""))
            if m:
                por_id[int(m.group(1))] = x
    for i, (ag, s) in enumerate(objetivo, 1):
        x = por_id.get(i)
        if not x:
            resumen["no_verificables"] += 1
            continue
        estado = normalizar(x.get("estado")).replace(" ", "_")
        if estado not in ESTADOS:
            estado = "parcial"
        pagina = None
        m = re.search(r"F(\d+)", str(x.get("fragmento") or "").upper())
        if m and 1 <= int(m.group(1)) <= len(fragmentos):
            pagina = fragmentos[int(m.group(1)) - 1].get("page_number")
        s["verificacion"].update({"estado": estado, "cita": str(x.get("cita") or "")[:300],
                                  "nota": str(x.get("nota") or "")[:300], "pagina": pagina, "modelo": proveedor})
        if estado == "contradicha":
            s["severidad_original"] = s.get("severidad")
            s["severidad"] = "baja"
        clave = {"respaldada": "respaldadas", "parcial": "parciales", "no_respaldada": "no_respaldadas",
                 "contradicha": "contradichas"}[estado]
        resumen[clave] += 1
    return resumen


def resumen_por_agente(resultado):
    """Conteo de verificación de las señales de un agente (para mostrar en la app)."""
    c = {"revisadas": 0, "respaldadas": 0, "parciales": 0, "no_respaldadas": 0, "contradichas": 0, "no_verificables": 0}
    for s in (resultado or {}).get("senales") or []:
        v = s.get("verificacion") if isinstance(s, dict) else None
        if not v:
            continue
        c["revisadas"] += 1
        c[{"respaldada": "respaldadas", "parcial": "parciales", "no_respaldada": "no_respaldadas",
           "contradicha": "contradichas"}.get(v.get("estado"), "no_verificables")] += 1
    return c


def a_json(obj):
    return json.dumps(obj, ensure_ascii=False)
