# -*- coding: utf-8 -*-
"""Guardado de las tablas nuevas de la versión 3 (valoraciones, lecciones y perfiles de tono).

Si la tabla existe en Supabase se usa Supabase. Si no existe (todavía no se corrió migracion_v3.sql),
se guarda en un archivo JSON local para que nada falle. OJO: en Render gratis ese archivo se borra en
cada despliegue o reinicio, por eso /api/estado avisa dónde se está guardando.
"""
import json
import os
import threading
import time
import uuid
from datetime import datetime, timezone

CARPETA_LOCAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "datos_locales")
_LOCK = threading.RLock()
_DETECCION = {}          # tabla -> (momento, "supabase" | "local", error)
TTL_DETECCION = 300


def ahora_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _ruta(tabla):
    return os.path.join(CARPETA_LOCAL, f"{tabla}.json")


def _leer_local(tabla):
    try:
        with open(_ruta(tabla), encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except FileNotFoundError:
        return []
    except Exception as e:  # noqa: BLE001
        print(f"[PERSISTENCIA] No se pudo leer {tabla} local: {e}", flush=True)
        return []


def _escribir_local(tabla, filas):
    os.makedirs(CARPETA_LOCAL, exist_ok=True)
    tmp = _ruta(tabla) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(filas, f, ensure_ascii=False, indent=1)
    os.replace(tmp, _ruta(tabla))


class Tabla:
    """Operaciones mínimas: insertar, listar con filtros de igualdad, obtener, actualizar y borrar por id."""

    def __init__(self, get_sb, nombre):
        self.get_sb = get_sb
        self.nombre = nombre

    # -- dónde se guarda
    def destino(self, forzar=False):
        hit = _DETECCION.get(self.nombre)
        if hit and not forzar and time.time() - hit[0] < TTL_DETECCION:
            return hit[1]
        destino, error = "local", None
        try:
            sb = self.get_sb() if self.get_sb else None
            if sb is not None:
                sb.table(self.nombre).select("id").limit(1).execute()
                destino = "supabase"
        except Exception as e:  # noqa: BLE001
            error = str(e)[:200]
        _DETECCION[self.nombre] = (time.time(), destino, error)
        return destino

    def _sb(self):
        return self.get_sb() if self.destino() == "supabase" else None

    # -- operaciones
    def insertar(self, fila):
        fila = dict(fila)
        fila.setdefault("id", str(uuid.uuid4()))
        fila.setdefault("creado_en", ahora_iso())
        sb = self._sb()
        if sb is not None:
            try:
                r = sb.table(self.nombre).insert(fila).execute()
                return (r.data or [fila])[0]
            except Exception as e:  # noqa: BLE001
                print(f"[PERSISTENCIA] Supabase falló al insertar en {self.nombre}; se guarda local: {e}", flush=True)
        with _LOCK:
            filas = _leer_local(self.nombre)
            filas.append(fila)
            _escribir_local(self.nombre, filas)
        return fila

    def listar(self, limite=1000, orden="creado_en", desc=True, **iguales):
        sb = self._sb()
        if sb is not None:
            try:
                q = sb.table(self.nombre).select("*")
                for k, v in iguales.items():
                    if v is not None:
                        q = q.eq(k, v)
                r = q.order(orden, desc=desc).limit(limite).execute()
                return r.data or []
            except Exception as e:  # noqa: BLE001
                print(f"[PERSISTENCIA] Supabase falló al leer {self.nombre}; se usa lo local: {e}", flush=True)
        with _LOCK:
            filas = [f for f in _leer_local(self.nombre)
                     if all(v is None or str(f.get(k)) == str(v) for k, v in iguales.items())]
        filas.sort(key=lambda f: str(f.get(orden) or ""), reverse=desc)
        return filas[:limite]

    def obtener(self, id_):
        filas = self.listar(limite=1, id=id_)
        return filas[0] if filas else None

    def actualizar(self, id_, cambios):
        sb = self._sb()
        if sb is not None:
            try:
                r = sb.table(self.nombre).update(cambios).eq("id", id_).execute()
                return (r.data or [None])[0]
            except Exception as e:  # noqa: BLE001
                print(f"[PERSISTENCIA] Supabase falló al actualizar {self.nombre}: {e}", flush=True)
        with _LOCK:
            filas = _leer_local(self.nombre)
            out = None
            for f in filas:
                if str(f.get("id")) == str(id_):
                    f.update(cambios)
                    out = f
            _escribir_local(self.nombre, filas)
        return out

    def borrar(self, id_):
        sb = self._sb()
        if sb is not None:
            try:
                sb.table(self.nombre).delete().eq("id", id_).execute()
                return True
            except Exception as e:  # noqa: BLE001
                print(f"[PERSISTENCIA] Supabase falló al borrar en {self.nombre}: {e}", flush=True)
        with _LOCK:
            filas = _leer_local(self.nombre)
            _escribir_local(self.nombre, [f for f in filas if str(f.get("id")) != str(id_)])
        return True


def estado(get_sb, tablas=("valoraciones", "lecciones", "perfiles_tono")):
    out = {}
    for t in tablas:
        destino = Tabla(get_sb, t).destino(forzar=True)
        out[t] = destino
    out["aviso"] = ("" if all(out[t] == "supabase" for t in tablas) else
                    "Algunas tablas se guardan en un archivo local del servidor, que en Render se borra al reiniciar. "
                    "Corre backend/migracion_v3.sql en Supabase para guardarlas de forma permanente.")
    return out
