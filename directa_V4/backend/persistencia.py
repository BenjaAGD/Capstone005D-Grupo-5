# -*- coding: utf-8 -*-
"""Persistencia autenticada. Las denegaciones no se convierten en archivos JSON.

Los archivos históricos de datos_locales se conservan en disco sin adjudicarlos
ni leerlos automáticamente para una nueva identidad u organización.
"""
import uuid
from datetime import datetime, timezone


def ahora_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Tabla:
    def __init__(self, get_sb, nombre):
        self.get_sb, self.nombre = get_sb, nombre

    def _sb(self):
        sb = self.get_sb() if self.get_sb else None
        if sb is None:
            raise RuntimeError("La persistencia autenticada no está disponible.")
        return sb

    def destino(self, forzar=False):
        self._sb().table(self.nombre).select("id").limit(1).execute()
        return "supabase"

    def insertar(self, fila):
        fila = dict(fila)
        fila.setdefault("id", str(uuid.uuid4()))
        fila.setdefault("creado_en", ahora_iso())
        r = self._sb().table(self.nombre).insert(fila).execute()
        return (r.data or [fila])[0]

    def listar(self, limite=1000, orden="creado_en", desc=True, **iguales):
        q = self._sb().table(self.nombre).select("*")
        for k, v in iguales.items():
            if v is not None:
                q = q.eq(k, v)
        return q.order(orden, desc=desc).limit(limite).execute().data or []

    def obtener(self, id_):
        filas = self.listar(limite=1, id=id_)
        return filas[0] if filas else None

    def actualizar(self, id_, cambios):
        r = self._sb().table(self.nombre).update(cambios).eq("id", id_).execute()
        return (r.data or [None])[0]

    def borrar(self, id_):
        self._sb().table(self.nombre).delete().eq("id", id_).execute()
        return True


def estado(get_sb, tablas=("valoraciones", "lecciones", "perfiles_tono")):
    return {**{t: Tabla(get_sb, t).destino(forzar=True) for t in tablas}, "aviso": ""}
