# -*- coding: utf-8 -*-
"""Pruebas del verificador: capa de código (determinista) y pipeline completo con un LLM simulado."""
import pytest

import verificador as V

CHUNKS = [
    {"page_number": 12, "content": "Los ingresos operacionales del ejercicio 2024 alcanzaron US$ 2.134 millones, un 12,5% superior a los "
                                   "US$ 1.897 millones de 2023. El EBITDA fue de US$ 456 millones."},
    {"page_number": 13, "content": "La utilidad atribuible a los propietarios fue de MM$ 1.500, frente a MM$ 1.200 el año anterior. "
                                   "La dotación es de 1.234 colaboradores. El comité de directores sesionó 12 veces."},
]


def probs(res, tipo=None):
    return [p for p in res["problemas"] if tipo is None or p["tipo"] == tipo]


# ----------------------------------------------------------------------------- capa 1: código
def test_respuesta_correcta_no_genera_problemas():
    r = V.verificar_codigo("Los ingresos 2024 fueron US$ 2.134 millones (pág. 12), 12,5% más que en 2023. "
                           "El EBITDA fue de US$ 456 millones.", CHUNKS)
    assert r["ok"] and not r["cifras_sin_respaldo"] and r["cifras_revisadas"] >= 3


def test_detecta_cifra_cambiada():
    r = V.verificar_codigo("El EBITDA fue de US$ 465 millones.", CHUNKS)
    assert not r["ok"] and r["cifras_sin_respaldo"] == ["465"] and probs(r, "cifra_sin_respaldo")[0]["gravedad"] == "alta"


def test_detecta_porcentaje_inventado():
    r = V.verificar_codigo("Los ingresos crecieron 15% respecto de 2023.", CHUNKS)
    assert not r["ok"] and any("15" in c for c in r["cifras_sin_respaldo"])


def test_acepta_variacion_calculada():
    # (2134-1897)/1897*100 = 12,49
    r = V.verificar_codigo("La variación fue de 12,49% frente a 2023.", CHUNKS)
    assert r["ok"] and r["cifras_derivadas"] == 1


def test_acepta_diferencia_y_suma():
    r = V.verificar_codigo("La utilidad subió MM$ 300 (de MM$ 1.200 a MM$ 1.500).", CHUNKS)
    assert r["ok"], r["problemas"]
    r2 = V.verificar_codigo("En conjunto son MM$ 2.700.", CHUNKS)
    assert r2["ok"], r2["problemas"]


def test_formato_chileno_e_ingles_de_miles():
    assert V.verificar_codigo("Tiene 1.234 colaboradores.", CHUNKS)["ok"]
    assert V.verificar_codigo("Tiene 1,234 colaboradores.", CHUNKS)["ok"]
    assert not V.verificar_codigo("Tiene 1.243 colaboradores.", CHUNKS)["ok"]


def test_escala_mil_millones():
    r = V.verificar_codigo("La utilidad fue de 1,5 mil millones de pesos.", CHUNKS)
    assert r["ok"], r["problemas"]


def test_no_marca_conteos_chicos_ni_numeracion_ni_paginas():
    txt = "Hay 3 puntos clave y 2 riesgos.\n1. Primero (pág. 13)\n2) Segundo, ver páginas 12 y 13. Nota 5."
    r = V.verificar_codigo(txt, CHUNKS)
    assert r["ok"] and not r["cifras_sin_respaldo"]


def test_pagina_inexistente():
    r = V.verificar_codigo("Según la memoria (pág. 40) hubo 12 sesiones.", CHUNKS)
    assert r["paginas_invalidas"] == [40] and probs(r, "pagina_inexistente")
    assert V.verificar_codigo("Ver págs. 12-13.", CHUNKS)["paginas_invalidas"] == []


def test_cita_textual_literal_y_alterada():
    ok = V.verificar_codigo("Dice: «los ingresos operacionales del ejercicio 2024 alcanzaron US$ 2.134 millones».", CHUNKS)
    assert ok["ok"] and not ok["citas_no_literales"]
    mal = V.verificar_codigo("Dice: «los ingresos operacionales del ejercicio 2024 cayeron fuertemente respecto del año previo».", CHUNKS)
    assert not mal["ok"] and mal["citas_no_literales"]


def test_anio_ausente_es_baja():
    r = V.verificar_codigo("En 2019 el resultado fue distinto.", CHUNKS)
    assert probs(r, "periodo") and probs(r, "periodo")[0]["gravedad"] == "baja" and r["ok"]


def test_fechas_no_se_marcan():
    assert V.verificar_codigo("Al 31/12/2024 el directorio aprobó el plan.", CHUNKS)["ok"]


# ----------------------------------------------------------------------------- pipeline con LLM simulado
BUENO = {"veredicto": "correcta", "afirmaciones": [{"texto": "Ingresos US$ 2.134 millones", "estado": "respaldada",
                                                    "evidencia": "alcanzaron US$ 2.134 millones", "pagina": 12}], "problemas": []}
MALO = {"veredicto": "con_problemas", "afirmaciones": [{"texto": "EBITDA 465", "estado": "contradice", "evidencia": "El EBITDA fue de US$ 456 millones", "pagina": 12}],
        "problemas": [{"tipo": "cifra_incorrecta", "gravedad": "alta", "detalle": "EBITDA 465 vs 456 en pág. 12", "correccion": "US$ 456 millones"}]}
MEM_OK = {"veredicto": "coincide", "contrastes": [{"afirmacion": "Ingresos 2.134", "estado": "coincide", "memoria": "US$ 2.134 millones", "anio": 2024, "pagina": 30}], "problemas": []}
MEM_DIF = {"veredicto": "difiere", "contrastes": [{"afirmacion": "Dotación 1.234", "estado": "difiere", "memoria": "1.180 colaboradores", "anio": 2024, "pagina": 55,
                                                  "detalle": "La memoria dice 1.180"}],
           "problemas": [{"tipo": "difiere_memoria", "gravedad": "media", "detalle": "Dotación 1.234 vs 1.180 en la memoria 2024"}]}


class LLMFalso:
    def __init__(self, verificador=BUENO, memoria=MEM_OK, corrector="El EBITDA fue de US$ 456 millones (pág. 12).", falla=False):
        self.verificador, self.memoria, self.corrector, self.falla = verificador, memoria, corrector, falla
        self.llamadas = []

    def __call__(self, sistema, usuario, max_tokens, modelo, texto=False):
        self.llamadas.append(sistema[:30])
        if texto:
            return self.corrector
        if "VERIFICADOR DE MEMORIA" in sistema:
            return self.memoria
        if self.falla:
            raise RuntimeError("Gemini no respondió")
        v = self.verificador
        return v(usuario) if callable(v) else v


MEM_FN = lambda p, r: [{"content": "memoria", "memoria_nombre": "Memoria 2024", "memoria_anio": 2024, "page_number": 30}]


def correr(respuesta, llm, **kw):
    kw.setdefault("memoria_fn", MEM_FN)
    return V.verificar_respuesta("¿Cómo vamos?", respuesta, CHUNKS, llm=llm, **kw)


def test_pipeline_todo_bien_es_verificada():
    r = correr("Los ingresos 2024 fueron US$ 2.134 millones (pág. 12).", LLMFalso())
    assert r["sello"] == "verificada" and r["etiqueta"] == "Verificada" and r["puntaje"] == 100 and not r["corregida"]
    assert set(r["capas"]) == {"codigo", "llm", "memoria"} and r["capas"]["memoria"]["consultada"]


def test_si_la_segunda_verificacion_falla_nunca_es_verificada():
    r = correr("Los ingresos 2024 fueron US$ 2.134 millones (pág. 12).", LLMFalso(falla=True))
    assert r["sello"] == "con_reservas" and "no respondió" in r["resumen"]


def test_codigo_detecta_y_el_corrector_arregla():
    llm = LLMFalso()
    r = correr("El EBITDA fue de US$ 465 millones (pág. 12).", llm)
    assert r["corregida"] and r["texto_corregido"].startswith("El EBITDA fue de US$ 456") and r["texto_original"].startswith("El EBITDA fue de US$ 465")
    assert r["sello"] == "verificada"          # la versión corregida pasó las verificaciones otra vez
    assert any("CORRECTOR" in s for s in llm.llamadas)


def test_corrector_que_no_arregla_deja_con_reservas():
    llm = LLMFalso(corrector="El EBITDA fue de US$ 470 millones (pág. 12).")
    r = correr("El EBITDA fue de US$ 465 millones (pág. 12).", llm)
    assert r["sello"] == "con_reservas" and r["capas"]["codigo"]["cifras_sin_respaldo"]


def test_la_ia_verificadora_encuentra_lo_que_el_codigo_no():
    # la cifra existe en el documento (código OK) pero está atribuida al período equivocado
    mal = {"veredicto": "con_problemas", "afirmaciones": [],
           "problemas": [{"tipo": "periodo", "gravedad": "alta", "detalle": "US$ 1.897 millones es 2023, no 2024", "correccion": ""}]}
    r = correr("Los ingresos 2024 fueron US$ 1.897 millones (pág. 12).", LLMFalso(verificador=mal, corrector="Los ingresos de 2023 fueron US$ 1.897 millones (pág. 12)."), corregir=False)
    assert r["capas"]["codigo"]["ok"] and r["sello"] == "con_reservas" and r["puntaje"] <= 75


def test_memoria_que_difiere_baja_el_sello():
    r = correr("La dotación es de 1.234 colaboradores (pág. 13).", LLMFalso(memoria=MEM_DIF), corregir=False)
    assert r["sello"] == "con_reservas" and any(p["tipo"] == "difiere_memoria" for p in r["problemas"])


def test_sin_memorias_cargadas_no_bloquea():
    r = correr("Los ingresos 2024 fueron US$ 2.134 millones (pág. 12).", LLMFalso(), memoria_fn=lambda p, r: [])
    assert r["sello"] == "verificada" and r["capas"]["memoria"]["consultada"] is False


def test_sin_fragmentos_es_no_verificable():
    r = V.verificar_respuesta("¿?", "Algo.", [], llm=LLMFalso())
    assert r["sello"] == "no_verificable"


def test_modo_rapido_nunca_dice_verificada():
    r = V.verificar_respuesta("¿?", "Los ingresos fueron US$ 2.134 millones.", CHUNKS, modo="rapida", llm=LLMFalso())
    assert r["sello"] == "con_reservas" and "llm" not in r["capas"]


def test_subagentes_separados_corren_tres_y_combinan():
    llm = LLMFalso()
    r = correr("Los ingresos 2024 fueron US$ 2.134 millones (pág. 12).", llm, sub_modo="separado")
    assert set(r["capas"]["llm"]["subagentes"]) == {"cifras", "evidencia", "coherencia"}
    assert sum(1 for s in llm.llamadas if s.startswith("Eres un VERIFICADOR")) == 3


def test_subagente_que_falla_impide_verificada():
    estado = {"n": 0}

    def v(usuario):
        estado["n"] += 1
        if estado["n"] == 2:
            raise RuntimeError("boom")
        return BUENO
    r = correr("Los ingresos 2024 fueron US$ 2.134 millones (pág. 12).", LLMFalso(verificador=v), sub_modo="separado")
    assert r["sello"] != "verificada"


def test_afirmacion_contradice_se_convierte_en_problema():
    sucio = {"veredicto": "correcta", "afirmaciones": [{"texto": "Dotación de 2.000 personas", "estado": "contradice", "evidencia": "1.234", "pagina": 13}], "problemas": []}
    res = V._limpiar_resultado_llm(sucio)
    assert res["veredicto"] == "con_problemas" and res["problemas"][0]["gravedad"] == "alta"


def test_json_basura_de_la_ia_no_rompe():
    assert V._limpiar_resultado_llm("hola")["veredicto"] == "no_verificable"
    assert V._limpiar_resultado_llm({"veredicto": 5, "problemas": [None, 3]})["problemas"] == []


# ----------------------------------------------------------------------------- memoria de referencia
def test_detecta_documentos_de_memoria_anual():
    assert V.es_memoria_anual({"titulo": "CSAV_Memoria2023.pdf"})
    assert V.es_memoria_anual({"nombre_archivo": "2018_Memoria_Anual.pdf"})
    assert not V.es_memoria_anual({"titulo": "Informe de directorio octubre.pdf"})
    assert V.es_memoria_anual({"titulo": "Informe X", "tipo": "memoria"})


def test_memorias_de_referencia_ordena_por_anio_y_excluye_actual(monkeypatch):
    from db_memoria import FakeSupabase
    sb = FakeSupabase()
    for i, n in [("a", "CSAV_Memoria2022.pdf"), ("b", "CSAV-Memoria2024.pdf"), ("c", "Informe_directorio.pdf"), ("d", "CSAV_Memoria2023.pdf"), ("e", "Memoria_2019.pdf")]:
        sb.table("documentos").insert({"id": i, "titulo": n}).execute()
    r = V.memorias_de_referencia(sb, excluir_id="b", maximo=2)
    assert [m["id"] for m in r] == ["d", "a"]
    r2 = V.memorias_de_referencia(sb, metas={"c": {"tipo": "memoria", "periodo": "2025"}}, maximo=3)
    assert r2[0]["id"] == "c"


# ----------------------------------------------------------------------------- señales del análisis
def test_verificar_senales_rebaja_las_no_respaldadas():
    res = {"senales": [{"titulo": "EBITDA cayó 30%", "descripcion": "x", "severidad": "alta"},
                       {"titulo": "Rotación alta", "descripcion": "y", "severidad": "baja"},
                       {"titulo": "Covenant en riesgo", "descripcion": "z", "severidad": "crítica"}]}

    def llm(sistema, usuario, mt, modelo, texto=False):
        return {"senales": [{"indice": 0, "estado": "contradice", "motivo": "el EBITDA subió"}, {"indice": 2, "estado": "respaldada", "motivo": "ratio 3,9 vs límite 4"}]}
    out = V.verificar_senales(res, CHUNKS, llm=llm)
    assert out["senales"][0]["severidad"] == "baja" and out["senales"][0]["severidad_original"] == "alta"
    assert out["senales"][2]["severidad"] == "crítica" and out["senales"][2]["verificada"] == "respaldada"
    assert out["verificacion"]["senales_rebajadas"] == 1
