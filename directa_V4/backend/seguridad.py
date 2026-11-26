# -*- coding: utf-8 -*-
"""Seguridad del backend DIRECTA: sesión obligatoria y documentos con dueño (empresa).

Qué hace:
  1. Todas las rutas /api/* exigen `Authorization: Bearer <token de Supabase>`. Sin token válido: 401.
     "/" (el ping de la app) y las rutas que no empiezan con /api/ siguen abiertas.
  2. La empresa de la persona sale de `app_metadata.rut_empresa` (el usuario NO puede editarlo; lo copia
     un trigger de la base al crear la cuenta, ver migracion_v8). Debe estar activa en empresas_autorizadas.
  3. Si la petición menciona un documento (en la ruta, la consulta o el cuerpo) que pertenece a otra
     empresa, responde 404 como si no existiera.
  4. El cliente de Supabase que usa el resto del código ([ClienteEmpresa]) filtra automáticamente la
     tabla `documentos` por la empresa de la petición y marca con ella los documentos nuevos. Así los
     listados y las memorias por año solo ven documentos propios, sin tocar cada ruta.

Requiere SUPABASE_SERVICE_ROLE_KEY (solo en el servidor, nunca en la app).
"""
import contextvars
import hashlib
import json
import re
import threading
import time
from urllib.parse import parse_qs

from starlette.concurrency import run_in_threadpool
from starlette.responses import JSONResponse

# Empresa y usuario de la petición en curso (los hilos que se crean durante la petición los heredan).
EMPRESA_ACTUAL = contextvars.ContextVar("directa_empresa_rut", default=None)
USUARIO_ACTUAL = contextvars.ContextVar("directa_usuario_id", default=None)

_VIGENCIA_SESION = 60       # segundos que se recuerda un token ya validado
_VIGENCIA_EMPRESA = 300     # segundos que se recuerda que una empresa está activa
_VIGENCIA_PROPIEDAD = 30    # segundos que se recuerda que un documento es de la empresa
_BYTES_A_REVISAR = 256 * 1024


def rut_normal(rut):
    """'76.123.456-0' → '76123456-0' (igual que public.directa_rut_normal en la base)."""
    limpio = re.sub(r"[^0-9kK]", "", str(rut or "")).upper()
    if len(limpio) < 2:
        return ""
    return limpio[:-1].lstrip("0") + "-" + limpio[-1]


# --------------------------------------------------------------------------- hilos

def propagar_contexto_en_hilos():
    """Hace que los hilos creados con threading.Thread hereden la empresa de la petición.
    (Python 3.12 y anteriores no copian el contexto solos.) Se llama una sola vez al arrancar."""
    if getattr(threading.Thread, "_directa_ctx", False):
        return
    original = threading.Thread

    class HiloConContexto(original):
        _directa_ctx = True

        def __init__(self, *a, **k):
            super().__init__(*a, **k)
            self._ctx_directa = contextvars.copy_context()

        def run(self):
            self._ctx_directa.run(super().run)

    threading.Thread = HiloConContexto


# --------------------------------------------------------------------------- cliente

class _TablaDocumentos:
    """La tabla `documentos` limitada a la empresa de la petición."""

    def __init__(self, tabla, empresa, usuario):
        self._t = tabla
        self._empresa = empresa
        self._usuario = usuario

    def _marcar(self, fila):
        if isinstance(fila, list):
            return [self._marcar(f) for f in fila]
        fila = dict(fila)
        fila["empresa_rut"] = self._empresa
        if self._usuario:
            fila.setdefault("subido_por", self._usuario)
        return fila

    def select(self, *a, **k):
        return self._t.select(*a, **k).eq("empresa_rut", self._empresa)

    def update(self, *a, **k):
        return self._t.update(*a, **k).eq("empresa_rut", self._empresa)

    def delete(self, *a, **k):
        return self._t.delete(*a, **k).eq("empresa_rut", self._empresa)

    def insert(self, fila, *a, **k):
        return self._t.insert(self._marcar(fila), *a, **k)

    def upsert(self, fila, *a, **k):
        return self._t.upsert(self._marcar(fila), *a, **k)

    def __getattr__(self, nombre):
        return getattr(self._t, nombre)


class ClienteEmpresa:
    """Envuelve el cliente de Supabase (con la clave de servicio). Todo funciona igual, salvo que
    `table("documentos")` solo ve y crea documentos de la empresa de la petición en curso.
    Fuera de una petición (arranque, tareas internas) se comporta como el cliente normal."""

    def __init__(self, real):
        self._real = real

    @property
    def real(self):
        return self._real

    def reemplazar(self, real):
        self._real = real

    def table(self, nombre):
        tabla = self._real.table(nombre)
        if nombre == "documentos":
            empresa = EMPRESA_ACTUAL.get()
            if empresa:
                return _TablaDocumentos(tabla, empresa, USUARIO_ACTUAL.get())
        return tabla

    def __getattr__(self, nombre):
        return getattr(self._real, nombre)


# --------------------------------------------------------------------------- middleware

class _Rechazo(Exception):
    def __init__(self, estado, mensaje):
        super().__init__(mensaje)
        self.estado = estado
        self.mensaje = mensaje


_RUTAS_CON_DOCUMENTO = [
    re.compile(r"^/api/(?:documentos|dashboard|diagnosticos|diagnostico|progreso|analisis-reintentar|"
               r"analisis-completos|verificar-analisis|ruta-preguntas|preparar-reunion|indicadores/sugeridos)/([^/]+)"),
    re.compile(r"^/api/dashboard-comparar/([^/]+)/([^/]+)"),
]
_CLAVES_ID = ("document_id", "documento_id", "id_a", "id_b")
_CLAVES_LISTA = ("docs", "documentos")


def _ids_de_texto(valor):
    return [x.strip() for x in str(valor or "").split(",") if x.strip()]


def ids_en_ruta(path):
    ids = []
    for patron in _RUTAS_CON_DOCUMENTO:
        m = patron.match(path)
        if m:
            ids.extend(m.groups())
    return ids


def ids_en_consulta(query_string):
    if isinstance(query_string, bytes):
        query_string = query_string.decode("latin-1")
    q = parse_qs(query_string or "")
    ids = []
    for k in _CLAVES_ID:
        ids.extend(q.get(k, []))
    for k in _CLAVES_LISTA:
        for v in q.get(k, []):
            ids.extend(_ids_de_texto(v))
    return ids


def ids_en_cuerpo(tipo, datos, completo):
    """Busca ids de documentos en un cuerpo JSON, formulario o multipart (solo el inicio del cuerpo)."""
    ids = []
    tipo = (tipo or "").lower()
    try:
        if "application/json" in tipo:
            if not completo:
                return ids
            obj = json.loads(datos.decode("utf-8"))
            if isinstance(obj, dict):
                for k in _CLAVES_ID:
                    if obj.get(k):
                        ids.append(str(obj[k]))
                for k in _CLAVES_LISTA:
                    ids.extend(_ids_de_texto(obj.get(k)))
        elif "application/x-www-form-urlencoded" in tipo:
            ids.extend(ids_en_consulta(datos))
        elif "multipart/form-data" in tipo:
            texto = datos.decode("latin-1")
            for k in _CLAVES_ID + _CLAVES_LISTA:
                for m in re.finditer(r'name="%s"\r?\n\r?\n([^\r\n]*)' % re.escape(k), texto):
                    ids.extend(_ids_de_texto(m.group(1)) if k in _CLAVES_LISTA else [m.group(1).strip()])
    except Exception:
        pass
    return ids


class AutenticacionDirecta:
    """Middleware ASGI. `obtener_cliente()` debe devolver el cliente REAL de Supabase (clave de servicio)."""

    def __init__(self, app, obtener_cliente):
        self.app = app
        self._cliente = obtener_cliente
        self._sesiones = {}
        self._empresas = {}
        self._propios = {}
        self._cerrojo = threading.Lock()

    # ---- consultas (corren en un hilo) ----
    def _empresa_activa(self, rut):
        ahora = time.time()
        hit = self._empresas.get(rut)
        if hit and hit > ahora:
            return True
        try:
            filas = (self._cliente().table("empresas_autorizadas").select("rut")
                     .eq("rut", rut).eq("activa", True).limit(1).execute().data or [])
        except Exception as e:  # noqa: BLE001
            print(f"[SEGURIDAD] No se pudo leer empresas_autorizadas: {e}", flush=True)
            raise _Rechazo(503, "No se pudo verificar tu empresa. Revisa la configuración del servidor.")
        if not filas:
            return False
        self._empresas[rut] = ahora + _VIGENCIA_EMPRESA
        return True

    def _validar(self, token):
        clave = hashlib.sha256(token.encode()).hexdigest()
        ahora = time.time()
        hit = self._sesiones.get(clave)
        if hit and hit[0] > ahora:
            return hit[1]
        try:
            usuario = self._cliente().auth.get_user(token).user
        except Exception:  # noqa: BLE001
            usuario = None
        if usuario is None:
            raise _Rechazo(401, "Tu sesión venció o no es válida. Vuelve a iniciar sesión.")
        if not getattr(usuario, "email_confirmed_at", None):
            raise _Rechazo(403, "Confirma tu correo antes de usar DIRECTA.")
        meta = getattr(usuario, "app_metadata", None) or {}
        empresa = rut_normal(meta.get("rut_empresa"))
        if not empresa or not self._empresa_activa(empresa):
            raise _Rechazo(403, "Tu cuenta no tiene una empresa habilitada en DIRECTA.")
        datos = (str(usuario.id), empresa)
        with self._cerrojo:
            if len(self._sesiones) > 2000:
                self._sesiones.clear()
            self._sesiones[clave] = (ahora + _VIGENCIA_SESION, datos)
        return datos

    def _verificar_documentos(self, ids, empresa):
        ahora = time.time()
        pendientes = sorted({i for i in ids if i and not i.startswith("__")
                             and self._propios.get((empresa, i), 0) <= ahora})
        if not pendientes:
            return
        try:
            filas = (self._cliente().table("documentos").select("id, empresa_rut")
                     .in_("id", pendientes).execute().data or [])
        except Exception as e:  # noqa: BLE001
            print(f"[SEGURIDAD] No se pudo comprobar el dueño del documento: {e}", flush=True)
            raise _Rechazo(503, "No se pudo verificar el documento. Inténtalo de nuevo.")
        for f in filas:
            if rut_normal(f.get("empresa_rut")) != empresa:
                raise _Rechazo(404, "Documento no encontrado.")
            self._propios[(empresa, f["id"])] = ahora + _VIGENCIA_PROPIEDAD
        if len(self._propios) > 5000:
            self._propios.clear()

    # ---- ASGI ----
    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        path = scope["path"]
        metodo = scope["method"]
        if metodo == "OPTIONS" or not path.startswith("/api/"):
            return await self.app(scope, receive, send)

        cabeceras = {k.decode("latin-1").lower(): v.decode("latin-1") for k, v in scope["headers"]}
        auth = cabeceras.get("authorization", "")
        token = auth[7:].strip() if auth.lower().startswith("bearer ") else ""
        recibir = receive
        try:
            if not token:
                raise _Rechazo(401, "Inicia sesión para usar DIRECTA.")
            usuario_id, empresa = await run_in_threadpool(self._validar, token)

            ids = ids_en_ruta(path) + ids_en_consulta(scope.get("query_string", b""))
            if metodo in ("POST", "PUT", "PATCH", "DELETE"):
                mensajes, completo, total = [], False, 0
                while True:
                    m = await receive()
                    mensajes.append(m)
                    if m["type"] != "http.request":
                        break
                    total += len(m.get("body", b""))
                    if not m.get("more_body", False):
                        completo = True
                        break
                    if total >= _BYTES_A_REVISAR:
                        break
                ids += ids_en_cuerpo(cabeceras.get("content-type"), b"".join(
                    m.get("body", b"") for m in mensajes if m["type"] == "http.request"), completo)

                async def recibir():  # noqa: F811 - reenvía lo ya leído y sigue con el resto
                    if mensajes:
                        return mensajes.pop(0)
                    return await receive()

            if ids:
                await run_in_threadpool(self._verificar_documentos, ids, empresa)
        except _Rechazo as r:
            respuesta = JSONResponse({"ok": False, "error": r.mensaje}, status_code=r.estado)
            return await respuesta(scope, receive, send)

        scope.setdefault("state", {})
        scope["state"]["empresa_rut"] = empresa
        scope["state"]["usuario_id"] = usuario_id
        t1 = EMPRESA_ACTUAL.set(empresa)
        t2 = USUARIO_ACTUAL.set(usuario_id)
        try:
            await self.app(scope, recibir, send)
        finally:
            EMPRESA_ACTUAL.reset(t1)
            USUARIO_ACTUAL.reset(t2)
