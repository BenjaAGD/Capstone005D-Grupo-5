# -*- coding: utf-8 -*-
"""
Servidor local que imita la API REST de Gemini (generateContent y batchEmbedContents).
Sirve para probar TODO el código de IA sin llave real y sin salir a internet.

Uso en pruebas:
    srv = FakeGemini().iniciar()
    os.environ["GEMINI_BASE_URL"] = srv.url
    ...
    srv.detener()

`srv.respuestas` es una cola opcional de (status, json) que se consumen en orden para simular
errores (429, 404, 400...). Si está vacía se usa `srv.responder(modelo, cuerpo)`, que por defecto
devuelve un JSON mínimo válido. Cada llamada queda en `srv.llamadas`.
"""
import hashlib
import json
import math
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def vector_demo(texto, dim):
    """Embedding determinista: bolsa de palabras con hashing. Textos parecidos -> vectores parecidos."""
    v = [0.0] * dim
    for palabra in re.findall(r"[a-záéíóúñ0-9]{3,}", (texto or "").lower()):
        h = int(hashlib.md5(palabra.encode()).hexdigest(), 16)
        v[h % dim] += 1.0
    n = math.sqrt(sum(x * x for x in v)) or 1.0
    return [x / n for x in v]


class FakeGemini:
    def __init__(self):
        self.llamadas = []          # [{"ruta":..., "cuerpo":..., "key":...}]
        self.respuestas = []        # cola de (status, dict) para simular fallas
        self.responder = self._por_defecto
        self.modelos_validos = None  # None = todos; o un set de nombres
        self._srv = None
        self._hilo = None
        self.url = ""
        self._lock = threading.Lock()

    # ---- comportamiento por defecto
    @staticmethod
    def _por_defecto(modelo, cuerpo):
        sistema = ((cuerpo.get("systemInstruction") or {}).get("parts") or [{}])[0].get("text", "")
        if (cuerpo.get("generationConfig") or {}).get("responseMimeType") == "application/json":
            return {"texto": json.dumps({"ok": True, "eco": sistema[:20]}), "finish": "STOP"}
        return {"texto": "ok", "finish": "STOP"}

    # ---- servidor
    def iniciar(self):
        fake = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a, **k):
                pass

            def _enviar(self, status, obj):
                data = json.dumps(obj).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                self._enviar(200, {"models": [{"name": "models/gemini-3.8-flash", "supportedGenerationMethods": ["generateContent"]}]})

            def do_POST(self):
                n = int(self.headers.get("Content-Length", "0"))
                cuerpo = json.loads(self.rfile.read(n) or b"{}")
                ruta = self.path.split("/v1beta/", 1)[-1]
                key = self.headers.get("x-goog-api-key", "")
                with fake._lock:
                    fake.llamadas.append({"ruta": ruta, "cuerpo": cuerpo, "key": key})
                    cola = fake.respuestas.pop(0) if fake.respuestas else None
                if cola is not None:
                    return self._enviar(cola[0], cola[1])
                modelo = ruta.split(":")[0].replace("models/", "")
                if fake.modelos_validos is not None and modelo not in fake.modelos_validos:
                    return self._enviar(404, {"error": {"code": 404, "message": f"models/{modelo} is not found", "status": "NOT_FOUND"}})
                if ruta.endswith(":batchEmbedContents"):
                    out = []
                    for rq in cuerpo.get("requests", []):
                        dim = int(rq.get("outputDimensionality") or 3072)
                        txt = ((rq.get("content") or {}).get("parts") or [{}])[0].get("text", "")
                        out.append({"values": vector_demo(txt, dim)})
                    return self._enviar(200, {"embeddings": out})
                if ruta.endswith(":generateContent"):
                    r = fake.responder(modelo, cuerpo)
                    if isinstance(r, tuple):
                        return self._enviar(r[0], r[1])
                    texto, finish = r["texto"], r.get("finish", "STOP")
                    return self._enviar(200, {
                        "candidates": [{"content": {"role": "model", "parts": [{"text": texto}]}, "finishReason": finish}],
                        "usageMetadata": {"promptTokenCount": 10, "candidatesTokenCount": 5, "thoughtsTokenCount": 0, "totalTokenCount": 15},
                    })
                self._enviar(404, {"error": {"code": 404, "message": "ruta desconocida", "status": "NOT_FOUND"}})

        self._srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.url = f"http://127.0.0.1:{self._srv.server_address[1]}/v1beta"
        self._hilo = threading.Thread(target=self._srv.serve_forever, daemon=True)
        self._hilo.start()
        return self

    def detener(self):
        if self._srv:
            self._srv.shutdown()
            self._srv.server_close()
