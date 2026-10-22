# -*- coding: utf-8 -*-
"""Pruebas de la capa Gemini (ia_config) contra un servidor falso."""
import importlib
import json
import math

import pytest


def test_no_quedan_rastros_de_groq_ni_nvidia():
    import ia_config
    fuente = open(ia_config.__file__, encoding="utf-8").read().lower()
    for palabra in ("groq", "nvidia", "nemotron", "integrate.api"):
        # solo se permite mencionarlos en el comentario que dice que fueron reemplazados
        apariciones = [l for l in fuente.splitlines() if palabra in l and "reemplaza" not in l]
        assert not apariciones, f"quedó '{palabra}' en ia_config.py: {apariciones[:2]}"


def test_chat_basico_y_cuerpo_de_la_solicitud(gemini):
    ia = gemini.ia
    t = ia.llamar_llm_chat("sistema X", "pregunta Y", temperatura=0.2, max_tokens=300)
    assert t == "ok"
    llamada = gemini.llamadas[0]
    assert llamada["ruta"] == "models/gemini-3.8-flash:generateContent"
    assert llamada["key"] == "llave-de-prueba-1"          # la llave va en el header, no en la URL
    cuerpo = llamada["cuerpo"]
    assert cuerpo["systemInstruction"]["parts"][0]["text"] == "sistema X"
    assert cuerpo["contents"][0]["parts"][0]["text"] == "pregunta Y"
    gc = cuerpo["generationConfig"]
    assert gc["thinkingConfig"] == {"thinkingLevel": "low"}
    assert gc["maxOutputTokens"] == 300 + ia.GEMINI_MARGEN_PENSAMIENTO   # el pensamiento cuenta dentro del tope
    assert "temperature" not in gc                          # Gemini 3: temperatura por defecto


def test_modo_json_y_parseo(gemini):
    ia = gemini.ia
    gemini.responder = lambda m, c: {"texto": '```json\n{"a": 1, "b": [1,2]}\n```'}
    d = ia.llamar_llm_json("s", "u")
    assert d == {"a": 1, "b": [1, 2]}
    assert gemini.llamadas[0]["cuerpo"]["generationConfig"]["responseMimeType"] == "application/json"


def test_json_cortado_se_repara(gemini):
    ia = gemini.ia
    gemini.responder = lambda m, c: {"texto": '{"resumen": "hola", "items": [{"x": 1}, {"x": 2}, {"x": ', "finish": "MAX_TOKENS"}
    d = ia.llamar_llm_json("s", "u")
    assert d["resumen"] == "hola" and d["items"][0] == {"x": 1}


def test_429_espera_y_reintenta(gemini):
    ia = gemini.ia
    gemini.respuestas = [(429, {"error": {"code": 429, "message": "quota", "status": "RESOURCE_EXHAUSTED",
                                          "details": [{"@type": "x/RetryInfo", "retryDelay": "0s"}]}})]
    assert ia.llamar_llm_chat("s", "u") == "ok"
    assert len(gemini.llamadas) == 2


def test_503_reintenta(gemini):
    ia = gemini.ia
    gemini.respuestas = [(503, {"error": {"code": 503, "message": "overloaded", "status": "UNAVAILABLE"}})]
    assert ia.llamar_llm_chat("s", "u") == "ok"


def test_modelo_inexistente_usa_respaldo(gemini):
    ia = gemini.ia
    gemini.modelos_validos = {"gemini-3.6-flash"}
    assert ia.llamar_llm_chat("s", "u") == "ok"
    rutas = [l["ruta"] for l in gemini.llamadas]
    assert rutas[0].startswith("models/gemini-3.8-flash") and rutas[1].startswith("models/gemini-3.6-flash")
    # el modelo caído se recuerda: la siguiente llamada ya no lo intenta
    gemini.llamadas.clear()
    ia.llamar_llm_chat("s", "u")
    assert gemini.llamadas[0]["ruta"].startswith("models/gemini-3.6-flash")


def test_modelo_rechaza_thinking_se_reenvia_sin_el(gemini):
    ia = gemini.ia
    gemini.respuestas = [(400, {"error": {"code": 400, "message": "Unsupported thinking level 'low' for this model",
                                          "status": "INVALID_ARGUMENT"}})]
    assert ia.llamar_llm_chat("s", "u") == "ok"
    assert "thinkingConfig" in gemini.llamadas[0]["cuerpo"]["generationConfig"]
    assert "thinkingConfig" not in gemini.llamadas[1]["cuerpo"]["generationConfig"]


def test_llave_invalida_pasa_a_la_siguiente(monkeypatch, gemini):
    monkeypatch.setenv("GEMINI_API_KEYS", "mala,buena")
    monkeypatch.setenv("GEMINI_API_KEY", "")
    ia = importlib.reload(gemini.ia)
    ia.ESPERA_MAXIMA = 0.05
    gemini.respuestas = [(400, {"error": {"code": 400, "message": "API key not valid. Please pass a valid API key.",
                                          "status": "INVALID_ARGUMENT"}})]
    assert ia.llamar_llm_chat("s", "u") == "ok"
    assert len({l["key"] for l in gemini.llamadas}) == 2


def test_contenido_vacio_es_error_claro(gemini):
    ia = gemini.ia
    gemini.responder = lambda m, c: {"texto": "", "finish": "MAX_TOKENS"}
    with pytest.raises(Exception) as e:
        ia.llamar_llm_chat("s", "u")
    assert "vac" in str(e.value).lower()


def test_sin_llave_el_error_dice_que_falta(monkeypatch, gemini):
    monkeypatch.setenv("GEMINI_API_KEY", "")
    ia = importlib.reload(gemini.ia)
    with pytest.raises(Exception) as e:
        ia.llamar_llm_chat("s", "u")
    assert "GEMINI_API_KEY" in str(e.value)


def test_embeddings_dimension_normalizacion_y_tipo(gemini):
    ia = gemini.ia
    vs = ia.generar_embeddings_batch(["ingresos del ejercicio 2024", "riesgo cibernetico"])
    assert len(vs) == 2 and all(len(v) == 2048 for v in vs)
    assert all(abs(math.sqrt(sum(x * x for x in v)) - 1) < 1e-6 for v in vs)
    rq = gemini.llamadas[0]["cuerpo"]["requests"][0]
    assert rq["taskType"] == "RETRIEVAL_DOCUMENT" and rq["outputDimensionality"] == 2048
    ia.generar_embedding_pregunta("¿Cuál fue el EBITDA?")
    assert gemini.llamadas[-1]["cuerpo"]["requests"][0]["taskType"] == "RETRIEVAL_QUERY"


def test_embeddings_de_textos_parecidos_son_cercanos(gemini):
    ia = gemini.ia
    a, b, c = ia.generar_embeddings_batch(["ingresos operacionales del año 2024 crecieron",
                                           "los ingresos operacionales crecieron en 2024",
                                           "plan de continuidad de ciberseguridad"])
    dot = lambda x, y: sum(p * q for p, q in zip(x, y))
    assert dot(a, b) > dot(a, c)


def test_embeddings_con_modelo_v2_no_manda_tasktype(monkeypatch, gemini):
    monkeypatch.setenv("EMBEDDING_MODEL", "gemini-embedding-2")
    ia = importlib.reload(gemini.ia)
    ia.generar_embedding_pregunta("hola")
    rq = gemini.llamadas[-1]["cuerpo"]["requests"][0]
    assert "taskType" not in rq and rq["content"]["parts"][0]["text"].startswith("task: search result | query:")


def test_embeddings_dimension_distinta_a_la_base_falla_claro(monkeypatch, gemini):
    ia = gemini.ia
    gemini.respuestas = [(200, {"embeddings": [{"values": [0.1] * 768}]})]
    with pytest.raises(Exception) as e:
        ia.generar_embeddings_batch(["x"])
    assert "dimensiones" in str(e.value)


def test_estado_no_filtra_la_llave(gemini):
    ia = gemini.ia
    s = json.dumps(ia.estado_ia())
    assert "llave-de-prueba" not in s and ia.estado_ia()["proveedor"] == "gemini"


def test_probar_proveedores(gemini):
    r = gemini.ia.probar_proveedores()
    assert r["gemini"]["ok"] and r["embeddings"]["ok"] and r["embeddings"]["dimension"] == 2048
