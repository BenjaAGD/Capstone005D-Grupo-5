# -*- coding: utf-8 -*-
"""
Pruebas estáticas del frontend (sin navegador): el JavaScript de cada página es sintácticamente válido y
todas las rutas /api/... que llama existen de verdad en el backend (evita botones que apuntan a nada).
"""
import os
import re
import shutil
import subprocess

import pytest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGINAS = ["index.html", "memoria.html"]


def _leer(nombre):
    with open(os.path.join(RAIZ, nombre), encoding="utf-8") as f:
        return f.read()


def _scripts(html):
    return [s for s in re.findall(r"<script(?![^>]*src)[^>]*>(.*?)</script>", html, re.S) if len(s) > 500]


@pytest.mark.skipif(not shutil.which("node"), reason="node no está instalado")
@pytest.mark.parametrize("pagina", PAGINAS)
def test_el_javascript_es_valido(pagina, tmp_path):
    for i, js in enumerate(_scripts(_leer(pagina))):
        ruta = tmp_path / f"{pagina}_{i}.js"
        ruta.write_text(js, encoding="utf-8")
        r = subprocess.run(["node", "--check", str(ruta)], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr[:600]


def _rutas_del_backend():
    rutas = set()
    for nombre in os.listdir(RAIZ):
        if nombre.endswith(".py"):
            with open(os.path.join(RAIZ, nombre), encoding="utf-8") as f:
                rutas |= set(re.findall(r'@(?:app|router)\.(?:get|post|put|delete)\("([^"]+)"', f.read()))
    return rutas


def _como_patron(ruta):
    return re.compile("^" + re.sub(r"\\\{[^}]+\\\}", r"[^/]+", re.escape(ruta)) + "$")


@pytest.mark.parametrize("pagina", PAGINAS)
def test_cada_ruta_que_llama_el_frontend_existe(pagina):
    backend = [_como_patron(r) for r in _rutas_del_backend()]
    llamadas = set()
    for js in _scripts(_leer(pagina)):
        for m in re.finditer(r'''["'`](/api/[^"'`]*)''', js):
            ruta = re.sub(r"\$\{[^{}]*\}", "X", m.group(1)).split("?")[0]
            llamadas.add(ruta)
    assert llamadas, "no se encontraron llamadas /api en " + pagina
    faltan = []
    for ruta in sorted(llamadas):
        candidatas = {ruta, ruta.rstrip("/"), ruta + "/", ruta.rstrip("X").rstrip("/") + "/X"}
        if not any(p.match(c) for p in backend for c in candidatas):
            faltan.append(ruta)
    assert not faltan, f"{pagina} llama a rutas que no existen: {faltan}"


def test_el_chat_arranca_en_modo_automatico_y_usa_el_origen_del_servidor():
    html = _leer("index.html")
    assert 'agenteActual: "auto"' in html
    assert "location.origin" in html


def test_el_sello_y_la_valoracion_estan_conectados_al_chat():
    html = _leer("index.html")
    for pieza in ("selloHtml(m)", "valoracionHtml(m)", "detalleVerificacionHtml", "texto_corregido", "verificando",
                  "preguntarSiguiente", "prepararReunion", "vMejora"):
        assert pieza in html, pieza
