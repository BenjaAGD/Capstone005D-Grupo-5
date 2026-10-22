# -*- coding: utf-8 -*-
"""
Almacén de las tablas NUEVAS de Directa (memoria de agentes, lecciones, perfil de tono, metadatos).

  * Si la tabla existe en Supabase (migracion_v3.sql ya corrida), se guarda ahí.
  * Si no existe (o Supabase no responde), se guarda en archivos JSON dentro de DIRECTA_DATOS_DIR
    (por defecto ./datos_locales; en Docker es un volumen, para que sobreviva a los reinicios).

Las tablas originales (documentos, document_chunks, analisis) NO se tocan desde aquí.
"""
import json
import os
import threading
import time
import uuid
from datetime import datetime, timezone

_PISTAS_TABLA_FALTANTE = ("pgrst205", "could not find the table", "does not exist", "42p01", "schema cache", "relation \"")
REINTENTO_SUPABASE_SEG = 600


def _ahora():
    return datetime.now(timezone.utc).isoformat()


def dir_datos():
    d = os.getenv("DIRECTA_DATOS_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "datos_locales")
    os.makedirs(d, exist_ok=True)
    return d


class Tabla:
    def __init__(self, almacen, nombre):
        self.a, self.nombre = almacen, nombre

    # ------------------------------------------------------------------ utilidades
    @property
    def _archivo(self):
        return os.path.join(dir_datos(), f"{self.nombre}.json")

    def _leer_local(self):
        with self.a._lock:
            try:
                with open(self._archivo, encoding="utf-8") as f:
                    datos = json.load(f)
                return datos if isinstance(datos, list) else []
            except (FileNotFoundError, ValueError):
                return []

    def _escribir_local(self, filas):
        with self.a._lock:
            tmp = self._archivo + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(filas, f, ensure_ascii=False, indent=1, default=str)
            os.replace(tmp, self._archivo)

    def _usar_supabase(self):
        sb = self.a._sb()
        if sb is None:
            return None
        caido = self.a._sin_tabla.get(self.nombre)
        if caido and time.time() - caido < REINTENTO_SUPABASE_SEG:
            return None
        return sb

    def _falla(self, e):
        t = (type(e).__name__ + " " + str(e)).lower()
        if any(p in t for p in _PISTAS_TABLA_FALTANTE):
            self.a._sin_tabla[self.nombre] = time.time()
            print(f"[ALMACEN] La tabla '{self.nombre}' no existe en Supabase; se usa archivo local. "
                  f"(Corre migracion_v3.sql para guardarla en la base.)", flush=True)
        else:
            print(f"[ALMACEN] Supabase falló en '{self.nombre}': {e}; se usa archivo local esta vez.", flush=True)

    @property
    def modo(self):
        return "supabase" if self._usar_supabase() is not None else "local"

    # ------------------------------------------------------------------ operaciones
    def insertar(self, fila):
        fila = dict(fila)
        fila.setdefault("id", str(uuid.uuid4()))
        fila.setdefault("creado_en", _ahora())
        sb = self._usar_supabase()
        if sb is not None:
            try:
                sb.table(self.nombre).insert(fila).execute()
                return fila
            except Exception as e:
                self._falla(e)
        with self.a._lock:                      # leer-modificar-escribir debe ser atómico: varios hilos guardan a la vez
            filas = self._leer_local()
            filas.append(fila)
            self._escribir_local(filas)
        return fila

    def listar(self, orden="creado_en", desc=True, limite=None, **filtros):
        """Filas que cumplen filtros de igualdad (columna=valor). Valor lista -> pertenece a la lista."""
        sb = self._usar_supabase()
        if sb is not None:
            try:
                q = sb.table(self.nombre).select("*")
                for c, v in filtros.items():
                    q = q.in_(c, v) if isinstance(v, (list, tuple, set)) else q.eq(c, v)
                if orden:
                    q = q.order(orden, desc=desc)
                if limite:
                    q = q.limit(limite)
                return q.execute().data or []
            except Exception as e:
                self._falla(e)
        filas = [f for f in self._leer_local() if all(
            (f.get(c) in v) if isinstance(v, (list, tuple, set)) else f.get(c) == v for c, v in filtros.items())]
        if orden:
            filas.sort(key=lambda f: (f.get(orden) is None, f.get(orden)), reverse=desc)
        return filas[:limite] if limite else filas

    def obtener(self, id_):
        r = self.listar(orden=None, id=id_, limite=1)
        return r[0] if r else None

    def actualizar(self, id_, cambios):
        cambios = dict(cambios)
        sb = self._usar_supabase()
        if sb is not None:
            try:
                sb.table(self.nombre).update(cambios).eq("id", id_).execute()
                return True
            except Exception as e:
                self._falla(e)
        with self.a._lock:
            filas, ok = self._leer_local(), False
            for f in filas:
                if f.get("id") == id_:
                    f.update(cambios)
                    ok = True
            if ok:
                self._escribir_local(filas)
        return ok

    def borrar(self, **filtros):
        if not filtros:
            raise ValueError("borrar() exige al menos un filtro")
        sb = self._usar_supabase()
        if sb is not None:
            try:
                q = sb.table(self.nombre).delete()
                for c, v in filtros.items():
                    q = q.eq(c, v)
                q.execute()
                return True
            except Exception as e:
                self._falla(e)
        with self.a._lock:
            filas = self._leer_local()
            quedan = [f for f in filas if not all(f.get(c) == v for c, v in filtros.items())]
            self._escribir_local(quedan)
        return len(quedan) != len(filas)

    def guardar_unico(self, clave, fila):
        """Reemplaza la fila con el mismo valor de `clave` (p. ej. document_id) o la crea."""
        with self.a._lock:                      # evita dos filas con la misma clave cuando dos hilos guardan a la vez
            previas = self.listar(orden=None, **{clave: fila[clave]})
            if previas:
                self.actualizar(previas[0]["id"], {k: v for k, v in fila.items() if k != "id"})
                return {**previas[0], **fila}
            return self.insertar(fila)


class Almacen:
    def __init__(self, get_supabase=None):
        self._get_sb = get_supabase
        self._sin_tabla = {}
        self._lock = threading.RLock()

    def _sb(self):
        if self._get_sb is None:
            return None
        try:
            return self._get_sb()
        except Exception:
            return None

    def tabla(self, nombre):
        return Tabla(self, nombre)

    def resumen(self):
        nombres = ("documentos_meta", "agente_interacciones", "agente_lecciones", "perfil_tono", "memoria_borradores", "reunion_carpetas")
        return {n: self.tabla(n).modo for n in nombres}


_almacen = Almacen()


def configurar(get_supabase):
    global _almacen
    _almacen = Almacen(get_supabase)
    return _almacen


def tabla(nombre):
    return _almacen.tabla(nombre)


def resumen():
    return _almacen.resumen()
