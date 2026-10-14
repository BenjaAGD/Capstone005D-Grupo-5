"""
==============================================================================
DIRECTA v2 — Configuración central de IA
==============================================================================
- Embeddings: NVIDIA NIM (nvidia/nemotron-3-embed-1b)
- Chat/Análisis primario: Groq con rotación de hasta 4 API keys
- Chat/Análisis fallback: NVIDIA NIM (mismo NVIDIA_API_KEY que embeddings)

Los modelos de razonamiento de NVIDIA (Nemotron 3 Super, etc.) tienen
enable_thinking=false para que respondan directo en content en vez de
gastar tokens en reasoning_content.

Cambios de esta versión (la API pública no cambia: mismas funciones y firmas):
- Groq: si una key es rechazada (401/403) se salta a la siguiente en vez de
  abortar todo el proveedor; en 429 se respeta "retry-after" y se salta la key
  si el cupo agotado es diario; el punto de partida de las keys rota entre
  llamadas para repartir la carga.
- Groq (gpt-oss): reasoning_effort configurable (por defecto "low") para que el
  razonamiento no consuma el presupuesto de max_tokens. Si el modelo no lo
  acepta, se reintenta sin él.
- Groq: una respuesta vacía ya no se da por buena (cae al otro proveedor) y un
  400 json_validate_failed intenta rescatar failed_generation.
- NVIDIA: ya no se usa reasoning_content como si fuera la respuesta.
- JSON: parseo robusto (llaves dentro de textos) y reparación de respuestas
  cortadas por max_tokens; si la respuesta de un proveedor no es un JSON
  utilizable, se prueba con el otro.
- Plazo máximo por proveedor (LLM_DEADLINE_SEG) para no quedar esperando
  decenas de minutos.
==============================================================================
"""

import os
import re
import time
import json
import threading
import unicodedata
import requests

from dotenv import load_dotenv

load_dotenv()


# ============================================================================
# API KEYS
# ============================================================================
NVIDIA_API_KEY = os.getenv("NVIDIA_API_KEY")

GROQ_API_KEYS = [
    os.getenv("GROQ_API_KEY_1"),
    os.getenv("GROQ_API_KEY_2"),
    os.getenv("GROQ_API_KEY_3"),
    os.getenv("GROQ_API_KEY_4"),
]
GROQ_API_KEYS = [k for k in GROQ_API_KEYS if k]

_legacy = os.getenv("GROQ_API_KEY")
if _legacy and _legacy not in GROQ_API_KEYS:
    GROQ_API_KEYS.append(_legacy)

if not NVIDIA_API_KEY:
    raise Exception("Falta NVIDIA_API_KEY en el .env")
if not GROQ_API_KEYS:
    print("[IA] Advertencia: no hay GROQ_API_KEYS. Se usará solo NVIDIA NIM.", flush=True)


# ============================================================================
# MODELOS
# ============================================================================
EMBEDDING_MODEL = "nvidia/nemotron-3-embed-1b"
NVIDIA_BASE_URL = "https://integrate.api.nvidia.com/v1"

# Modelo NVIDIA NIM vigente (octubre 2026)
NVIDIA_CHAT_MODEL = os.getenv(
    "NVIDIA_CHAT_MODEL",
    "nvidia/nemotron-3-super-120b-a12b"
)

GROQ_BASE_URL = "https://api.groq.com/openai/v1"

# Modelo Groq vigente (reemplazo oficial de llama-3.3-70b-versatile)
GROQ_MODEL = os.getenv("GROQ_MODEL", "openai/gpt-oss-120b")

LLM_PRIMARY = os.getenv("LLM_PRIMARY", "groq").lower().strip()
if LLM_PRIMARY not in ("groq", "nvidia"):
    print(f"[IA] LLM_PRIMARY='{LLM_PRIMARY}' no es válido (groq|nvidia). Se usará 'groq'.", flush=True)
    LLM_PRIMARY = "groq"


# ============================================================================
# PARÁMETROS
# ============================================================================
TAMANO_LOTE_EMBEDDING = 50
PAUSA_ENTRE_LOTES = 0.3
EMBEDDING_TIMEOUT = 60
CHAT_TIMEOUT = 120

MAX_REINTENTOS_EMBEDDING = 3
MAX_CICLOS_GROQ = 2
MAX_REINTENTOS_NVIDIA = 3

PAUSA_BASE_ENTRE_KEYS = 1.5
PAUSA_BASE_ENTRE_CICLOS = 4
PAUSA_BASE_NVIDIA = 2.0

# Plazo máximo (segundos) que puede gastar CADA proveedor en una llamada,
# sumando reintentos y pausas. 0 = sin límite.
LLM_DEADLINE_SEG = float(os.getenv("LLM_DEADLINE_SEG", "240"))

# Esfuerzo de razonamiento para modelos gpt-oss en Groq ("low" | "medium" |
# "high"). Un valor bajo deja más tokens para la respuesta. Vacío = no enviarlo.
GROQ_REASONING_EFFORT = os.getenv("GROQ_REASONING_EFFORT", "low").strip().lower()

LOG_TOKENS = True

# Si es "1", al fallar el parseo se imprimen hasta 800 caracteres de la
# respuesta (puede incluir contenido confidencial del documento).
DEBUG_JSON = os.getenv("DEBUG_JSON", "0") == "1"


# ============================================================================
# SESIÓN HTTP
# ============================================================================
_session = requests.Session()


# ============================================================================
# NORMALIZACIÓN
# ============================================================================
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


# ============================================================================
# EMBEDDINGS (NVIDIA NIM)
# ============================================================================
def generar_embeddings_batch(textos: list, max_intentos: int = MAX_REINTENTOS_EMBEDDING) -> list:
    if not textos:
        return []

    url = f"{NVIDIA_BASE_URL}/embeddings"
    headers = {
        "Authorization": f"Bearer {NVIDIA_API_KEY}",
        "Content-Type": "application/json",
    }
    body = {"model": EMBEDDING_MODEL, "input": textos}

    ultimo_error = None
    for intento in range(1, max_intentos + 1):
        try:
            r = _session.post(url, headers=headers, json=body, timeout=EMBEDDING_TIMEOUT)
            if r.status_code == 200:
                data = r.json()["data"]
                data = sorted(data, key=lambda x: x["index"])
                return [d["embedding"] for d in data]

            if r.status_code in (429, 500, 502, 503, 504):
                espera = 2 ** intento
                print(f"[EMBEDDING] HTTP {r.status_code}, esperando {espera}s ({intento}/{max_intentos})", flush=True)
                time.sleep(espera)
                ultimo_error = f"HTTP {r.status_code}"
                continue

            raise Exception(f"Embedding error {r.status_code}: {r.text[:200]}")

        except requests.exceptions.Timeout:
            espera = 2 ** intento
            print(f"[EMBEDDING] Timeout, esperando {espera}s", flush=True)
            time.sleep(espera)
            ultimo_error = "Timeout"

        except requests.exceptions.RequestException as e:
            espera = 2 ** intento
            print(f"[EMBEDDING] Error red: {e}", flush=True)
            time.sleep(espera)
            ultimo_error = str(e)

    raise Exception(f"Embedding falló tras {max_intentos} intentos. Último: {ultimo_error}")


def generar_embedding_documento(texto: str) -> list:
    return generar_embeddings_batch([texto])[0]


def generar_embedding_pregunta(pregunta: str) -> list:
    pregunta_limpia = normalizar_texto(pregunta)
    return generar_embeddings_batch([pregunta_limpia])[0]


# ============================================================================
# UTILIDADES DE LLAMADAS
# ============================================================================
def _log_tokens(provider: str, key_index, r_json):
    if not LOG_TOKENS:
        return
    usage = r_json.get("usage", {}) or {}
    prompt_t = usage.get("prompt_tokens", "?")
    completion_t = usage.get("completion_tokens", "?")
    total = usage.get("total_tokens", "?")
    try:
        finish = (r_json.get("choices") or [{}])[0].get("finish_reason", "?")
    except (AttributeError, IndexError, TypeError):
        finish = "?"
    print(f"[{provider}] key#{key_index} tokens in={prompt_t} out={completion_t} total={total} finish={finish}", flush=True)


def _leer_respuesta(r_json):
    """Devuelve (content, razonamiento, finish_reason) de una respuesta tipo OpenAI."""
    choice = (r_json.get("choices") or [{}])[0]
    msg = choice.get("message") or {}
    razonamiento = msg.get("reasoning_content") or msg.get("reasoning")
    return msg.get("content"), razonamiento, choice.get("finish_reason")


def _revisar_plazo(inicio: float, proveedor: str):
    if LLM_DEADLINE_SEG > 0 and (time.time() - inicio) > LLM_DEADLINE_SEG:
        raise Exception(f"{proveedor}: se superó el plazo máximo de {LLM_DEADLINE_SEG:.0f}s")


def _espera_retry_after(r, defecto: float, maximo: float = 30.0) -> float:
    """Usa la cabecera retry-after si viene; si no, el valor por defecto."""
    try:
        valor = r.headers.get("retry-after")
        if valor is not None:
            return max(0.5, min(float(valor), maximo))
    except (ValueError, TypeError, AttributeError):
        pass
    return defecto


_groq_lock = threading.Lock()
_groq_contador = 0


def _orden_keys_groq() -> list:
    """Índices de las keys, empezando por una distinta en cada llamada."""
    global _groq_contador
    n = len(GROQ_API_KEYS)
    with _groq_lock:
        inicio = _groq_contador % n
        _groq_contador += 1
    return [(inicio + j) % n for j in range(n)]


# ============================================================================
# PROVEEDOR: GROQ
# ============================================================================
def _llamar_groq(prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode):
    if not GROQ_API_KEYS:
        raise Exception("No hay GROQ_API_KEYS configuradas")

    inicio = time.time()
    url = f"{GROQ_BASE_URL}/chat/completions"
    body = {
        "model": GROQ_MODEL,
        "messages": [
            {"role": "system", "content": prompt_sistema},
            {"role": "user", "content": prompt_usuario},
        ],
        "temperature": temperatura,
        "max_tokens": max_tokens,
    }
    if GROQ_REASONING_EFFORT and "gpt-oss" in GROQ_MODEL.lower():
        body["reasoning_effort"] = GROQ_REASONING_EFFORT
    if json_mode:
        body["response_format"] = {"type": "json_object"}

    orden = _orden_keys_groq()
    ultimo_error = None

    for ciclo in range(MAX_CICLOS_GROQ):
        if ciclo > 0:
            espera = PAUSA_BASE_ENTRE_CICLOS * (2 ** (ciclo - 1))
            print(f"[GROQ] Ciclo {ciclo+1}/{MAX_CICLOS_GROQ} — esperando {espera}s", flush=True)
            time.sleep(espera)

        for pos, idx in enumerate(orden):
            _revisar_plazo(inicio, "Groq")
            num = idx + 1
            headers = {
                "Authorization": f"Bearer {GROQ_API_KEYS[idx]}",
                "Content-Type": "application/json",
            }
            try:
                r = _session.post(url, headers=headers, json=body, timeout=CHAT_TIMEOUT)

                # Si el modelo no acepta reasoning_effort, se reintenta una vez sin él.
                if (r.status_code == 400 and "reasoning_effort" in body
                        and "reasoning" in r.text.lower()
                        and "json_validate_failed" not in r.text.lower()):
                    print("[GROQ] El modelo no acepta reasoning_effort. Reintentando sin él.", flush=True)
                    body.pop("reasoning_effort", None)
                    r = _session.post(url, headers=headers, json=body, timeout=CHAT_TIMEOUT)

                if r.status_code == 200:
                    if pos > 0 or ciclo > 0:
                        print(f"[GROQ] OK con key#{num} (ciclo {ciclo+1})", flush=True)
                    r_json = r.json()
                    _log_tokens("GROQ", num, r_json)
                    contenido, _razonamiento, finish = _leer_respuesta(r_json)
                    if finish == "length":
                        print("[GROQ] Respuesta cortada por max_tokens (finish_reason=length).", flush=True)
                    if not contenido or not str(contenido).strip():
                        raise Exception(
                            f"Groq devolvió contenido vacío (finish_reason={finish}). "
                            "Probablemente el razonamiento consumió max_tokens."
                        )
                    return contenido

                if r.status_code in (401, 403):
                    print(f"[GROQ] key#{num} rechazada (HTTP {r.status_code}); se prueba la siguiente", flush=True)
                    ultimo_error = f"{r.status_code} en key#{num}"
                    continue

                if r.status_code == 429:
                    cuerpo = r.text.lower()
                    if "per day" in cuerpo or "tpd" in cuerpo or "rpd" in cuerpo:
                        print(f"[GROQ] key#{num} sin cupo diario; se prueba la siguiente", flush=True)
                        ultimo_error = f"cupo diario agotado en key#{num}"
                        continue
                    espera = _espera_retry_after(r, PAUSA_BASE_ENTRE_KEYS * (pos + 1))
                    print(f"[GROQ] key#{num} 429, esperando {espera:.1f}s", flush=True)
                    ultimo_error = f"429 en key#{num}"
                    time.sleep(espera)
                    continue

                if r.status_code in (500, 502, 503, 504):
                    espera = PAUSA_BASE_ENTRE_KEYS * (pos + 1)
                    print(f"[GROQ] key#{num} HTTP {r.status_code}, esperando {espera:.1f}s", flush=True)
                    ultimo_error = f"{r.status_code} en key#{num}"
                    time.sleep(espera)
                    continue

                if r.status_code == 413:
                    raise Exception(f"Groq 413 (request too large): {r.text[:300]}")

                if r.status_code == 400 and "json_validate_failed" in r.text:
                    # Groq entrega lo que alcanzó a generar; si es reparable se aprovecha.
                    falla = None
                    try:
                        falla = r.json()["error"].get("failed_generation")
                    except Exception:
                        pass
                    if falla and _intentar_parsear(falla) is not None:
                        print("[GROQ] json_validate_failed: se rescata failed_generation", flush=True)
                        return falla
                    raise Exception(f"Groq 400 json_validate_failed: {r.text[:300]}")

                raise Exception(f"Groq error fatal {r.status_code}: {r.text[:300]}")

            except requests.exceptions.Timeout:
                espera = PAUSA_BASE_ENTRE_KEYS * (pos + 1)
                print(f"[GROQ] Timeout key#{num}", flush=True)
                ultimo_error = f"Timeout key#{num}"
                time.sleep(espera)
                continue

            except requests.exceptions.RequestException as e:
                espera = PAUSA_BASE_ENTRE_KEYS * (pos + 1)
                print(f"[GROQ] Error red key#{num}: {e}", flush=True)
                ultimo_error = f"Red key#{num}"
                time.sleep(espera)
                continue

    raise Exception(f"Groq agotado tras {MAX_CICLOS_GROQ} ciclos. Último: {ultimo_error}")


# ============================================================================
# PROVEEDOR: NVIDIA NIM (fallback)
# ============================================================================
def _llamar_nvidia(prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode):
    inicio = time.time()
    url = f"{NVIDIA_BASE_URL}/chat/completions"
    body = {
        "model": NVIDIA_CHAT_MODEL,
        "messages": [
            {"role": "system", "content": prompt_sistema},
            {"role": "user", "content": prompt_usuario},
        ],
        "temperature": temperatura,
        "max_tokens": max_tokens,
        # FIX: desactivar razonamiento para que responda directo en content
        "chat_template_kwargs": {"enable_thinking": False},
    }
    if json_mode:
        body["response_format"] = {"type": "json_object"}

    headers = {
        "Authorization": f"Bearer {NVIDIA_API_KEY}",
        "Content-Type": "application/json",
    }

    ultimo_error = None

    for intento in range(1, MAX_REINTENTOS_NVIDIA + 1):
        _revisar_plazo(inicio, "NVIDIA")
        try:
            r = _session.post(url, headers=headers, json=body, timeout=CHAT_TIMEOUT)

            if r.status_code == 200:
                r_json = r.json()
                _log_tokens("NVIDIA", 1, r_json)

                contenido, razonamiento, finish = _leer_respuesta(r_json)
                if finish == "length":
                    print("[NVIDIA] Respuesta cortada por max_tokens (finish_reason=length).", flush=True)

                # El razonamiento NO es la respuesta: usarlo rompe el JSON del
                # análisis y mostraría el "pensamiento" del modelo en el chat.
                if not contenido or not str(contenido).strip():
                    raise Exception(
                        "NVIDIA devolvió respuesta vacía. "
                        f"finish_reason={finish}. "
                        f"{'Solo trajo razonamiento. ' if razonamiento else ''}"
                        "Verifica que enable_thinking=false funciona."
                    )

                return contenido

            # Algunos modelos NIM no soportan response_format json_object
            if json_mode and r.status_code == 400 and "response_format" in r.text:
                print("[NVIDIA] json_object no soportado. Reintentando sin él.", flush=True)
                body.pop("response_format", None)
                json_mode = False
                continue

            if r.status_code in (429, 500, 502, 503, 504):
                espera = _espera_retry_after(r, PAUSA_BASE_NVIDIA * intento) if r.status_code == 429 \
                    else PAUSA_BASE_NVIDIA * intento
                print(f"[NVIDIA] HTTP {r.status_code}, esperando {espera:.1f}s ({intento}/{MAX_REINTENTOS_NVIDIA})", flush=True)
                time.sleep(espera)
                ultimo_error = f"HTTP {r.status_code}"
                continue

            if r.status_code in (404, 410):
                raise Exception(
                    f"NVIDIA: modelo '{NVIDIA_CHAT_MODEL}' no existe o deprecado. "
                    f"Detalle: {r.text[:200]}"
                )

            raise Exception(f"NVIDIA error {r.status_code}: {r.text[:300]}")

        except requests.exceptions.Timeout:
            espera = PAUSA_BASE_NVIDIA * intento
            print(f"[NVIDIA] Timeout, esperando {espera:.1f}s", flush=True)
            time.sleep(espera)
            ultimo_error = "Timeout"

        except requests.exceptions.RequestException as e:
            espera = PAUSA_BASE_NVIDIA * intento
            print(f"[NVIDIA] Error red: {e}", flush=True)
            time.sleep(espera)
            ultimo_error = str(e)

    raise Exception(f"NVIDIA falló tras {MAX_REINTENTOS_NVIDIA} intentos. Último: {ultimo_error}")


# ============================================================================
# ORQUESTADOR
# ============================================================================
def _llamar_llm_unificado(prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode):
    """
    Intenta con el proveedor primario, y si falla, cae al secundario.
    Con json_mode, una respuesta que no se puede convertir en JSON (ni
    reparándola) cuenta como falla y se prueba con el otro proveedor.
    Devuelve (respuesta_texto, proveedor_usado).
    """
    if LLM_PRIMARY == "nvidia":
        orden = [("nvidia", _llamar_nvidia), ("groq", _llamar_groq)]
    else:
        orden = [("groq", _llamar_groq), ("nvidia", _llamar_nvidia)]

    errores = []
    for nombre, fn in orden:
        try:
            texto = fn(prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode)
            if json_mode and _intentar_parsear(texto) is None:
                raise Exception("la respuesta no es un JSON utilizable (¿cortada por max_tokens?)")
            return texto, nombre
        except Exception as e:
            errores.append(f"{nombre}: {e}")
            print(f"[LLM] {nombre} falló: {e}", flush=True)
            continue

    raise Exception(f"Todos los proveedores LLM fallaron. Detalles: {' | '.join(errores)}")


# ============================================================================
# API PÚBLICA
# ============================================================================
def llamar_llm_chat(prompt_sistema, prompt_usuario, temperatura=0.2, max_tokens=1500, json_mode=False):
    texto, proveedor = _llamar_llm_unificado(
        prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode
    )
    if proveedor != LLM_PRIMARY:
        print(f"[LLM] Usado fallback: {proveedor}", flush=True)
    return texto


def llamar_llm_analisis(prompt_sistema, prompt_usuario, temperatura=0.1, max_tokens=2000, json_mode=True):
    texto, proveedor = _llamar_llm_unificado(
        prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode
    )
    if proveedor != LLM_PRIMARY:
        print(f"[LLM] Usado fallback: {proveedor}", flush=True)
    return texto


def llamar_llm(prompt_sistema, prompt_usuario, temperatura=0.2, max_tokens=1500, json_mode=False):
    return llamar_llm_chat(prompt_sistema, prompt_usuario, temperatura, max_tokens, json_mode)


# ============================================================================
# PARSEO Y VALIDACIÓN DE JSON
# ============================================================================
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
        # raw_decode entiende los textos entre comillas (una "}" dentro de un
        # texto ya no corta el objeto).
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

    pila = []              # cierres pendientes, en orden de apertura
    en_texto = False
    escapado = False
    candidatos = []        # (posición_fin, cierres) donde se puede cortar

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
            # Un número solo se considera completo si el texto sigue después de él;
            # si el corte cae justo al final, podría ser "61" cortado como "6".
            if i + 1 < len(texto) and texto[i + 1] not in "0123456789.eE+-":
                candidatos.append((i + 1, "".join(reversed(pila))))
        elif c in "elu":                     # fin posible de true/false/null
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


# ============================================================================
# UTILIDADES
# ============================================================================
def calcular_score_promedio(scores: list) -> int:
    validos = [s for s in scores if isinstance(s, (int, float))]
    if not validos:
        return 0
    return round(sum(validos) / len(validos))


def estado_keys() -> dict:
    return {
        "n_keys_groq": len(GROQ_API_KEYS),
        "nvidia_configurada": bool(NVIDIA_API_KEY),
        "modelo_groq": GROQ_MODEL,
        "modelo_nvidia_chat": NVIDIA_CHAT_MODEL,
        "modelo_embedding": EMBEDDING_MODEL,
        "llm_primary": LLM_PRIMARY,
        "groq_reasoning_effort": GROQ_REASONING_EFFORT or None,
        "llm_deadline_seg": LLM_DEADLINE_SEG,
    }


def probar_proveedores() -> dict:
    """Prueba ambos proveedores LLM con un prompt mínimo."""
    resultado = {"groq": None, "nvidia": None}

    try:
        r = _llamar_groq("Eres un asistente.", "Responde solo: ok", 0.0, 300, False)
        resultado["groq"] = {"ok": True, "respuesta": (r or "")[:50]}
    except Exception as e:
        resultado["groq"] = {"ok": False, "error": str(e)[:300]}

    try:
        r = _llamar_nvidia("Eres un asistente.", "Responde solo: ok", 0.0, 300, False)
        resultado["nvidia"] = {"ok": True, "respuesta": (r or "")[:50]}
    except Exception as e:
        resultado["nvidia"] = {"ok": False, "error": str(e)[:300]}

    return resultado