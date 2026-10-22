# -*- coding: utf-8 -*-
"""
DIRECTA - Capa de IA.  SOLO Gemini (Google).  Reemplaza a Groq y NVIDIA.

Qué hace este archivo
  * Chat / análisis:  generateContent  (modelo GEMINI_MODEL, con modelos de respaldo).
  * Embeddings:       batchEmbedContents (EMBEDDING_MODEL) en EMBEDDING_DIM dimensiones.
  * JSON tolerante:   limpia ```json, repara respuestas cortadas, etc.

Variables de entorno (ver .env.example)
  GEMINI_API_KEY            la llave (obligatoria). Para rotar varias: GEMINI_API_KEYS=k1,k2,k3
  GEMINI_MODEL              por defecto gemini-3.8-flash
  GEMINI_MODEL_FALLBACKS    por defecto gemini-3.6-flash,gemini-3.5-flash-lite
  GEMINI_THINKING_LEVEL     low | medium | high   (por defecto low: respuestas más rápidas)
  EMBEDDING_MODEL           por defecto gemini-embedding-001
  EMBEDDING_DIM             por defecto 2048 (igual que la tabla document_chunks.embedding)

Los nombres públicos (llamar_llm_chat, llamar_llm_analisis, generar_embeddings_batch,
generar_embedding_pregunta, parsear_json_respuesta...) se mantienen iguales que en la v2,
así que main.py y los demás módulos no cambian su forma de llamar a la IA.
"""
import os
import re
import time
import json
import math
import threading
import unicodedata
import requests

from dotenv import load_dotenv

load_dotenv()


def _entero(nombre, defecto):
    try:
        return int(os.getenv(nombre, defecto))
    except (TypeError, ValueError):
        return int(defecto)


def _decimal(nombre, defecto):
    try:
        return float(os.getenv(nombre, defecto))
    except (TypeError, ValueError):
        return float(defecto)


# --------------------------------------------------------------------------- configuración
GEMINI_BASE_URL = os.getenv("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com/v1beta").rstrip("/")


def _cargar_keys():
    """GEMINI_API_KEYS (coma) + GEMINI_API_KEY + GEMINI_API_KEY_2..4, sin repetidas ni vacías."""
    crudas = []
    crudas += (os.getenv("GEMINI_API_KEYS") or "").split(",")
    crudas.append(os.getenv("GEMINI_API_KEY"))
    crudas += [os.getenv(f"GEMINI_API_KEY_{i}") for i in range(2, 5)]
    out = []
    for k in crudas:
        k = (k or "").strip()
        if k and k not in out:
            out.append(k)
    return out


GEMINI_API_KEYS = _cargar_keys()

GEMINI_MODEL = (os.getenv("GEMINI_MODEL") or "gemini-3.8-flash").strip()
GEMINI_MODELOS_RESPALDO = [m.strip() for m in (os.getenv("GEMINI_MODEL_FALLBACKS")
                                               or "gemini-3.6-flash,gemini-3.5-flash-lite").split(",") if m.strip()]
GEMINI_MODEL_VERIFICADOR = (os.getenv("GEMINI_MODEL_VERIFICADOR") or "").strip()   # opcional: otro modelo revisa al primero
GEMINI_THINKING_LEVEL = (os.getenv("GEMINI_THINKING_LEVEL") or "low").strip().lower()
# Los tokens de "pensamiento" cuentan dentro de maxOutputTokens: se suma un margen para que
# max_tokens siga significando "largo visible de la respuesta" (como en la v2).
GEMINI_MARGEN_PENSAMIENTO = _entero("GEMINI_MARGEN_PENSAMIENTO", "1024")
# Para los modelos Gemini 3 Google recomienda dejar la temperatura por defecto; se envía solo si se pide.
GEMINI_ENVIAR_TEMPERATURA = os.getenv("GEMINI_ENVIAR_TEMPERATURA", "").strip().lower() in ("1", "true", "si", "sí", "yes")

EMBEDDING_MODEL = (os.getenv("EMBEDDING_MODEL") or "gemini-embedding-001").strip()
EMBEDDING_DIM = _entero("EMBEDDING_DIM", "2048")

TAMANO_LOTE_EMBEDDING = _entero("TAMANO_LOTE_EMBEDDING", "50")
PAUSA_ENTRE_LOTES = _decimal("PAUSA_ENTRE_LOTES", "0.3")
EMBEDDING_TIMEOUT = _entero("EMBEDDING_TIMEOUT", "60")
CHAT_TIMEOUT = _entero("CHAT_TIMEOUT", "120")

MAX_REINTENTOS_EMBEDDING = 3
MAX_REINTENTOS_GEMINI = _entero("MAX_REINTENTOS_GEMINI", "4")
PAUSA_BASE = _decimal("PAUSA_BASE_GEMINI", "1.5")
ESPERA_MAXIMA = 30.0

LLM_DEADLINE_SEG = _decimal("LLM_DEADLINE_SEG", "240")
LOG_TOKENS = os.getenv("LOG_TOKENS", "1") != "0"
DEBUG_JSON = os.getenv("DEBUG_JSON", "0") == "1"

if not GEMINI_API_KEYS:
    print("[IA] Advertencia: falta GEMINI_API_KEY en el .env. La app arranca, pero ninguna llamada a la IA funcionará.",
          flush=True)

_session = requests.Session()
_lock = threading.Lock()
_contador_keys = 0
# Si un modelo devuelve 404 se recuerda para no volver a intentarlo en esta ejecución.
_modelos_caidos = set()


class ErrorGemini(Exception):
    """Error de la API de Gemini (con código HTTP y estado si los hay)."""

    def __init__(self, mensaje, http=None, estado=None, reintentar_en=None):
        super().__init__(mensaje)
        self.http = http
        self.estado = estado
        self.reintentar_en = reintentar_en


# --------------------------------------------------------------------------- utilidades
def normalizar_texto(texto: str) -> str:
    if not texto:
        return ""
    texto = texto.lower()
    texto = ''.join(
        c for c in unicodedata.normalize('NFD', texto)
        if unicodedata.category(c) != 'Mn'
    )
    texto = re.sub(r'\s+', ' ', texto).strip()
    return texto


def _revisar_plazo(inicio: float, etiqueta: str = "Gemini"):
    if LLM_DEADLINE_SEG > 0 and (time.time() - inicio) > LLM_DEADLINE_SEG:
        raise Exception(f"{etiqueta}: se superó el plazo máximo de {LLM_DEADLINE_SEG:.0f}s")


def _orden_keys():
    """Índices de las llaves, empezando por una distinta en cada llamada (reparte el cupo)."""
    global _contador_keys
    n = len(GEMINI_API_KEYS)
    if n == 0:
        raise ErrorGemini("Falta GEMINI_API_KEY en el .env (o en las variables de entorno del contenedor).")
    with _lock:
        inicio = _contador_keys % n
        _contador_keys += 1
    return [(inicio + j) % n for j in range(n)]


def _leer_error(r):
    """Devuelve (mensaje, estado, segundos_de_espera) a partir de la respuesta de error de Gemini."""
    mensaje, estado, espera = (r.text or "")[:400], None, None
    try:
        e = r.json().get("error") or {}
        mensaje = str(e.get("message") or mensaje)
        estado = e.get("status")
        for d in (e.get("details") or []):
            rd = d.get("retryDelay") if isinstance(d, dict) else None
            if rd:
                m = re.match(r"^\s*([\d.]+)\s*s", str(rd))
                if m:
                    espera = float(m.group(1))
    except Exception:
        pass
    h = None
    try:
        h = r.headers.get("retry-after")
        if h is not None and espera is None:
            espera = float(h)
    except (ValueError, TypeError, AttributeError):
        pass
    return mensaje, estado, espera


def _post_gemini(ruta, cuerpo, timeout, etiqueta="Gemini", modelo_ruta=None):
    """
    POST a la API de Gemini con rotación de llaves y reintentos.
    Devuelve el JSON de la respuesta. Lanza ErrorGemini con una causa clara si no se logra.
    Casos especiales que NO se reintentan igual:
      404 -> ErrorGemini(http=404): el llamador prueba otro modelo.
      400 por 'thinking' -> ErrorGemini(estado='THINKING'): el llamador reenvía sin thinkingConfig.
    """
    inicio = time.time()
    url = f"{GEMINI_BASE_URL}/{ruta}"
    orden = _orden_keys()
    ultimo = None
    for intento in range(1, MAX_REINTENTOS_GEMINI + 1):
        for pos, idx in enumerate(orden):
            _revisar_plazo(inicio, etiqueta)
            headers = {"x-goog-api-key": GEMINI_API_KEYS[idx], "Content-Type": "application/json"}
            try:
                r = _session.post(url, headers=headers, json=cuerpo, timeout=timeout)
            except requests.exceptions.Timeout:
                ultimo = ErrorGemini(f"{etiqueta}: tiempo de espera agotado")
                print(f"[GEMINI] Timeout (llave#{idx + 1}, intento {intento})", flush=True)
                time.sleep(min(PAUSA_BASE * intento, ESPERA_MAXIMA))
                continue
            except requests.exceptions.RequestException as e:
                ultimo = ErrorGemini(f"{etiqueta}: error de red: {e}")
                print(f"[GEMINI] Error de red: {e}", flush=True)
                time.sleep(min(PAUSA_BASE * intento, ESPERA_MAXIMA))
                continue

            if r.status_code == 200:
                try:
                    return r.json()
                except ValueError:
                    ultimo = ErrorGemini(f"{etiqueta}: respuesta que no es JSON")
                    continue

            mensaje, estado, espera = _leer_error(r)
            low = mensaje.lower()

            if r.status_code == 400 and ("thinking" in low or "thinkinglevel" in low or "thinking_level" in low):
                raise ErrorGemini(mensaje, http=400, estado="THINKING")
            if r.status_code == 400 and ("api key not valid" in low or "api_key_invalid" in low):
                print(f"[GEMINI] llave#{idx + 1} no es válida; se prueba la siguiente", flush=True)
                ultimo = ErrorGemini(f"La llave GEMINI_API_KEY no es válida: {mensaje}", http=400, estado=estado)
                continue
            if r.status_code in (401, 403):
                print(f"[GEMINI] llave#{idx + 1} rechazada (HTTP {r.status_code}); se prueba la siguiente", flush=True)
                ultimo = ErrorGemini(f"Gemini rechazó la llave o el permiso (HTTP {r.status_code}): {mensaje}",
                                     http=r.status_code, estado=estado)
                continue
            if r.status_code == 404:
                raise ErrorGemini(f"Modelo o recurso no encontrado: {mensaje}", http=404, estado=estado)
            if r.status_code == 429:
                sin_cupo_dia = any(x in low for x in ("per day", "perday", "daily"))
                ultimo = ErrorGemini(f"Gemini sin cupo (429): {mensaje[:200]}", http=429, estado=estado, reintentar_en=espera)
                if sin_cupo_dia and len(orden) > 1 and pos < len(orden) - 1:
                    print(f"[GEMINI] llave#{idx + 1} sin cupo diario; se prueba la siguiente", flush=True)
                    continue
                if sin_cupo_dia:
                    raise ultimo
                pausa = min(espera if espera is not None else PAUSA_BASE * intento * 2, ESPERA_MAXIMA)
                print(f"[GEMINI] 429, esperando {pausa:.1f}s (intento {intento}/{MAX_REINTENTOS_GEMINI})", flush=True)
                time.sleep(pausa)
                continue
            if r.status_code in (500, 502, 503, 504):
                ultimo = ErrorGemini(f"Gemini no disponible (HTTP {r.status_code}): {mensaje[:200]}",
                                     http=r.status_code, estado=estado)
                pausa = min(PAUSA_BASE * intento, ESPERA_MAXIMA)
                print(f"[GEMINI] HTTP {r.status_code}, esperando {pausa:.1f}s (intento {intento}/{MAX_REINTENTOS_GEMINI})", flush=True)
                time.sleep(pausa)
                continue
            raise ErrorGemini(f"Gemini error {r.status_code}: {mensaje[:300]}", http=r.status_code, estado=estado)

    raise ultimo or ErrorGemini(f"{etiqueta}: agotados los reintentos")


# --------------------------------------------------------------------------- embeddings
def _es_embedding_v2(modelo=None):
    return "embedding-2" in (modelo or EMBEDDING_MODEL).lower()


def _normalizar_vector(v):
    n = math.sqrt(sum(x * x for x in v))
    return [x / n for x in v] if n > 0 else v


def _preparar_texto_embedding(texto, tarea):
    """gemini-embedding-001 usa taskType; gemini-embedding-2 no lo admite y la tarea va en el texto."""
    t = (texto or "").strip() or "(vacío)"
    if _es_embedding_v2():
        return f"task: search result | query: {t}" if tarea == "pregunta" else f"title: none | text: {t}"
    return t


def generar_embeddings_batch(textos: list, max_intentos: int = MAX_REINTENTOS_EMBEDDING, tarea: str = "documento") -> list:
    """
    Devuelve un vector (lista de EMBEDDING_DIM floats, normalizado) por cada texto, en el mismo orden.
    tarea = "documento" (fragmentos que se guardan) o "pregunta" (consulta de búsqueda).
    """
    if not textos:
        return []
    v2 = _es_embedding_v2()
    tipo = "RETRIEVAL_QUERY" if tarea == "pregunta" else "RETRIEVAL_DOCUMENT"
    solicitudes = []
    for t in textos:
        s = {
            "model": f"models/{EMBEDDING_MODEL}",
            "content": {"parts": [{"text": _preparar_texto_embedding(t, tarea)}]},
            "outputDimensionality": EMBEDDING_DIM,
        }
        if not v2:
            s["taskType"] = tipo
        solicitudes.append(s)
    cuerpo = {"requests": solicitudes}
    ruta = f"models/{EMBEDDING_MODEL}:batchEmbedContents"

    ultimo = None
    for intento in range(1, max_intentos + 1):
        try:
            data = _post_gemini(ruta, cuerpo, EMBEDDING_TIMEOUT, etiqueta="Embeddings")
            vectores = [(e or {}).get("values") or [] for e in (data.get("embeddings") or [])]
            if len(vectores) != len(textos):
                raise ErrorGemini(f"Embeddings: se pidieron {len(textos)} y llegaron {len(vectores)}")
            for v in vectores:
                if len(v) != EMBEDDING_DIM:
                    raise ErrorGemini(
                        f"Embeddings: el modelo devolvió {len(v)} dimensiones y la base espera {EMBEDDING_DIM} "
                        "(revisa EMBEDDING_DIM y la columna document_chunks.embedding).", http=422)
            # con menos de 3072 dimensiones gemini-embedding-001 no entrega vectores normalizados
            return [_normalizar_vector(v) for v in vectores]
        except ErrorGemini as e:
            ultimo = e
            if e.http in (400, 401, 403, 404, 422):
                raise
            pausa = min(2 ** intento, ESPERA_MAXIMA)
            print(f"[EMBEDDING] {e}; esperando {pausa}s ({intento}/{max_intentos})", flush=True)
            time.sleep(pausa)
    raise Exception(f"Embedding falló tras {max_intentos} intentos. Último: {ultimo}")


def generar_embedding_documento(texto: str) -> list:
    return generar_embeddings_batch([texto], tarea="documento")[0]


def generar_embedding_pregunta(pregunta: str) -> list:
    limpia = " ".join((pregunta or "").split())
    return generar_embeddings_batch([limpia], tarea="pregunta")[0]


# --------------------------------------------------------------------------- generación de texto
def _config_pensamiento(modelo):
    """thinkingConfig según la familia del modelo; None = no enviar nada."""
    nivel = GEMINI_THINKING_LEVEL
    if not nivel or nivel in ("off", "none", "default"):
        return None
    m = modelo.lower()
    if m.startswith("gemini-3"):
        if nivel == "minimal" and "3.8" in m:      # 3.8 Flash no admite 'minimal'
            nivel = "low"
        if nivel not in ("minimal", "low", "medium", "high"):
            nivel = "low"
        return {"thinkingLevel": nivel}
    if m.startswith("gemini-2.5"):
        presupuesto = {"minimal": 0, "low": 1024, "medium": 4096, "high": 8192}.get(nivel, 1024)
        if "pro" in m:
            presupuesto = max(presupuesto, 128)
        return {"thinkingBudget": presupuesto}
    return None


def _cuerpo_generacion(modelo, prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode, con_pensamiento=True):
    gc = {"maxOutputTokens": int(max_tokens)}
    if json_mode:
        gc["responseMimeType"] = "application/json"
    solo_gemini3 = modelo.lower().startswith("gemini-3")
    if temperatura is not None and (GEMINI_ENVIAR_TEMPERATURA or not solo_gemini3):
        gc["temperature"] = float(temperatura)
    if con_pensamiento:
        pens = _config_pensamiento(modelo)
        if pens:
            gc["thinkingConfig"] = pens
            gc["maxOutputTokens"] = int(max_tokens) + GEMINI_MARGEN_PENSAMIENTO
    cuerpo = {
        "contents": [{"role": "user", "parts": [{"text": prompt_usuario}]}],
        "generationConfig": gc,
    }
    if prompt_sistema:
        cuerpo["systemInstruction"] = {"parts": [{"text": prompt_sistema}]}
    return cuerpo


def _extraer_texto(data):
    """(texto, finishReason). Lanza ErrorGemini si Gemini bloqueó la solicitud."""
    cands = data.get("candidates") or []
    if not cands:
        razon = (data.get("promptFeedback") or {}).get("blockReason")
        raise ErrorGemini(f"Gemini no devolvió respuesta{f' (bloqueada: {razon})' if razon else ''}.")
    c = cands[0] or {}
    partes = ((c.get("content") or {}).get("parts")) or []
    texto = "".join(p.get("text", "") for p in partes if isinstance(p, dict) and not p.get("thought"))
    return texto, c.get("finishReason")


def _log_tokens(modelo, data, finish):
    if not LOG_TOKENS:
        return
    u = data.get("usageMetadata") or {}
    print(f"[GEMINI] {modelo} tokens in={u.get('promptTokenCount', '?')} out={u.get('candidatesTokenCount', '?')} "
          f"pens={u.get('thoughtsTokenCount', 0)} finish={finish}", flush=True)


def _llamar_gemini(prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode, modelo=None):
    """Prueba el modelo pedido (o el principal) y luego los de respaldo. Devuelve (texto, modelo_usado)."""
    modelos = [m for m in [modelo or GEMINI_MODEL, GEMINI_MODEL] + GEMINI_MODELOS_RESPALDO if m]
    vistos, ordenados = set(), []
    for m in modelos:
        if m not in vistos:
            vistos.add(m)
            ordenados.append(m)
    candidatos = [m for m in ordenados if m not in _modelos_caidos] or ordenados
    errores = []
    for modelo in candidatos:
        con_pens = True
        for _ in range(2):   # 2.º intento: sin thinkingConfig si el modelo lo rechaza
            cuerpo = _cuerpo_generacion(modelo, prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode, con_pens)
            try:
                data = _post_gemini(f"models/{modelo}:generateContent", cuerpo, CHAT_TIMEOUT, etiqueta=f"Gemini {modelo}")
                texto, finish = _extraer_texto(data)
                _log_tokens(modelo, data, finish)
                if finish == "MAX_TOKENS":
                    print(f"[GEMINI] {modelo}: respuesta cortada por max_tokens.", flush=True)
                if finish in ("SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST") and not texto.strip():
                    raise ErrorGemini(f"Gemini bloqueó la respuesta ({finish}).")
                if not texto.strip():
                    raise ErrorGemini(f"Gemini devolvió contenido vacío (finishReason={finish}). "
                                      "Si pasa seguido, sube max_tokens o baja GEMINI_THINKING_LEVEL.")
                return texto, modelo
            except ErrorGemini as e:
                if e.estado == "THINKING" and con_pens:
                    print(f"[GEMINI] {modelo} no acepta thinkingConfig; se reintenta sin él.", flush=True)
                    con_pens = False
                    continue
                errores.append(f"{modelo}: {e}")
                if e.http == 404:
                    _modelos_caidos.add(modelo)
                    print(f"[GEMINI] El modelo {modelo} no existe para esta llave; se prueba el siguiente.", flush=True)
                break
            except Exception as e:
                errores.append(f"{modelo}: {e}")
                break
    raise Exception("Todos los modelos de Gemini fallaron. Detalles: " + " | ".join(errores))


def _llamar_llm_unificado(prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode, modelo=None):
    """
    Llama a Gemini. Con json_mode, una respuesta que no se puede convertir en JSON (ni reparándola)
    se pide una vez más; si sigue mal, se falla con un mensaje claro.
    Devuelve (texto, modelo_usado).
    """
    texto, usado = _llamar_gemini(prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode, modelo)
    if json_mode and _intentar_parsear(texto) is None:
        print("[LLM] La respuesta no es un JSON utilizable; se reintenta una vez con más margen.", flush=True)
        texto, usado = _llamar_gemini(prompt_sistema, prompt_usuario, temperatura, int(max_tokens * 1.5), json_mode, modelo)
        if _intentar_parsear(texto) is None:
            raise Exception("la respuesta no es un JSON utilizable (¿cortada por max_tokens?)")
    return texto, usado


def llamar_llm_chat(prompt_sistema, prompt_usuario, temperatura=0.2, max_tokens=1500, json_mode=False, modelo=None):
    return _llamar_llm_unificado(prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode, modelo)[0]


def llamar_llm_analisis(prompt_sistema, prompt_usuario, temperatura=0.1, max_tokens=2000, json_mode=True, modelo=None):
    return _llamar_llm_unificado(prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode, modelo)[0]


def llamar_llm(prompt_sistema, prompt_usuario, temperatura=0.2, max_tokens=1500, json_mode=False, modelo=None):
    return llamar_llm_chat(prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode, modelo)


def llamar_llm_json(prompt_sistema, prompt_usuario, temperatura=0.1, max_tokens=1800, modelo=None) -> dict:
    """Atajo: pide JSON y devuelve ya el dict."""
    return parsear_json_respuesta(llamar_llm_analisis(prompt_sistema, prompt_usuario, temperatura, max_tokens, True, modelo))


# --------------------------------------------------------------------------- JSON tolerante
def _limpiar_json(texto: str) -> str:
    """Extrae el primer objeto JSON del texto (quita ```json, prefijos y sobrantes)."""
    texto = texto.strip()
    if "```" in texto:
        match = re.search(r'```(?:json)?\s*(.*?)```', texto, re.DOTALL)
        if match:
            texto = match.group(1).strip()
    inicio = texto.find('{')
    if inicio == -1:
        return texto
    texto = texto[inicio:]
    try:
        _obj, fin = json.JSONDecoder().raw_decode(texto)
        return texto[:fin].strip()
    except json.JSONDecodeError:
        return texto.strip()


def _reparar_json_truncado(texto: str):
    """
    Intenta rescatar un objeto JSON cortado a la mitad (por ejemplo por
    max_tokens): vuelve al último punto donde el contenido estaba completo y
    cierra las llaves y corchetes abiertos. Nunca inventa valores: solo
    descarta lo que quedó incompleto. Devuelve un dict, o None.
    """
    if not texto:
        return None
    texto = texto.lstrip()
    if not texto.startswith("{"):
        return None

    pila = []              
    en_texto = False
    escapado = False
    candidatos = []        

    for i, c in enumerate(texto):
        if en_texto:
            if escapado:
                escapado = False
            elif c == "\\":
                escapado = True
            elif c == '"':
                en_texto = False
                candidatos.append((i + 1, "".join(reversed(pila))))
            continue
        if c == '"':
            en_texto = True
        elif c in "{[":
            pila.append("}" if c == "{" else "]")
        elif c in "}]":
            if not pila:
                break
            pila.pop()
            candidatos.append((i + 1, "".join(reversed(pila))))
        elif c.isdigit():
            if i + 1 < len(texto) and texto[i + 1] not in "0123456789.eE+-":
                candidatos.append((i + 1, "".join(reversed(pila))))
        elif c in "elu":                     
            candidatos.append((i + 1, "".join(reversed(pila))))

    for fin, cierres in reversed(candidatos[-800:]):
        trozo = texto[:fin].rstrip().rstrip(",")
        try:
            obj = json.loads(trozo + cierres)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict):
            return obj
    return None


def _intentar_parsear(texto):
    """Devuelve un dict si el texto es JSON (o JSON reparable); si no, None."""
    if not texto or not str(texto).strip():
        return None
    limpio = _limpiar_json(str(texto))
    try:
        obj = json.loads(limpio)
        return obj if isinstance(obj, dict) else None
    except json.JSONDecodeError:
        return _reparar_json_truncado(limpio)


def parsear_json_respuesta(texto: str) -> dict:
    if not texto:
        raise Exception("Respuesta vacía del LLM")
    limpio = _limpiar_json(texto)
    try:
        return json.loads(limpio)
    except json.JSONDecodeError as e:
        reparado = _reparar_json_truncado(limpio)
        if reparado is not None:
            print("[JSON] Respuesta incompleta: se reparó el JSON (puede faltar contenido al final).", flush=True)
            return reparado
        print(f"[JSON] Error parseando: {e}", flush=True)
        if DEBUG_JSON:
            print(f"[JSON] Primeros 800 chars: {limpio[:800]}", flush=True)
        raise Exception(f"No se pudo parsear JSON: {e}")


def calcular_score_promedio(scores: list) -> int:
    validos = [s for s in scores if isinstance(s, (int, float))]
    if not validos:
        return 0
    return round(sum(validos) / len(validos))




# --------------------------------------------------------------------------- estado y pruebas
def estado_ia() -> dict:
    """Configuración visible de la IA. Nunca incluye las llaves."""
    return {
        "proveedor": "gemini",
        "llaves_configuradas": len(GEMINI_API_KEYS),
        "modelo": GEMINI_MODEL,
        "modelo_verificador": GEMINI_MODEL_VERIFICADOR or GEMINI_MODEL,
        "modelos_respaldo": GEMINI_MODELOS_RESPALDO,
        "nivel_pensamiento": GEMINI_THINKING_LEVEL,
        "modelo_embedding": EMBEDDING_MODEL,
        "dimension_embedding": EMBEDDING_DIM,
        "plazo_maximo_seg": LLM_DEADLINE_SEG,
    }


def estado_keys() -> dict:
    """Alias de estado_ia() (nombre de la v2)."""
    return estado_ia()


def listar_modelos_disponibles() -> list:
    """Modelos que la llave puede usar (GET /models). Útil para elegir GEMINI_MODEL."""
    idx = _orden_keys()[0]
    r = _session.get(f"{GEMINI_BASE_URL}/models", headers={"x-goog-api-key": GEMINI_API_KEYS[idx]},
                     params={"pageSize": 200}, timeout=30)
    if r.status_code != 200:
        raise ErrorGemini(_leer_error(r)[0], http=r.status_code)
    out = []
    for m in (r.json().get("models") or []):
        out.append({"nombre": str(m.get("name", "")).replace("models/", ""),
                    "metodos": m.get("supportedGenerationMethods") or []})
    return out


def probar_proveedores() -> dict:
    """Prueba el chat y los embeddings de Gemini con un prompt mínimo."""
    resultado = {"gemini": None, "embeddings": None}
    try:
        t, modelo = _llamar_gemini("Eres un asistente.", "Responde solo: ok", 0.0, 50, False)
        resultado["gemini"] = {"ok": True, "modelo": modelo, "respuesta": (t or "").strip()[:50]}
    except Exception as e:
        resultado["gemini"] = {"ok": False, "error": str(e)[:400]}
    try:
        v = generar_embedding_pregunta("prueba de embeddings")
        resultado["embeddings"] = {"ok": True, "modelo": EMBEDDING_MODEL, "dimension": len(v)}
    except Exception as e:
        resultado["embeddings"] = {"ok": False, "error": str(e)[:400]}
    return resultado
