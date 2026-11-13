"""Puerta de acceso del MVP mientras se conserva el backend para la migración TS.

La identidad se valida ONLINE en Supabase Auth. Todas las lecturas/RPC usan el
JWT del usuario y RLS; las escrituras de worker llevan tenant fijo y permisos.
No existe modo público ni contraseña de prueba en este módulo.
"""
import base64
import contextvars
import json
import math
import os
import threading
import time
import uuid
from collections.abc import MutableMapping
from dataclasses import dataclass
from urllib.parse import urlparse

import requests
from starlette.concurrency import run_in_threadpool
from starlette.responses import JSONResponse
from supabase import create_client


class AccessError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


def _claims(token):
    """Solo extraer claims; NO concede identidad. Auth /user valida la firma."""
    try:
        if len(token) > 16384 or len(token.split('.')) != 3:
            raise ValueError()
        header, payload, _ = token.split('.')
        unpack = lambda s: json.loads(base64.urlsafe_b64decode(s + '=' * (-len(s) % 4)))
        if unpack(header).get('alg') not in ('HS256', 'ES256', 'RS256'):
            raise ValueError()
        return unpack(payload)
    except (ValueError, TypeError, AttributeError, RecursionError, UnicodeDecodeError, json.JSONDecodeError):
        raise AccessError(401, 'La sesión no es válida.') from None


@dataclass(frozen=True)
class AccessConfig:
    url: str
    anon_key: str
    worker_key: str
    issuer: str
    environment: str = 'production'

    @classmethod
    def from_env(cls):
        url = os.getenv('SUPABASE_URL', '').rstrip('/')
        return cls(url, os.getenv('SUPABASE_ANON_KEY', ''), os.getenv('SUPABASE_KEY', ''),
                   os.getenv('SUPABASE_AUTH_ISSUER', url + '/auth/v1'), os.getenv('DIRECTA_ENV', 'production'))

    def validate(self):
        parsed = urlparse(self.url)
        local = self.environment == 'local' and parsed.hostname in (
            'localhost', '127.0.0.1', '::1', 'host.docker.internal', '10.0.2.2')
        if not self.anon_key or not self.worker_key or not parsed.hostname:
            raise AccessError(503, 'El acceso del servidor aún no está configurado.')
        if parsed.scheme != 'https' and not local:
            raise AccessError(503, 'La conexión del servidor requiere HTTPS.')
        if self.anon_key.startswith('sb_secret_'):
            raise AccessError(503, 'Revisar la clave pública del servidor.')
        if self.anon_key.count('.') == 2 and _claims(self.anon_key).get('role') != 'anon':
            raise AccessError(503, 'Revisar la clave pública del servidor.')


_current = contextvars.ContextVar('directa_access', default=None)
_ROLES = {'owner', 'admin', 'gerente_general', 'secretaria', 'director'}
_TABLES = {'usuarios', 'documentos', 'document_chunks', 'analisis', 'valoraciones', 'lecciones', 'perfiles_tono'}


def current_access():
    value = _current.get()
    if value is None:
        raise AccessError(401, 'Se requiere una sesión verificada.')
    return value


def _json_get(config, path, token, params=None, admin=False):
    key = config.worker_key if admin else config.anon_key
    try:
        response = requests.get(config.url + path, params=params, timeout=8,
                                headers={'apikey': key, 'Authorization': 'Bearer ' + (key if admin else token)})
    except requests.RequestException:
        raise AccessError(503, 'No se pudo verificar el acceso. Inténtalo nuevamente.') from None
    if response.status_code in (401, 403):
        raise AccessError(401, 'La sesión terminó o fue revocada.')
    if response.status_code != 200:
        raise AccessError(503, 'No se pudo comprobar la configuración de acceso.')
    try:
        return response.json()
    except ValueError:
        raise AccessError(503, 'No se pudo comprobar la configuración de acceso.') from None


class AccessRuntime:
    def __init__(self, config=None, http_get=None, client_factory=None):
        self.config = config or AccessConfig.from_env()
        self.http_get = http_get or _json_get
        self.client_factory = client_factory or create_client

    def verify(self, authorization, tenant):
        self.config.validate()
        if not authorization.startswith('Bearer '):
            raise AccessError(401, 'Inicia sesión para continuar.')
        token = authorization[7:].strip()
        payload = _claims(token)
        # Estos checks de claims nunca reemplazan la verificación ONLINE siguiente.
        try:
            user_id = str(uuid.UUID(payload.get('sub', '')))
            tenant = str(uuid.UUID(tenant))
            audience = payload.get('aud')
            if (payload.get('role') != 'authenticated' or payload.get('iss') != self.config.issuer
                or not (audience == 'authenticated' or isinstance(audience, list) and 'authenticated' in audience)
                or not isinstance(payload.get('exp'), (int, float)) or isinstance(payload['exp'], bool)
                or not math.isfinite(payload['exp']) or payload['exp'] <= time.time()):
                raise ValueError()
        except (ValueError, TypeError, AttributeError):
            raise AccessError(401, 'La sesión o la organización no es válida.') from None
        user = self.http_get(self.config, '/auth/v1/user', token)
        if user.get('id') != user_id:
            raise AccessError(401, 'No se pudo verificar la identidad de la sesión.')
        if not user.get('email_confirmed_at'):
            raise AccessError(403, 'Confirma tu correo antes de continuar.')
        if (user.get('user_metadata') or {}).get('directa_local_test') and self.config.environment != 'local':
            raise AccessError(403, 'La cuenta de pruebas no está habilitada en este entorno.')
        rows = self.http_get(self.config, '/rest/v1/memberships', token,
            {'select': 'tenant_id,user_id,role,active', 'tenant_id': 'eq.' + tenant,
             'user_id': 'eq.' + user_id, 'active': 'eq.true'})
        if len(rows) != 1 or not rows[0].get('active') or rows[0].get('role') not in _ROLES:
            raise AccessError(403, 'No tienes una membresía activa para esta organización.')
        role = rows[0]['role']
        if rows[0].get('user_id') != user_id or rows[0].get('tenant_id') != tenant:
            raise AccessError(403, 'La membresía no corresponde a esta sesión.')
        verified_factor = any(f.get('status') == 'verified' for f in (user.get('factors') or []))
        if (role != 'director' or verified_factor) and payload.get('aal') != 'aal2':
            raise AccessError(403, 'Completa la verificación de segundo factor para continuar.')
        organizations = self.http_get(self.config, '/rest/v1/organizations', token,
                                      {'select': 'id,name,active', 'id': 'eq.' + tenant, 'active': 'eq.true'})
        if len(organizations) != 1 or organizations[0].get('id') != tenant or not organizations[0].get('active'):
            raise AccessError(403, 'La organización no está activa o no está disponible.')
        return RequestAccess(self, token, user_id, tenant, role, payload['exp'], organizations[0]['name'])


class RequestAccess:
    def __init__(self, runtime, token, user_id, tenant_id, role, expires, organization):
        self.runtime, self.token = runtime, token
        self.user_id, self.tenant_id, self.role = user_id, tenant_id, role
        self.expires, self.organization = expires, organization
        self._user = self._worker = None
        self._lock = threading.RLock()
        self._references = 1
        self._last_check = time.monotonic()

    def permits(self, permission):
        if permission in ('documents.read', 'analysis.read', 'learning.read'):
            return True
        if permission == 'documents.write':
            return self.role in ('owner', 'admin', 'gerente_general', 'secretaria')
        if permission in ('documents.delete', 'learning.manage'):
            return self.role in ('owner', 'admin', 'gerente_general')
        return False

    def require(self, permission):
        if not self.permits(permission):
            raise AccessError(403, 'Tu cuenta no tiene permiso para esta operación.')

    def ensure_active(self):
        if self.expires <= time.time():
            raise AccessError(401, 'La sesión terminó. Vuelve a iniciar sesión.')
        if time.monotonic() - self._last_check >= 5:
            renewed = self.runtime.verify('Bearer ' + self.token, self.tenant_id)
            try:
                if renewed.role != self.role:
                    raise AccessError(403, 'Los permisos cambiaron. Vuelve a verificar tu acceso.')
                self._last_check = time.monotonic()
            finally:
                renewed.release()

    def client(self, worker=False):
        with self._lock:
            self.ensure_active()
            if worker:
                if self._worker is None:
                    self._worker = self.runtime.client_factory(self.runtime.config.url, self.runtime.config.worker_key)
                return self._worker
            if self._user is None:
                self._user = self.runtime.client_factory(self.runtime.config.url, self.runtime.config.anon_key)
                self._user.postgrest.auth(self.token)
            return self._user

    def reconnect(self):
        with self._lock:
            for client in (self._user, self._worker):
                if client is not None:
                    client.postgrest.session.close()
            self._user = self._worker = None

    def retain(self):
        with self._lock:
            self._references += 1

    def release(self):
        with self._lock:
            self._references -= 1
            if self._references == 0:
                self.reconnect()


class TenantMap(MutableMapping):
    """Cachés y trabajos en memoria separados por organización, incluso en hilos."""
    def __init__(self):
        self._data, self._lock = {}, threading.RLock()
    def _key(self, key):
        return current_access().tenant_id, key
    def __getitem__(self, key):
        with self._lock: return self._data[self._key(key)]
    def __setitem__(self, key, value):
        with self._lock: self._data[self._key(key)] = value
    def __delitem__(self, key):
        with self._lock: del self._data[self._key(key)]
    def __iter__(self):
        tenant = current_access().tenant_id
        with self._lock: return iter([key for (owner, key) in self._data if owner == tenant])
    def __len__(self):
        return sum(1 for _ in self)


def bound_worker(target):
    """Capturar contexto antes de crear el hilo; no usar una credencial global."""
    access = current_access()
    copied = contextvars.copy_context()
    access.retain()
    def run(*args, **kwargs):
        try:
            return copied.run(target, *args, **kwargs)
        finally:
            access.release()
    return run


class ScopedSupabase:
    def table(self, name):
        if name not in _TABLES:
            raise AccessError(403, 'La tabla no está habilitada para esta operación.')
        return ScopedQuery(current_access(), name)
    def reconnect(self):
        current_access().reconnect()
    def rpc(self, name, arguments):
        access = current_access()
        access.require('documents.read')
        if name != 'match_document_chunks':
            raise AccessError(403, 'La función no está habilitada.')
        _require_document(access, arguments.get('p_document_id'))
        return access.client().rpc(name, arguments)


def _require_document(access, document_id):
    if not document_id:
        raise AccessError(422, 'Selecciona un documento de tu organización.')
    rows = access.client().table('documentos').select('id').eq('tenant_id', access.tenant_id).eq('id', document_id).limit(1).execute().data
    if not rows:
        raise AccessError(404, 'El documento no está disponible en esta organización.')


class ScopedQuery:
    def __init__(self, access, name):
        self.access, self.name, self.query = access, name, None
        self.action = 'select'

    def select(self, *args, **kwargs):
        self.query = self.access.client().table(self.name).select(*args, **kwargs)
        return self

    def _permission(self, action):
        if self.name == 'usuarios':
            raise AccessError(403, 'Los perfiles se administran mediante el flujo de identidad.')
        permission = ('learning.manage' if self.name in ('lecciones', 'perfiles_tono') or self.name == 'valoraciones' and action == 'update'
                      else 'documents.read' if self.name == 'valoraciones'
                      else 'documents.delete' if self.name == 'documentos' and action == 'delete'
                      else 'documents.write')
        self.access.require(permission)

    def _payload(self, payload, update=False):
        is_list = isinstance(payload, list)
        result = []
        for original in payload if is_list else [payload]:
            row = dict(original)
            if update and any(key in row for key in ('tenant_id', 'created_by', 'auth_user_id')):
                raise AccessError(403, 'La pertenencia y autoría no se cambian desde esta operación.')
            if not update:
                if row.get('tenant_id', self.access.tenant_id) != self.access.tenant_id:
                    raise AccessError(403, 'La organización no corresponde a esta sesión.')
                row['tenant_id'] = self.access.tenant_id
                if self.name in ('documentos', 'valoraciones', 'lecciones', 'perfiles_tono'):
                    if row.get('created_by', self.access.user_id) != self.access.user_id:
                        raise AccessError(403, 'La autoría no corresponde a esta sesión.')
                    row['created_by'] = self.access.user_id
            if row.get('document_id') is not None:
                _require_document(self.access, row['document_id'])
            if self.name == 'valoraciones' and not update and not row.get('document_id'):
                raise AccessError(422, 'La valoración requiere un documento autorizado.')
            if self.name == 'document_chunks' and row.get('embedding') is not None:
                vector = row['embedding']
                if not isinstance(vector, list) or len(vector) != 2048 or not all(isinstance(v, (float, int)) and math.isfinite(v) for v in vector):
                    raise AccessError(422, 'El embedding no es compatible con la colección.')
                if row.get('embedding_model', 'nvidia/nemotron-3-embed-1b') != 'nvidia/nemotron-3-embed-1b':
                    raise AccessError(422, 'El modelo del embedding no es compatible.')
                row['embedding_model'] = 'nvidia/nemotron-3-embed-1b'
            result.append(row)
        return result if is_list else result[0]

    def insert(self, payload, **kwargs):
        self._permission('insert')
        self.action = 'insert'
        self.query = self.access.client(worker=True).table(self.name).insert(self._payload(payload), **kwargs)
        return self

    def update(self, payload, **kwargs):
        self._permission('update')
        self.query = self.access.client(worker=True).table(self.name).update(self._payload(payload, update=True), **kwargs)
        return self

    def delete(self, **kwargs):
        self._permission('delete')
        self.query = self.access.client(worker=True).table(self.name).delete(**kwargs)
        if self.name == 'valoraciones':
            self.query = self.query.eq('created_by', self.access.user_id)
        return self

    def execute(self):
        if self.query is None:
            raise AccessError(422, 'Falta indicar la operación de datos.')
        self.access.ensure_active()
        if self.action == 'insert':
            return self.query.execute()
        # Se añade AL FINAL para que ninguna cadena cambie el tenant fijo.
        return self.query.eq('tenant_id', self.access.tenant_id).execute()

    def __getattr__(self, name):
        if name not in ('eq', 'neq', 'in_', 'in_filter', 'order', 'limit', 'range', 'filter', 'gte', 'lte', 'gt', 'lt', 'is_', 'not_') or self.query is None:
            raise AttributeError(name)
        def apply(*args, **kwargs):
            if name == 'eq' and len(args) >= 2 and args[0] == 'tenant_id' and args[1] != self.access.tenant_id:
                raise AccessError(403, 'La organización no corresponde a esta sesión.')
            self.query = getattr(self.query, name)(*args, **kwargs)
            return self
        return apply


def permission_for(method, path):
    if method == 'GET': return 'documents.read'
    if path.startswith('/api/lecciones') or path.startswith('/api/memoria/perfil-tono'):
        return 'learning.manage'
    if method == 'DELETE': return 'documents.delete'
    if path in ('/api/consultar/', '/api/consultar-stream/', '/api/verificar/', '/api/guia/preguntar', '/api/valoraciones', '/api/informe/',
                '/api/indicadores/pdf', '/api/memoria/pdf', '/api/indicadores/sugerir') or path.endswith('/pdf') or path.endswith('/excel'):
        return 'documents.read'
    return 'documents.write'


class AccessMiddleware:
    def __init__(self, app, runtime=None):
        self.app, self.runtime = app, runtime or AccessRuntime()

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http' or scope['method'] == 'OPTIONS' or not (
            scope.get('path', '').startswith('/api/') or scope.get('path') in ('/docs', '/redoc', '/openapi.json')):
            return await self.app(scope, receive, send)
        headers = {k.decode('latin-1').lower(): v.decode('latin-1') for k, v in scope.get('headers', [])}
        access = None
        try:
            access = await run_in_threadpool(self.runtime.verify, headers.get('authorization', ''), headers.get('x-directa-tenant', ''))
            access.require(permission_for(scope['method'], scope['path']))
        except AccessError as error:
            if access is not None: access.release()
            response = JSONResponse({'ok': False, 'error': str(error)}, status_code=error.status,
                headers={'Cache-Control': 'no-store', **({'WWW-Authenticate': 'Bearer'} if error.status == 401 else {})})
            return await response(scope, receive, send)
        token = _current.set(access)
        try:
            async def private_send(message):
                if message['type'] == 'http.response.start':
                    message = {**message, 'headers': [*message.get('headers', []), (b'cache-control', b'no-store')]}
                await send(message)
            return await self.app(scope, receive, private_send)
        finally:
            _current.reset(token)
            access.release()
