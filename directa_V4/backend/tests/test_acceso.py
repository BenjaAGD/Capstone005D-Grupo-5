"""Pruebas de middleware, scope, workers y transporte. Sin Supabase remoto.

La autoridad Auth se simula con un verificador HMAC de prueba; NO sustituye
una prueba de integración con el servicio GoTrue/Supabase real.
"""
import asyncio
import ast
import base64
import contextvars
import hashlib
import hmac
import importlib
import json
import os
from pathlib import Path
import sys
import threading
import time
import unittest
from types import SimpleNamespace
from unittest.mock import Mock

import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import acceso
from acceso import AccessConfig, AccessError, AccessRuntime, ScopedSupabase, TenantMap, bound_worker

USER = '10000000-0000-4000-8000-000000000001'
TENANT_A = '20000000-0000-4000-8000-000000000001'
TENANT_B = '20000000-0000-4000-8000-000000000002'
KEY = b'clave-ficticia-exclusiva-del-verificador-de-pruebas'
CONFIG = AccessConfig('https://auth.example.invalid', 'public-test-key', 'worker-test-key',
                      'https://auth.example.invalid/auth/v1', 'local')


def token(**extra):
    values = {'sub': USER, 'iss': CONFIG.issuer, 'aud': 'authenticated', 'role': 'authenticated',
              'aal': 'aal2', 'exp': int(time.time()) + 3600}
    values.update(extra)
    encode = lambda data: base64.urlsafe_b64encode(json.dumps(data).encode()).decode().rstrip('=')
    data = encode({'alg': 'HS256'}) + '.' + encode(values)
    return data + '.' + base64.urlsafe_b64encode(hmac.new(KEY, data.encode(), hashlib.sha256).digest()).decode().rstrip('=')


class FakeQuery:
    def __init__(self, store, table, calls, worker=False):
        self.store, self.table, self.calls, self.worker = store, table, calls, worker
        self.filters, self.action, self.body = [], 'select', None
    def select(self, *args, **kwargs): return self
    def eq(self, column, value): self.filters.append((column, value)); return self
    def insert(self, data, **kwargs): self.action, self.body = 'insert', data; return self
    def update(self, data, **kwargs): self.action, self.body = 'update', data; return self
    def delete(self, **kwargs): self.action = 'delete'; return self
    def order(self, *args, **kwargs): return self
    def limit(self, *args, **kwargs): return self
    def range(self, *args, **kwargs): return self
    def execute(self):
        self.calls.append((self.table, self.action, list(self.filters), self.body, self.worker))
        data = self.store.setdefault(self.table, [])
        rows = [r for r in data if all(r.get(k) == v for k, v in self.filters)]
        if self.action == 'insert':
            rows = self.body if isinstance(self.body, list) else [self.body]
            data.extend(rows)
        elif self.action == 'update':
            for row in rows: row.update(self.body)
        elif self.action == 'delete':
            for row in rows: data.remove(row)
        return SimpleNamespace(data=[dict(x) for x in rows], count=len(rows))


class FakeSdk:
    def __init__(self, store, calls, worker):
        self.store, self.calls, self.worker = store, calls, worker
        self.postgrest = SimpleNamespace(auth=Mock(), session=SimpleNamespace(close=Mock()))
    def table(self, table): return FakeQuery(self.store, table, self.calls, self.worker)
    def rpc(self, name, arguments): return FakeQuery(self.store, 'rpc', self.calls)


class Authority:
    def __init__(self):
        self.role, self.active, self.organization_active, self.email_verified = 'admin', True, True, True
        self.calls = []
        self.db_calls = []
        self.store = {
            'documentos': [{'id': 'a', 'tenant_id': TENANT_A}, {'id': 'b', 'tenant_id': TENANT_B}],
            'analisis': [{'id': 'analysis-a', 'tenant_id': TENANT_A, 'document_id': 'a', 'score': 10},
                         {'id': 'analysis-b', 'tenant_id': TENANT_B, 'document_id': 'b', 'score': 20}],
        }
    def get(self, config, path, jwt, params=None, admin=False):
        self.calls.append(path)
        if path == '/auth/v1/user':
            data, signature = jwt.rsplit('.', 1)
            expected = base64.urlsafe_b64encode(hmac.new(KEY, data.encode(), hashlib.sha256).digest()).decode().rstrip('=')
            if not hmac.compare_digest(signature, expected): raise AccessError(401, 'Firma inválida en autoridad simulada.')
            return {'id': USER, 'email_confirmed_at': '2026-01-01' if self.email_verified else None}
        if path == '/rest/v1/memberships':
            if not self.active or params['tenant_id'] != 'eq.' + TENANT_A: return []
            return [{'tenant_id': TENANT_A, 'user_id': USER, 'role': self.role, 'active': True}]
        if path == '/rest/v1/organizations':
            return [{'id': TENANT_A, 'name': 'Empresa ficticia A', 'active': self.organization_active}]
        raise AssertionError(path)
    def sdk(self, url, key): return FakeSdk(self.store, self.db_calls, key == CONFIG.worker_key)
    def runtime(self): return AccessRuntime(CONFIG, http_get=self.get, client_factory=self.sdk)


class AccessUnitTests(unittest.TestCase):
    def setUp(self): self.authority = Authority(); self.runtime = self.authority.runtime()
    def verify(self, value=None, tenant=TENANT_A): return self.runtime.verify('Bearer ' + (value or token()), tenant)
    def denied(self, status, operation):
        with self.assertRaises(AccessError) as caught: operation()
        self.assertEqual(caught.exception.status, status)

    def test_ausente_y_malformado(self):
        self.denied(401, lambda: self.runtime.verify('', TENANT_A))
        for value in ('a', 'a.b.c', 'x' * 17000): self.denied(401, lambda: self.verify(value))
    def test_firma_debe_validarla_la_autoridad_auth(self):
        self.denied(401, lambda: self.verify(token()[:-4] + 'fake'))
        self.assertEqual(self.authority.calls, ['/auth/v1/user'])
    def test_expirado_emisor_audiencia_y_rol(self):
        for value in (token(exp=int(time.time()) - 1), token(iss='https://otro.invalid'), token(aud='otro'), token(role='service_role')):
            self.denied(401, lambda: self.verify(value))
        self.assertFalse(self.authority.calls)
    def test_sin_confirmacion_no_entra(self):
        self.authority.email_verified = False; self.denied(403, self.verify)
    def test_organizacion_ajena_rechazada(self): self.denied(403, lambda: self.verify(tenant=TENANT_B))
    def test_membresia_inactiva_rechazada(self):
        self.authority.active = False; self.denied(403, self.verify)
    def test_organizacion_inactiva_rechazada(self):
        self.authority.organization_active = False; self.denied(403, self.verify)
    def test_aal1_admin_rechazado_y_director_lectura(self):
        self.denied(403, lambda: self.verify(token(aal='aal1')))
        self.authority.role = 'director'; access = self.verify(token(aal='aal1'))
        self.assertTrue(access.permits('documents.read')); self.assertFalse(access.permits('documents.write'))
        access.release()
    def test_lecturas_llevan_jwt_y_tenant(self):
        access = self.verify(); context = acceso._current.set(access)
        try:
            result = ScopedSupabase().table('documentos').select('*').execute().data
            self.assertEqual([r['id'] for r in result], ['a'])
            self.assertIn(('tenant_id', TENANT_A), self.authority.db_calls[-1][2])
            access._user.postgrest.auth.assert_called_once_with(access.token)
            self.assertFalse(self.authority.db_calls[-1][4])
        finally: acceso._current.reset(context); access.release()
    def test_escritura_de_worker_fija_empresa_y_autor(self):
        access = self.verify(); context = acceso._current.set(access)
        try:
            ScopedSupabase().table('documentos').insert({'id': 'nuevo', 'titulo': 'Ficticio'}).execute()
            body = self.authority.db_calls[-1][3]
            self.assertEqual(body['tenant_id'], TENANT_A); self.assertEqual(body['created_by'], USER)
            self.denied(403, lambda: ScopedSupabase().table('documentos').insert({'id': 'mal', 'tenant_id': TENANT_B}))
            self.denied(403, lambda: ScopedSupabase().table('documentos').insert({'id': 'mal', 'created_by': TENANT_B}))
        finally: acceso._current.reset(context); access.release()
    def test_actualizacion_no_modifica_analisis_de_otra_empresa(self):
        access = self.verify(); context = acceso._current.set(access)
        try:
            ScopedSupabase().table('analisis').update({'score': 100}).eq('id', 'analysis-b').execute()
            self.assertEqual(self.authority.store['analisis'][1]['score'], 20)
            self.denied(403, lambda: ScopedSupabase().table('analisis').update({'tenant_id': TENANT_B}))
        finally: acceso._current.reset(context); access.release()
    def test_no_inyectar_documento_ni_embedding_de_otro_tenant(self):
        access = self.verify(); context = acceso._current.set(access)
        try:
            self.denied(404, lambda: ScopedSupabase().table('document_chunks').insert({'document_id': 'b', 'content': 'x'}))
            self.denied(422, lambda: ScopedSupabase().table('document_chunks').insert({'document_id': 'a', 'content': 'x', 'embedding': [1.0]}))
            self.denied(404, lambda: ScopedSupabase().rpc('match_document_chunks', {'p_document_id': 'b'}))
        finally: acceso._current.reset(context); access.release()
    def test_cache_y_worker_no_comparten_empresa(self):
        store = TenantMap(); a = self.verify(); c = acceso._current.set(a)
        try:
            store['job'] = 'A'; out = []
            worker = threading.Thread(target=bound_worker(lambda: out.append(store['job'])))
            worker.start(); worker.join(); self.assertEqual(out, ['A'])
            b = acceso.RequestAccess(self.runtime, token(), USER, TENANT_B, 'admin', time.time() + 50, 'B')
            bc = acceso._current.set(b)
            try: self.assertIsNone(store.get('job')); store['job'] = 'B'
            finally: acceso._current.reset(bc); b.release()
            self.assertEqual(store['job'], 'A')
        finally: acceso._current.reset(c); a.release()
    def test_fuera_de_sesion_no_hay_acceso_a_cache_ni_datos(self):
        self.denied(401, lambda: TenantMap().get('dato'))
        self.denied(401, lambda: ScopedSupabase().table('documentos'))
    def test_error_de_db_no_cae_en_json(self):
        from persistencia import Tabla
        def denied(): raise AccessError(403, 'Acceso denegado')
        for op in (lambda: Tabla(denied, 'lecciones').listar(), lambda: Tabla(denied, 'valoraciones').insertar({'valor': 1})):
            self.denied(403, op)


class RouteTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        os.environ.update({'SUPABASE_URL': CONFIG.url, 'SUPABASE_KEY': CONFIG.worker_key,
                           'SUPABASE_ANON_KEY': CONFIG.anon_key, 'NVIDIA_API_KEY': 'ficticia-solo-para-importar-en-pruebas'})
        self.main = importlib.import_module('main')
        self.authority = Authority()
        for middleware in self.main.app.user_middleware:
            if middleware.cls is acceso.AccessMiddleware: middleware.kwargs['runtime'] = self.authority.runtime()
        self.main.app.middleware_stack = None
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=self.main.app), base_url='http://test', trust_env=False)
    async def asyncTearDown(self): await self.client.aclose()
    async def test_las_50_operaciones_existentes_rechazan_sesion_ausente(self):
        routes = []
        for file in ROOT.glob('*.py'):
            if file.name == 'acceso.py': continue
            for node in ast.walk(ast.parse(file.read_text())):
                if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)): continue
                for d in node.decorator_list:
                    if isinstance(d, ast.Call) and isinstance(d.func, ast.Attribute) and d.func.attr in ('get','post','put','delete') and d.args and isinstance(d.args[0], ast.Constant):
                        path = d.args[0].value
                        if isinstance(path, str) and path.startswith('/api/') and path != '/api/auth/session':
                            import re
                            routes.append((d.func.attr.upper(), re.sub(r'\{[^}]+\}', 'ficticio', path)))
        self.assertEqual(len(routes), 50)
        for method, route in routes:
            response = await self.client.request(method, route)
            self.assertEqual(response.status_code, 401, (method, route, response.text))
    async def test_contexto_y_listado_autorizados_sin_datos_ajenos(self):
        headers = {'Authorization': 'Bearer ' + token(), 'X-Directa-Tenant': TENANT_A}
        response = await self.client.get('/api/auth/session', headers=headers)
        self.assertEqual(response.status_code, 200); self.assertTrue(response.json()['verified'])
        response = await self.client.get('/api/documentos', headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual([r['id'] for r in response.json()['documentos']], ['a'])
    async def test_director_no_borra_y_membresia_revocada_no_lee(self):
        self.authority.role = 'director'
        headers = {'Authorization': 'Bearer ' + token(aal='aal1'), 'X-Directa-Tenant': TENANT_A}
        response = await self.client.delete('/api/documentos/a', headers=headers)
        self.assertEqual(response.status_code, 403)
        self.authority.active = False
        response = await self.client.get('/api/documentos', headers=headers)
        self.assertEqual(response.status_code, 403)


if __name__ == '__main__': unittest.main(verbosity=2)
