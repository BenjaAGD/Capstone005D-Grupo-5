# -*- coding: utf-8 -*-
"""Pruebas de seguridad.py con un Supabase falso (sin llaves ni red).
Ejecutar desde backend/:   python -m unittest test_seguridad -v
"""
import threading
import unittest
from types import SimpleNamespace

from fastapi import FastAPI, Form, Request
from fastapi.testclient import TestClient

import seguridad

EMPRESA_A = "76123456-0"
EMPRESA_B = "99999999-9"

# token → (id, empresa, correo confirmado)
TOKENS = {
    "tok-a": ("u-a", EMPRESA_A, True),
    "tok-b": ("u-b", EMPRESA_B, True),
    "tok-sin-confirmar": ("u-c", EMPRESA_A, False),
    "tok-sin-empresa": ("u-d", "", True),
}
DOCUMENTOS = [
    {"id": "doc-a", "empresa_rut": EMPRESA_A},
    {"id": "doc-b", "empresa_rut": EMPRESA_B},
]


class ConsultaFalsa:
    def __init__(self, tabla, filas, registro):
        self.tabla, self.filas, self.registro = tabla, filas, registro
        self.filtros = []
        self.accion = "select"

    def select(self, *a, **k): self.accion = "select"; return self
    def insert(self, fila, *a, **k): self.accion = "insert"; self.registro.append(("insert", self.tabla, fila)); return self
    def update(self, *a, **k): self.accion = "update"; return self
    def delete(self, *a, **k): self.accion = "delete"; return self
    def limit(self, *a, **k): return self
    def order(self, *a, **k): return self
    def eq(self, col, val): self.filtros.append(("eq", col, val)); return self
    def in_(self, col, vals): self.filtros.append(("in", col, list(vals))); return self

    def execute(self):
        if self.accion == "insert":
            return SimpleNamespace(data=[])
        self.registro.append((self.accion, self.tabla, list(self.filtros)))
        filas = list(self.filas.get(self.tabla, []))
        for tipo, col, val in self.filtros:
            if tipo == "eq":
                filas = [f for f in filas if f.get(col) == val]
            else:
                filas = [f for f in filas if f.get(col) in val]
        return SimpleNamespace(data=filas)


class SupabaseFalso:
    def __init__(self):
        self.registro = []
        self.filas = {
            "documentos": DOCUMENTOS,
            "empresas_autorizadas": [{"rut": EMPRESA_A, "activa": True}, {"rut": EMPRESA_B, "activa": True}],
        }
        self.auth = SimpleNamespace(get_user=self._get_user)

    def _get_user(self, token):
        if token not in TOKENS:
            raise Exception("jwt inválido")
        uid, empresa, confirmado = TOKENS[token]
        return SimpleNamespace(user=SimpleNamespace(
            id=uid, email_confirmed_at="2026-01-01" if confirmado else None,
            app_metadata={"rut_empresa": empresa} if empresa else {}))

    def table(self, nombre):
        return ConsultaFalsa(nombre, self.filas, self.registro)


def crear_app(real):
    cliente = seguridad.ClienteEmpresa(real)
    app = FastAPI()
    app.add_middleware(seguridad.AutenticacionDirecta, obtener_cliente=lambda: cliente.real)

    @app.get("/")
    def raiz(): return {"ok": True}

    @app.get("/api/documentos")
    def listar():
        return {"docs": [d["id"] for d in cliente.table("documentos").select("id").execute().data]}

    @app.get("/api/dashboard/{document_id}")
    def dash(document_id: str): return {"id": document_id}

    @app.get("/api/dashboard-comparar/{a}/{b}")
    def comparar(a: str, b: str): return {"ok": True}

    @app.get("/api/memoria/cobertura")
    def cobertura(docs: str = ""): return {"docs": docs}

    @app.post("/api/consultar/")
    def consultar(request: Request, document_id: str = Form(...), pregunta: str = Form(...)):
        return {"id": document_id, "pregunta": pregunta, "empresa": request.state.empresa_rut}

    @app.post("/api/memoria/pdf")
    async def memoria_pdf(request: Request):
        return {"cuerpo": await request.json()}

    @app.post("/api/subir-informe/")
    def subir(document_id: str = Form(...)):
        cliente.table("documentos").insert({"id": document_id, "titulo": "x"}).execute()
        hilo_vio = []
        t = threading.Thread(target=lambda: hilo_vio.append(seguridad.EMPRESA_ACTUAL.get()))
        t.start()
        t.join()
        return {"hilo_empresa": hilo_vio[0]}

    return app, cliente


class PruebasSeguridad(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        seguridad.propagar_contexto_en_hilos()

    def setUp(self):
        self.real = SupabaseFalso()
        self.app, self.cliente = crear_app(self.real)
        self.http = TestClient(self.app)

    def con(self, token):
        return {"Authorization": f"Bearer {token}"}

    # ---- sesión ----
    def test_raiz_es_publica(self):
        self.assertEqual(self.http.get("/").status_code, 200)

    def test_sin_token_401(self):
        r = self.http.get("/api/documentos")
        self.assertEqual(r.status_code, 401)
        self.assertFalse(r.json()["ok"])

    def test_token_invalido_401(self):
        self.assertEqual(self.http.get("/api/documentos", headers=self.con("falso")).status_code, 401)

    def test_correo_sin_confirmar_403(self):
        self.assertEqual(self.http.get("/api/documentos", headers=self.con("tok-sin-confirmar")).status_code, 403)

    def test_cuenta_sin_empresa_403(self):
        self.assertEqual(self.http.get("/api/documentos", headers=self.con("tok-sin-empresa")).status_code, 403)

    def test_options_pasa_sin_token(self):
        r = self.http.options("/api/documentos")
        self.assertNotEqual(r.status_code, 401)

    # ---- dueño del documento ----
    def test_documento_propio_en_ruta(self):
        self.assertEqual(self.http.get("/api/dashboard/doc-a", headers=self.con("tok-a")).status_code, 200)

    def test_documento_ajeno_en_ruta_404(self):
        r = self.http.get("/api/dashboard/doc-b", headers=self.con("tok-a"))
        self.assertEqual(r.status_code, 404)

    def test_documento_inexistente_lo_resuelve_la_ruta(self):
        self.assertEqual(self.http.get("/api/dashboard/no-existe", headers=self.con("tok-a")).status_code, 200)

    def test_comparar_con_un_ajeno_404(self):
        r = self.http.get("/api/dashboard-comparar/doc-a/doc-b", headers=self.con("tok-a"))
        self.assertEqual(r.status_code, 404)

    def test_lista_docs_en_consulta(self):
        self.assertEqual(self.http.get("/api/memoria/cobertura?docs=doc-a", headers=self.con("tok-a")).status_code, 200)
        self.assertEqual(self.http.get("/api/memoria/cobertura?docs=doc-a,doc-b", headers=self.con("tok-a")).status_code, 404)

    def test_formulario_con_documento_ajeno_404(self):
        r = self.http.post("/api/consultar/", data={"document_id": "doc-b", "pregunta": "hola"}, headers=self.con("tok-a"))
        self.assertEqual(r.status_code, 404)

    def test_formulario_propio_llega_completo_a_la_ruta(self):
        r = self.http.post("/api/consultar/", data={"document_id": "doc-a", "pregunta": "¿qué riesgo hay?"},
                           headers=self.con("tok-a"))
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json(), {"id": "doc-a", "pregunta": "¿qué riesgo hay?", "empresa": EMPRESA_A})

    def test_multipart_con_archivo_y_documento_ajeno_404(self):
        r = self.http.post("/api/consultar/", data={"document_id": "doc-b", "pregunta": "x"},
                           files={"archivo": ("a.pdf", b"%PDF" * 10)}, headers=self.con("tok-a"))
        self.assertEqual(r.status_code, 404)

    def test_json_con_docs_ajenos_404_y_propios_llegan(self):
        malo = self.http.post("/api/memoria/pdf", json={"docs": "doc-a,doc-b"}, headers=self.con("tok-a"))
        self.assertEqual(malo.status_code, 404)
        bueno = self.http.post("/api/memoria/pdf", json={"docs": "doc-a", "caps": {"x": 1}}, headers=self.con("tok-a"))
        self.assertEqual(bueno.status_code, 200)
        self.assertEqual(bueno.json()["cuerpo"], {"docs": "doc-a", "caps": {"x": 1}})

    def test_la_otra_empresa_ve_lo_suyo(self):
        self.assertEqual(self.http.get("/api/dashboard/doc-b", headers=self.con("tok-b")).status_code, 200)
        self.assertEqual(self.http.get("/api/dashboard/doc-a", headers=self.con("tok-b")).status_code, 404)

    # ---- cliente que filtra por empresa ----
    def test_listado_solo_de_mi_empresa(self):
        self.http.get("/api/documentos", headers=self.con("tok-a"))
        consulta = [r for r in self.real.registro if r[0] == "select" and r[1] == "documentos"][-1]
        self.assertIn(("eq", "empresa_rut", EMPRESA_A), consulta[2])

    def test_documento_nuevo_queda_marcado_con_empresa_y_usuario(self):
        r = self.http.post("/api/subir-informe/", data={"document_id": "doc-nuevo"}, headers=self.con("tok-a"))
        self.assertEqual(r.status_code, 200)
        insertado = [x for x in self.real.registro if x[0] == "insert"][-1][2]
        self.assertEqual(insertado["empresa_rut"], EMPRESA_A)
        self.assertEqual(insertado["subido_por"], "u-a")
        # el hilo de segundo plano también conoce la empresa
        self.assertEqual(r.json()["hilo_empresa"], EMPRESA_A)

    def test_subir_con_id_de_otra_empresa_404(self):
        r = self.http.post("/api/subir-informe/", data={"document_id": "doc-b"}, headers=self.con("tok-a"))
        self.assertEqual(r.status_code, 404)

    def test_fuera_de_una_peticion_el_cliente_no_filtra(self):
        self.cliente.table("documentos").select("id").execute()
        consulta = [r for r in self.real.registro if r[0] == "select" and r[1] == "documentos"][-1]
        self.assertEqual(consulta[2], [])

    def test_rut_normal(self):
        self.assertEqual(seguridad.rut_normal("76.123.456-0"), "76123456-0")
        self.assertEqual(seguridad.rut_normal("076123456-0"), "76123456-0")
        self.assertEqual(seguridad.rut_normal("12.345.678-k"), "12345678-K")
        self.assertEqual(seguridad.rut_normal(""), "")


if __name__ == "__main__":
    unittest.main()
