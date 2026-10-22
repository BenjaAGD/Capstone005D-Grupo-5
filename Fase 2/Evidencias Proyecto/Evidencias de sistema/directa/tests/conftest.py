# -*- coding: utf-8 -*-
import importlib
import os
import sys

import pytest

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
for p in (RAIZ, AQUI):
    if p not in sys.path:
        sys.path.insert(0, p)

from fake_gemini import FakeGemini  # noqa: E402


@pytest.fixture()
def gemini(monkeypatch, tmp_path):
    """Servidor Gemini falso + ia_config recargado apuntando a él (sin esperas largas)."""
    srv = FakeGemini().iniciar()
    monkeypatch.setenv("GEMINI_BASE_URL", srv.url)
    monkeypatch.setenv("GEMINI_API_KEY", "llave-de-prueba-1")
    monkeypatch.delenv("GEMINI_API_KEYS", raising=False)
    for i in (2, 3, 4):
        monkeypatch.delenv(f"GEMINI_API_KEY_{i}", raising=False)
    monkeypatch.setenv("GEMINI_MODEL", "gemini-3.8-flash")
    monkeypatch.setenv("GEMINI_MODEL_FALLBACKS", "gemini-3.6-flash,gemini-3.5-flash-lite")
    monkeypatch.setenv("PAUSA_BASE_GEMINI", "0.01")
    monkeypatch.setenv("LOG_TOKENS", "0")
    monkeypatch.setenv("DIRECTA_DATOS_DIR", str(tmp_path / "datos"))
    import ia_config
    importlib.reload(ia_config)
    ia_config.ESPERA_MAXIMA = 0.05
    srv.ia = ia_config
    yield srv
    srv.detener()
