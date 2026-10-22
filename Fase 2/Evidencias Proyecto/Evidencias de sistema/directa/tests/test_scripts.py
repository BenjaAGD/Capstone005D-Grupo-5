# -*- coding: utf-8 -*-
"""Los scripts de apoyo (probar_gemini, reindexar_embeddings) funcionan contra el Gemini falso y una base en memoria."""
import importlib
import json
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _cargar(nombre):
    if RAIZ not in sys.path:
        sys.path.insert(0, RAIZ)
    sys.modules.pop(nombre, None)
    return importlib.import_module(nombre)


def test_probar_gemini_funciona_y_no_imprime_la_llave(gemini, capsys, monkeypatch):
    gemini.responder = lambda modelo, cuerpo: {"texto": json.dumps({"ok": True, "suma": 4})
                                               if (cuerpo.get("generationConfig") or {}).get("responseMimeType") == "application/json"
                                               else "Estoy listo para ayudar."}
    monkeypatch.setattr(sys, "argv", ["probar_gemini.py"])
    pg = _cargar("probar_gemini")
    assert pg.main() == 0
    salida = capsys.readouterr().out
    assert "[OK]" in salida and "2048 dimensiones" in salida
    assert "llave-de-prueba-1" not in salida                      # la llave nunca se imprime


def test_probar_gemini_sin_llave_avisa_y_sale(gemini, capsys, monkeypatch):
    monkeypatch.setattr(sys, "argv", ["probar_gemini.py"])
    pg = _cargar("probar_gemini")
    monkeypatch.setattr(pg.ia, "estado_ia", lambda: {"llaves_configuradas": 0, "modelo": "x", "modelos_respaldo": [],
                                                      "modelo_embedding": "e", "dimension_embedding": 2048})
    assert pg.main() == 2 and ".env" in capsys.readouterr().out


def test_reindexar_recalcula_todos_los_fragmentos_y_retoma(gemini, tmp_path, monkeypatch, capsys):
    from db_memoria import FakeSupabase
    sb = FakeSupabase()
    sb.table("documentos").insert({"id": "d1", "titulo": "X", "nombre_archivo": "x.pdf", "total_paginas": 1, "estado": "Listo"}).execute()
    viejo = [0.5] * 2048
    sb.table("document_chunks").insert([{"document_id": "d1", "content": f"Texto número {i} sobre ingresos y EBITDA.", "page_number": 1,
                                         "entity": None, "embedding": viejo} for i in range(5)]).execute()
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("SUPABASE_URL", "http://x")
    monkeypatch.setenv("SUPABASE_KEY", "k")
    import supabase as paquete
    monkeypatch.setattr(paquete, "create_client", lambda u, k: sb)
    monkeypatch.setattr(sys, "argv", ["reindexar_embeddings.py", "--lote", "2"])
    rx = _cargar("reindexar_embeddings")
    assert rx.main() == 0
    filas = sb.table("document_chunks").select("id,embedding").execute().data
    assert len(filas) == 5 and all(f["embedding"] != viejo and len(f["embedding"]) == 2048 for f in filas)
    assert os.path.exists("reindexar_avance.json")
    # segunda corrida: no queda nada pendiente
    assert rx.main() == 0 and "Total por recalcular: 0" in capsys.readouterr().out
