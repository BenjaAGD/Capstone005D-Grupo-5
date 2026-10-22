# -*- coding: utf-8 -*-
"""«Preparar mi reunión»: selección por código de señales y preguntas, respuestas verificadas, carpeta y PDF."""
import time

from test_e2e import app, sembrar, TEXTO_INFORME  # noqa: F401

import reunion


def _analisis():
    return {
        "ciberseguridad": {"senales": [{"titulo": "Hallazgo de ciberseguridad abierto sin fecha de remediación", "descripcion": "120 días", "severidad": "alta"}],
                           "preguntas": [{"pregunta": "¿Cuándo se remediará el hallazgo de ciberseguridad abierto?"},
                                         "¿Qué plan de continuidad existe ante un ataque informático?"]},
        "financiero": {"senales": [{"titulo": "Hallazgo de ciberseguridad abierto sin fecha de remediación", "descripcion": "duplicada", "severidad": "media"},
                                   {"titulo": "Caída del margen operacional respecto del año anterior", "severidad": "crítica"}],
                       "preguntas": [{"pregunta": "¿Qué explica la variación del EBITDA frente al año anterior?"}, {"pregunta": "corta"}]},
        "legal": {"senales": [], "preguntas": ["¿Qué contingencias legales podrían afectar el resultado del próximo año?"]},
    }


def test_las_senales_salen_ordenadas_y_sin_repetidos():
    s, total = reunion.senales_prioritarias(_analisis())
    assert total == 3 and [x["severidad"] for x in s] == ["crítica", "alta"]          # la duplicada se fusiona
    assert s[1].get("tambien_en") == ["Financiero"]


def test_las_preguntas_se_reparten_entre_areas_empezando_por_las_mas_graves():
    qs = reunion.preguntas_probables(_analisis(), 3)
    assert [q["agente"] for q in qs] == ["financiero", "ciberseguridad", "legal"]     # una por área, la de señal crítica primero
    assert all(len(q["pregunta"]) > 12 for q in qs)                                    # «corta» se descarta
    assert len(reunion.preguntas_probables(_analisis(), 10)) == 4


def test_el_resumen_sale_de_datos_no_de_la_ia():
    c = reunion.armar_carpeta("d", "Informe", _analisis(), lambda p, a: {"respuesta": "Respuesta.", "verificacion": {"sello": "verificada", "puntaje": 100}})
    assert "3 señales" in c["texto_resumen"] and "2 de ellas son críticas o altas" in c["texto_resumen"]
    assert c["resumen"]["por_sello"]["verificada"] == 4


def test_una_pregunta_que_falla_no_tumba_la_carpeta():
    def r(p, a):
        if "EBITDA" in p:
            raise RuntimeError("se cayó")
        return {"respuesta": "Ok.", "verificacion": {"sello": "con_reservas", "problemas": [{"tipo": "unidad", "gravedad": "media", "detalle": "x"}]}}
    c = reunion.armar_carpeta("d", "Informe", _analisis(), r, max_preguntas=3)
    sellos = {q["pregunta"][:12]: q["sello"] for q in c["preguntas"]}
    assert sellos["¿Qué explica"] == "no_verificable" and len(c["reservas"]) == 3


def test_preparar_la_reunion_de_punta_a_punta(app):
    sembrar(app, "d1", "Informe_Directorio_2024.docx", TEXTO_INFORME, con_analisis=True)
    for k, res in _analisis().items():
        app.main._guardar_analisis("d1", k, {"resumen_ejecutivo": "r", "hallazgos": [], "omisiones": [], "recomendaciones": [], "score": 70, **res})
    job = app.post("/api/reunion/preparar", data={"document_id": "d1", "preguntas": "3"}).json()["job_id"]
    for _ in range(120):
        e = app.get(f"/api/reunion/estado/{job}").json()
        if e["estado"] != "corriendo":
            break
        time.sleep(0.25)
    assert e["estado"] == "listo" and e["hechas"] == e["total"] == 3, e
    c = e["carpeta"]
    assert len(c["preguntas"]) == 3 and all(q["respuesta"] for q in c["preguntas"])
    assert all(q["sello"] in ("verificada", "con_reservas", "no_verificable") for q in c["preguntas"])
    assert c["preguntas"][0]["agente_usado"] == "financiero"
    # queda guardada y se puede bajar el PDF
    assert app.get("/api/reunion/ultima/d1").json()["carpeta"]["document_id"] == "d1"
    pdf = app.get("/api/reunion/pdf/d1")
    assert pdf.status_code == 200 and pdf.content[:4] == b"%PDF"


def test_sin_analisis_pide_correr_a_los_agentes_y_sin_carpeta_no_hay_pdf(app):
    sembrar(app, "d2", "Otro.docx", TEXTO_INFORME)
    job = app.post("/api/reunion/preparar", data={"document_id": "d2"}).json()["job_id"]
    for _ in range(40):
        e = app.get(f"/api/reunion/estado/{job}").json()
        if e["estado"] != "corriendo":
            break
        time.sleep(0.1)
    assert e["estado"] == "error" and "análisis" in e["mensaje"]
    assert app.get("/api/reunion/pdf/d2").status_code == 404 and app.get("/api/reunion/estado/zzz").status_code == 404
