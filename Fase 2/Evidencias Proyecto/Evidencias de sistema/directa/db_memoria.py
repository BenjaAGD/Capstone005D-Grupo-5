# -*- coding: utf-8 -*-
"""
Base de datos EN MEMORIA con la misma interfaz mínima que usa el proyecto de supabase-py.

Para qué sirve
  * Modo demo: `DIRECTA_DB=memoria` arranca la app completa sin Supabase (nada se guarda al apagar).
  * Pruebas automáticas: se usa junto con un Gemini falso para recorrer el flujo completo.

Soporta lo que usa Directa: table().select/insert/update/delete/upsert, eq, neq, in_, ilike, gt, gte, lt, lte,
is_, order, range, limit, count="exact", y rpc("match_document_chunks").
NO es un reemplazo de Supabase en producción.
"""
import copy
import itertools
import math
import re
import threading
import uuid


class _Resp:
    def __init__(self, data, count=None):
        self.data = data
        self.count = count


class _Consulta:
    def __init__(self, db, tabla):
        self.db, self.tabla = db, tabla
        self._op, self._cols, self._payload = "select", "*", None
        self._filtros, self._orden, self._desde, self._hasta = [], None, None, None
        self._limite, self._contar, self._on_conflict = None, False, None

    # ---- operaciones
    def select(self, cols="*", count=None):
        self._op, self._cols, self._contar = "select", cols or "*", (count == "exact")
        return self

    def insert(self, payload):
        self._op, self._payload = "insert", payload
        return self

    def upsert(self, payload, on_conflict=None):
        self._op, self._payload, self._on_conflict = "upsert", payload, on_conflict
        return self

    def update(self, payload):
        self._op, self._payload = "update", payload
        return self

    def delete(self):
        self._op = "delete"
        return self

    # ---- filtros
    def _f(self, tipo, col, val):
        self._filtros.append((tipo, col, val))
        return self

    def eq(self, c, v): return self._f("eq", c, v)
    def neq(self, c, v): return self._f("neq", c, v)
    def gt(self, c, v): return self._f("gt", c, v)
    def gte(self, c, v): return self._f("gte", c, v)
    def lt(self, c, v): return self._f("lt", c, v)
    def lte(self, c, v): return self._f("lte", c, v)
    def in_(self, c, v): return self._f("in", c, list(v))
    def ilike(self, c, v): return self._f("ilike", c, v)
    def is_(self, c, v): return self._f("is", c, v)

    def order(self, col, desc=False, **_):
        self._orden = (col, bool(desc))
        return self

    def range(self, desde, hasta):
        self._desde, self._hasta = desde, hasta
        return self

    def limit(self, n):
        self._limite = n
        return self

    # ---- ejecución
    def _coincide(self, fila):
        for tipo, c, v in self._filtros:
            x = fila.get(c)
            if tipo == "eq" and x != v: return False
            if tipo == "neq" and x == v: return False
            if tipo == "in" and x not in v: return False
            if tipo in ("gt", "gte", "lt", "lte"):
                if x is None: return False
                if tipo == "gt" and not x > v: return False
                if tipo == "gte" and not x >= v: return False
                if tipo == "lt" and not x < v: return False
                if tipo == "lte" and not x <= v: return False
            if tipo == "ilike":
                patron = "^" + re.escape(str(v)).replace("%", ".*").replace("_", ".") + "$"
                if not re.match(patron, str(x or ""), re.I | re.S): return False
            if tipo == "is":
                if str(v).lower() == "null" and x is not None: return False
        return True

    def execute(self):
        with self.db._lock:
            filas = self.db._tablas.setdefault(self.tabla, [])
            if self._op in ("insert", "upsert"):
                lote = self._payload if isinstance(self._payload, list) else [self._payload]
                salida = []
                for f in lote:
                    f = copy.deepcopy(f)
                    if self._op == "upsert" and self._on_conflict:
                        claves = [c.strip() for c in self._on_conflict.split(",")]
                        for ex in filas:
                            if all(ex.get(k) == f.get(k) for k in claves):
                                ex.update(f)
                                salida.append(copy.deepcopy(ex))
                                break
                        else:
                            self.db._asignar_id(self.tabla, f); filas.append(f); salida.append(copy.deepcopy(f))
                    else:
                        self.db._asignar_id(self.tabla, f); filas.append(f); salida.append(copy.deepcopy(f))
                return _Resp(salida)
            if self._op == "update":
                n = []
                for f in filas:
                    if self._coincide(f):
                        f.update(copy.deepcopy(self._payload)); n.append(copy.deepcopy(f))
                return _Resp(n)
            if self._op == "delete":
                borradas = [f for f in filas if self._coincide(f)]
                self.db._tablas[self.tabla] = [f for f in filas if not self._coincide(f)]
                return _Resp([copy.deepcopy(f) for f in borradas])
            sel = [f for f in filas if self._coincide(f)]
            if self._orden:
                c, desc = self._orden
                sel.sort(key=lambda f: (f.get(c) is None, f.get(c)), reverse=desc)
            total = len(sel)
            if self._desde is not None:
                sel = sel[self._desde:(self._hasta or 0) + 1]
            if self._limite is not None:
                sel = sel[:self._limite]
            cols = None if self._cols.strip() == "*" else [c.strip() for c in self._cols.split(",") if c.strip()]
            if cols:
                sel = [{c: f.get(c) for c in cols} for f in sel]
            else:
                sel = [copy.deepcopy(f) for f in sel]
            return _Resp(sel, total if self._contar else None)


class _Rpc:
    def __init__(self, db, nombre, args):
        self.db, self.nombre, self.args = db, nombre, args

    def execute(self):
        if self.nombre != "match_document_chunks":
            raise Exception(f"rpc desconocida: {self.nombre}")
        a = self.args
        q = a["query_embedding"]
        out = []
        with self.db._lock:
            for f in self.db._tablas.get("document_chunks", []):
                if a.get("p_document_id") and f.get("document_id") != a["p_document_id"]:
                    continue
                e = f.get("embedding")
                if not e:
                    continue
                dot = sum(x * y for x, y in zip(q, e))
                nq = math.sqrt(sum(x * x for x in q)) or 1.0
                ne = math.sqrt(sum(x * x for x in e)) or 1.0
                sim = dot / (nq * ne)
                if sim >= a.get("match_threshold", 0.0):
                    r = {k: v for k, v in f.items() if k != "embedding"}
                    r["similarity"] = sim
                    out.append(r)
        out.sort(key=lambda r: -r["similarity"])
        return _Resp(out[: int(a.get("match_count", 8))])


class FakeSupabase:
    def __init__(self):
        self._tablas = {}
        self._lock = threading.RLock()
        self._secuencias = {}

    def _asignar_id(self, tabla, fila):
        if "id" in fila and fila["id"] is not None:
            return
        if tabla == "document_chunks":
            self._secuencias.setdefault(tabla, itertools.count(1))
            fila["id"] = next(self._secuencias[tabla])      # ordenable, como pide ampliar_chunks
        elif tabla in ("documentos",):
            return
        else:
            fila["id"] = str(uuid.uuid4())
        fila.setdefault("creado_en", _ahora())

    def table(self, nombre):
        return _Consulta(self, nombre)

    def rpc(self, nombre, args):
        return _Rpc(self, nombre, args)


def _ahora():
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat()
