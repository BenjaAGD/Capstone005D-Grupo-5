# -*- coding: utf-8 -*-
"""
Prueba de punta a punta: la app completa (FastAPI) con Gemini FALSO y base de datos EN MEMORIA.
Recorre: subir un documento -> embeddings -> análisis de 14 agentes (con verificación de señales) -> chat con
ruteo automático -> doble verificación + corrección -> valoración 👍/👎 -> lecciones -> guía -> informe de mejora.
"""
import io
import json
import os
import re
import sys
import time

import pytest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TEXTO_INFORME = (
    "Informe de directorio del ejercicio 2024. Los ingresos operacionales alcanzaron US$ 2.134 millones, un 12,5% superior a los "
    "US$ 1.897 millones de 2023. El EBITDA fue de US$ 456 millones. La utilidad atribuible a los propietarios fue de MM$ 1.500, "
    "frente a MM$ 1.200 el año anterior. La dotación es de 1.234 colaboradores. El comité de directores sesionó 12 veces. "
    "Existe un hallazgo de ciberseguridad abierto desde hace 120 días sin fecha comprometida de remediación. "
) * 3

TEXTO_MEMORIA = ("Memoria Anual 2023. Los ingresos operacionales de 2023 alcanzaron US$ 1.897 millones. "
                 "La dotación al cierre de 2023 fue de 1.180 colaboradores. ") * 3


class Cerebro:
    """Responde como lo haría Gemini según el prompt que llega."""

    def __init__(self):
        self.respuesta_chat = "Los ingresos 2024 fueron US$ 2.134 millones (pág. 1)."
        self.corrector = "Los ingresos 2024 fueron US$ 2.134 millones (pág. 1)."
        self.veredicto_memoria = "coincide"
        self.sistemas = []          # todos los prompts de sistema vistos (para inspeccionar)

    def __call__(self, modelo, cuerpo):
        sistema = ((cuerpo.get("systemInstruction") or {}).get("parts") or [{}])[0].get("text", "")
        usuario = ((cuerpo.get("contents") or [{}])[0].get("parts") or [{}])[0].get("text", "")
        self.sistemas.append(sistema)
        js = (cuerpo.get("generationConfig") or {}).get("responseMimeType") == "application/json"
        if "VERIFICADOR DE MEMORIA ANUAL" in sistema:
            return {"texto": json.dumps({"veredicto": self.veredicto_memoria, "contrastes": [
                {"afirmacion": "ingresos", "estado": "coincide", "memoria": "US$ 1.897 millones", "anio": 2023, "pagina": 1, "detalle": ""}],
                "problemas": []}), "finish": "STOP"}
        if "auditar las SEÑALES" in sistema:
            return {"texto": json.dumps({"senales": [{"indice": 0, "estado": "sin_respaldo", "motivo": "no aparece", "severidad_sugerida": "baja"}]})}
        if "VERIFICADOR independiente" in sistema:
            return {"texto": json.dumps({"veredicto": "correcta", "afirmaciones": [
                {"texto": "ingresos 2024", "estado": "respaldada", "evidencia": "US$ 2.134 millones", "pagina": 1}], "problemas": []})}
        if "CORRECTOR" in sistema:
            return {"texto": self.corrector}
        if "mejorador" in sistema:
            return {"texto": json.dumps({"lecciones": [], "retirar": []})}
        if js and "PANEL de analistas" in sistema:
            claves = [k.lower() for k in re.findall(r"^### ([A-ZÁÉÍÓÚ]+) —", sistema, re.M)]
            out = {}
            for k in claves:
                out[k] = {"resumen_ejecutivo": f"Resumen del agente {k} con ingresos de US$ 2.134 millones.",
                          "hallazgos": [{"titulo": f"Hallazgo de {k}", "descripcion": "Descripción."}],
                          "senales": ([{"titulo": "Hallazgo de ciberseguridad abierto sin fecha", "descripcion": "120 días", "severidad": "alta"}]
                                      if k == "ciberseguridad" else []),
                          "omisiones": [], "preguntas": [{"pregunta": f"¿Qué pasa con {k}?"}], "recomendaciones": [], "score": 80}
            return {"texto": json.dumps(out)}
        if js:
            return {"texto": json.dumps({})}
        return {"texto": self.respuesta_chat}


@pytest.fixture()
def app(monkeypatch, tmp_path, gemini):
    monkeypatch.setenv("DIRECTA_DB", "memoria")
    monkeypatch.setenv("VERIFICACION_MODO", "completa")
    monkeypatch.setenv("VERIFICADOR_SUBAGENTES", "unificado")
    monkeypatch.setenv("UMBRAL_VALORACIONES", "2")
    monkeypatch.chdir(tmp_path)
    for nombre, mod in list(sys.modules.items()):
        ruta = getattr(mod, "__file__", None) or ""
        if ruta.startswith(RAIZ) and "tests" not in ruta and nombre != "ia_config":
            del sys.modules[nombre]
    cerebro = Cerebro()
    gemini.responder = cerebro
    import main
    monkeypatch.setattr(main, "PAUSA_ENTRE_GRUPOS", 0)
    monkeypatch.setattr(main, "PAUSA_ENTRE_LOTES", 0)
    from fastapi.testclient import TestClient
    cliente = TestClient(main.app)
    cliente.main, cliente.cerebro, cliente.gemini = main, cerebro, gemini
    return cliente


def sembrar(cliente, doc_id, nombre, texto, con_analisis=False):
    """Inserta un documento ya indexado (sin pasar por la subida)."""
    m, ia = cliente.main, cliente.gemini.ia
    m.supabase.table("documentos").insert({"id": doc_id, "titulo": nombre, "nombre_archivo": nombre, "total_paginas": 1, "estado": "Listo"}).execute()
    trozos = [t.strip() for t in re.split(r"(?<=\.)\s+", texto) if t.strip()]
    pegados = [" ".join(trozos[i:i + 3]) for i in range(0, len(trozos), 3)]
    embs = ia.generar_embeddings_batch(pegados)
    m.supabase.table("document_chunks").insert([
        {"document_id": doc_id, "content": c, "page_number": 1, "entity": None, "embedding": e} for c, e in zip(pegados, embs)]).execute()
    if con_analisis:
        m._guardar_analisis(doc_id, "financiero", {"resumen_ejecutivo": "Ingresos US$ 2.134 millones.", "hallazgos": [], "senales": [],
                                                    "omisiones": [], "preguntas": [], "recomendaciones": [], "score": 90})


def sse(respuesta):
    eventos = []
    for linea in respuesta.text.splitlines():
        if linea.startswith("data: ") and linea != "data: [DONE]":
            eventos.append(json.loads(linea[6:]))
    return eventos


# ------------------------------------------------------------------------------------------------ estado
def test_estado_no_filtra_secretos_y_describe_el_sistema(app):
    r = app.get("/api/estado").json()
    s = json.dumps(r)
    assert r["ok"] and r["ia"]["proveedor"] == "gemini" and r["base_de_datos"].startswith("memoria")
    assert "llave-de-prueba" not in s and r["verificacion"]["modo"] == "completa" and r["agentes"] == 14
    assert app.post("/api/ia/probar").json()["ok"]


def test_la_app_se_sirve_con_la_direccion_de_la_api(app):
    h = app.get("/app")
    assert h.status_code == 200 and "window.DIRECTA_API" in h.text
    assert app.get("/memoria.html").status_code == 200 and app.get("/no_existe.html").status_code == 404


def test_hay_14_agentes_orientados_al_gerente_general(app):
    ags = app.get("/api/agentes").json()["agentes"]
    assert len([a for a in ags if a["tipo"] != "general"]) == 14
    import agentes
    for k, a in agentes.AGENTES.items():
        assert "GERENTE GENERAL" in a["rol_chat"] and "GERENTE GENERAL" in a["rol_analisis"], k
        assert a.get("foco_gerente"), k


# ------------------------------------------------------------------------------------------------ chat
def test_chat_con_ruteo_automatico_y_doble_verificacion(app):
    sembrar(app, "d1", "informe.pdf", TEXTO_INFORME, con_analisis=True)
    sembrar(app, "m23", "Memoria_Anual_2023.pdf", TEXTO_MEMORIA)
    app.cerebro.respuesta_chat = "Los ingresos 2024 fueron US$ 2.134 millones (pág. 1)."
    r = app.post("/api/consultar/", data={"pregunta": "¿Cuánto fue el EBITDA y el margen de utilidad?", "document_id": "d1", "agente": "auto"}).json()
    assert r["ok"] and r["agente_key"] == "financiero" and r["agente_automatico"]
    v = r["verificacion"]
    assert v["sello"] == "verificada" and v["capas"]["codigo"]["ok"] and v["capas"]["llm"]["veredicto"] == "correcta"
    assert v["capas"]["memoria"]["consultada"] and "Memoria_Anual_2023.pdf" in v["capas"]["memoria"]["documentos"][0]
    assert r["interaccion_id"] and r["siguiente"]["pregunta"]["id"] == "financiero-1" or r["siguiente"]["pregunta"]["id"].startswith("financiero")


def test_respuesta_con_cifra_inventada_se_corrige_y_se_marca(app):
    sembrar(app, "d1", "informe.pdf", TEXTO_INFORME, con_analisis=True)
    app.cerebro.respuesta_chat = "Los ingresos 2024 fueron US$ 2.143 millones (pág. 1)."       # cifra cambiada
    r = app.post("/api/consultar/", data={"pregunta": "¿Cuáles fueron los ingresos?", "document_id": "d1", "agente": "financiero"}).json()
    assert r["verificacion"]["corregida"] and "2.134" in r["respuesta"] and "2.143" in r["respuesta_original"]
    assert r["verificacion"]["sello"] == "verificada"


def test_si_la_ia_verificadora_cae_el_sello_nunca_es_verificada(app):
    sembrar(app, "d1", "informe.pdf", TEXTO_INFORME)
    original = app.cerebro.__call__
    app.gemini.responder = lambda m, c: (500, {"error": {"code": 500, "message": "boom", "status": "INTERNAL"}}) if "VERIFICADOR" in (
        ((c.get("systemInstruction") or {}).get("parts") or [{}])[0].get("text", "")) else original(m, c)
    r = app.post("/api/consultar/", data={"pregunta": "¿Cuáles fueron los ingresos?", "document_id": "d1", "agente": "general"}).json()
    assert r["ok"] and r["verificacion"]["sello"] in ("con_reservas", "no_verificable")


def test_stream_emite_texto_verificando_y_resultado(app):
    sembrar(app, "d1", "informe.pdf", TEXTO_INFORME, con_analisis=True)
    r = app.post("/api/consultar-stream/", data={"pregunta": "¿Cuáles fueron los ingresos?", "document_id": "d1", "agente": "auto"})
    ev = sse(r)
    texto = "".join(e.get("chunk", "") for e in ev)
    assert "2.134" in texto
    assert any(e.get("verificando") for e in ev)
    final = [e for e in ev if "verificacion" in e][-1]
    assert final["verificacion"]["sello"] == "verificada" and final["interaccion_id"]
    assert r.text.strip().endswith("data: [DONE]")


def test_la_pregunta_general_va_al_asistente_general(app):
    sembrar(app, "d1", "informe.pdf", TEXTO_INFORME)
    r = app.post("/api/consultar/", data={"pregunta": "¿De qué trata este documento?", "document_id": "d1", "agente": "auto"}).json()
    assert r["agente_key"] == "general"


# ------------------------------------------------------------------------------------------------ aprendizaje
def test_los_agentes_aprenden_de_las_valoraciones_y_lo_usan_en_el_prompt(app):
    sembrar(app, "d1", "informe.pdf", TEXTO_INFORME, con_analisis=True)
    ids = []
    for i in range(2):
        r = app.post("/api/consultar/", data={"pregunta": f"¿Cuáles fueron los ingresos {i}?", "document_id": "d1", "agente": "financiero"}).json()
        ids.append(r["interaccion_id"])
    assert "APRENDIZAJES" not in app.cerebro.sistemas[0]
    a = app.post("/api/valorar/", data={"interaccion_id": ids[0], "valor": -1, "motivo": "muy_largo"}).json()
    assert a["ok"] and a["leccion_nueva"] is None
    b = app.post("/api/valorar/", data={"interaccion_id": ids[1], "valor": -1, "motivo": "muy_largo"}).json()
    assert b["leccion_nueva"]["ok"]
    est = app.get("/api/agentes/financiero/estado").json()
    assert est["version"] == 1 and len(est["lecciones"]) == 1
    app.cerebro.sistemas.clear()
    app.post("/api/consultar/", data={"pregunta": "¿Y el EBITDA?", "document_id": "d1", "agente": "financiero"})
    chat = [s for s in app.cerebro.sistemas if "Gerente General" in s and "APRENDIZAJES" in s]
    assert chat and "Sé más breve" in chat[0]
    # otro agente no se contagia
    assert app.get("/api/agentes/legal/estado").json()["lecciones"] == []
    # revertir
    rv = app.post("/api/agentes/financiero/revertir", data={"version": 0}).json()
    assert rv["ok"] and app.get("/api/agentes/financiero/estado").json()["lecciones"] == []


def test_guia_avanza_con_cada_pregunta_hecha(app):
    sembrar(app, "d1", "informe.pdf", TEXTO_INFORME, con_analisis=True)
    g = app.get("/api/guia/siguiente", params={"document_id": "d1", "agente": "financiero"}).json()
    assert g["progreso"]["hechas"] == 0 and g["pregunta"]["id"] == "financiero-1"
    app.post("/api/consultar/", data={"pregunta": g["pregunta"]["pregunta"], "document_id": "d1", "agente": "financiero",
                                       "pregunta_id": g["pregunta"]["id"]})
    g2 = app.get("/api/guia/siguiente", params={"document_id": "d1", "agente": "financiero"}).json()
    assert g2["progreso"]["hechas"] == 1 and g2["pregunta"]["id"] == "financiero-2"
    assert len(app.get("/api/guia/preguntas").json()["preguntas"]) == 15


def test_informe_de_mejora_en_md_y_pdf(app):
    sembrar(app, "d1", "informe.pdf", TEXTO_INFORME, con_analisis=True)
    app.post("/api/consultar/", data={"pregunta": "¿Ingresos?", "document_id": "d1", "agente": "financiero"})
    md = app.get("/api/mejora/informe")
    assert md.status_code == 200 and "Informe de mejora de los agentes" in md.text and "Agente Financiero" in md.text
    pdf = app.get("/api/mejora/informe", params={"formato": "pdf"})
    assert pdf.status_code == 200 and pdf.content[:4] == b"%PDF"


# ------------------------------------------------------------------------------------------------ subida completa
def _docx_bytes(texto):
    import docx
    d = docx.Document()
    for parrafo in re.split(r"(?<=\.)\s+(?=Existe|Informe)", texto):
        d.add_paragraph(parrafo)
    b = io.BytesIO()
    d.save(b)
    return b.getvalue()


def test_subir_documento_indexa_y_analiza_los_14_agentes(app):
    r = app.post("/api/subir-informe/", data={"document_id": "up1"},
                 files={"archivo": ("Memoria_Anual_2023.docx", _docx_bytes(TEXTO_INFORME),
                                    "application/vnd.openxmlformats-officedocument.wordprocessingml.document")}).json()
    assert r["ok"]
    for _ in range(300):
        p = app.get("/api/progreso/up1").json()
        if p.get("fase") == "listo" or p.get("estado") == "Error":
            break
        time.sleep(0.1)
    assert p["fase"] == "listo", p
    docs = app.get("/api/documentos").json()["documentos"]
    assert docs[0]["analisis_count"] == 14 and docs[0]["chunks"] > 0
    meta = app.get("/api/documentos/up1/meta").json()["meta"]
    assert meta["tipo"] == "memoria" and meta["periodo"] == "2023"
    an = app.get("/api/analisis-completos/up1").json()
    ciber = [an["analisis"]["ciberseguridad"]]
    # la señal alta sin respaldo fue rebajada por la verificación del análisis
    res = ciber[0].get("resultado") or ciber[0]
    assert res["senales"][0]["severidad"] == "baja" and res["senales"][0]["severidad_original"] == "alta"
    assert res["verificacion"]["senales_rebajadas"] == 1
    # cambiar el tipo a mano
    assert app.post("/api/documentos/up1/meta", data={"tipo": "informe", "periodo": "2023"}).json()["meta"]["tipo"] == "informe"
    assert not app.post("/api/documentos/up1/meta", data={"tipo": "otra"}).json()["ok"]
