# -*- coding: utf-8 -*-
"""
DIRECTA — Lectura del documento dentro de la app.

Arregla tres problemas del lector anterior (/vista-previa):
  1. Los fragmentos se pedían ordenados solo por página, así que dentro de una misma página podían
     llegar desordenados. Ahora se ordena por (página, orden); la columna `orden` es opcional (ver
     migracion_v5_orden_chunks.sql). Sin ella, el orden dentro de la página queda como antes.
  2. Los fragmentos se cortan con 150 caracteres de traslape; al pegarlos, ese texto salía repetido.
     Aquí se detecta y se quita el traslape.
  3. El contador "página X de N+" contaba solo las páginas ya cargadas. Ahora se entrega la lista real
     de páginas con texto.

Endpoints (todos GET, sin efectos secundarios):
  /api/documentos/{id}/lectura            -> datos del documento + lista de páginas con texto
  /api/documentos/{id}/pagina/{numero}    -> texto de una página (ordenado y sin repeticiones)
  /api/documentos/{id}/buscar?q=...       -> coincidencias de un texto dentro del documento

Conexión en main.py: agregar "lectura" a la lista de módulos que se cargan con crear_router.
"""
from fastapi import APIRouter
from fastapi.responses import JSONResponse, Response

_TRASLAPE_MAX = 160   # el splitter usa 150; no se sube más para no borrar texto legítimamente repetido
_TRASLAPE_MIN = 25    # menos que esto podría ser una coincidencia casual
_BLOQUE = 1000        # PostgREST entrega como máximo 1000 filas por consulta


def quitar_traslape(anterior: str, nuevo: str) -> str:
    """Si `nuevo` empieza repitiendo el final de `anterior`, devuelve `nuevo` sin esa parte."""
    a = (anterior or "").rstrip()
    b = (nuevo or "").lstrip()
    tope = min(_TRASLAPE_MAX, len(a), len(b))
    for k in range(tope, _TRASLAPE_MIN - 1, -1):
        if a.endswith(b[:k]):
            return b[k:].lstrip()
    return b


def unir_fragmentos(textos):
    """Une los fragmentos de una página en párrafos, sin el texto repetido por el traslape."""
    partes = []
    previo = ""
    for t in textos:
        t = (t or "").strip()
        if not t:
            continue
        limpio = quitar_traslape(previo, t) if previo else t
        if limpio:
            partes.append(limpio)
        previo = t
    return "\n\n".join(partes)


def _escapar_like(q: str) -> str:
    return q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def crear_router(get_supabase):
    router = APIRouter()

    def err(e, codigo=200):
        return JSONResponse({"ok": False, "error": str(e)[:300]}, status_code=codigo)

    def _consulta_chunks(columnas, document_id):
        sb = get_supabase()
        return sb.table("document_chunks").select(columnas).eq("document_id", document_id)

    def _chunks_de_pagina(document_id, numero):
        """Devuelve (lista_de_textos, hay_orden). Prueba con `orden`; si la columna no existe, sin ella."""
        try:
            r = (_consulta_chunks("content, orden", document_id).eq("page_number", numero)
                 .order("orden", desc=False, nullsfirst=False).order("creado_en").execute())
            return [x.get("content") or "" for x in (r.data or [])], True
        except Exception:  # noqa: BLE001 — la columna `orden` puede no existir todavía
            r = (_consulta_chunks("content", document_id).eq("page_number", numero)
                 .order("creado_en").execute())
            return [x.get("content") or "" for x in (r.data or [])], False

    @router.get("/api/documentos/{document_id}/lectura")
    def lectura_info(document_id: str):
        try:
            sb = get_supabase()
            d = (sb.table("documentos").select("id, titulo, nombre_archivo, total_paginas, estado")
                 .eq("id", document_id).limit(1).execute()).data or []
            if not d:
                return err("Documento no encontrado")
            paginas, desde = set(), 0
            while True:
                bloque = (_consulta_chunks("page_number", document_id)
                          .range(desde, desde + _BLOQUE - 1).execute()).data or []
                for fila in bloque:
                    n = fila.get("page_number")
                    if isinstance(n, int):
                        paginas.add(n)
                if len(bloque) < _BLOQUE:
                    break
                desde += _BLOQUE
            return {"ok": True, "documento": d[0], "paginas": sorted(paginas)}
        except Exception as e:  # noqa: BLE001
            print("[LECTURA] Error:", e, flush=True)
            return err(e)

    @router.get("/api/documentos/{document_id}/pagina/{numero}")
    def lectura_pagina(document_id: str, numero: int):
        try:
            textos, hay_orden = _chunks_de_pagina(document_id, numero)
            return {"ok": True, "numero": numero, "texto": unir_fragmentos(textos),
                    "orden_garantizado": hay_orden}
        except Exception as e:  # noqa: BLE001
            print("[LECTURA] Error:", e, flush=True)
            return err(e)

    @router.get("/api/documentos/{document_id}/buscar")
    def lectura_buscar(document_id: str, q: str = "", limite: int = 40):
        q = (q or "").strip()
        if len(q) < 3:
            return {"ok": True, "q": q, "coincidencias": [], "paginas": 0,
                    "aviso": "Escribe al menos 3 letras."}
        limite = max(1, min(int(limite), 80))
        try:
            filas = (_consulta_chunks("page_number, content", document_id)
                     .ilike("content", f"%{_escapar_like(q)}%")
                     .order("page_number").limit(limite).execute()).data or []
            ql = q.lower()
            salida = []
            for f in filas:
                texto = " ".join((f.get("content") or "").split())
                i = texto.lower().find(ql)
                if i < 0:
                    continue
                ini = max(0, i - 70)
                fin = min(len(texto), i + len(q) + 90)
                salida.append({
                    "pagina": f.get("page_number"),
                    "antes": ("…" if ini > 0 else "") + texto[ini:i],
                    "coincide": texto[i:i + len(q)],
                    "despues": texto[i + len(q):fin] + ("…" if fin < len(texto) else ""),
                })
            return {"ok": True, "q": q, "coincidencias": salida,
                    "paginas": len({s["pagina"] for s in salida}),
                    "recortado": len(filas) >= limite}
        except Exception as e:  # noqa: BLE001
            print("[LECTURA] Error buscando:", e, flush=True)
            return err(e)

    # ------------------------------------------------------------------ página original (imagen)
    # El PDF original se guarda en Supabase Storage (bucket "documentos") al subirlo. Así el lector muestra
    # la página tal cual es, con su orden real, en vez del texto extraído (que pierde columnas y tablas).
    _cache_pdf = {}

    def _pdf_original(document_id):
        import time
        hit = _cache_pdf.get(document_id)
        if hit and time.time() - hit[0] < 900:
            return hit[1]
        datos = get_supabase().storage.from_(BUCKET).download(ruta_original(document_id))
        if len(_cache_pdf) >= 3:
            _cache_pdf.pop(next(iter(_cache_pdf)))
        _cache_pdf[document_id] = (time.time(), datos)
        return datos

    @router.get("/api/documentos/{document_id}/original")
    def lectura_original(document_id: str):
        try:
            import pypdfium2 as pdfium
            pdf = pdfium.PdfDocument(_pdf_original(document_id))
            return {"ok": True, "paginas": len(pdf)}
        except Exception as e:  # noqa: BLE001 — documento subido antes del cambio o bucket sin crear
            return {"ok": False, "error": f"No hay copia original de este documento ({str(e)[:120]})."}

    @router.get("/api/documentos/{document_id}/pagina/{numero}/imagen")
    def lectura_pagina_imagen(document_id: str, numero: int, ancho: int = 1100):
        try:
            import io
            import pypdfium2 as pdfium
            pdf = pdfium.PdfDocument(_pdf_original(document_id))
            if numero < 1 or numero > len(pdf):
                return err("Esa página no existe.", 404)
            pagina = pdf[numero - 1]
            escala = max(0.5, min(3.0, max(400, min(ancho, 1800)) / float(pagina.get_width())))
            imagen = pagina.render(scale=escala).to_pil().convert("RGB")
            buf = io.BytesIO()
            imagen.save(buf, format="JPEG", quality=82, optimize=True)
            return Response(content=buf.getvalue(), media_type="image/jpeg",
                            headers={"Cache-Control": "private, max-age=3600"})
        except Exception as e:  # noqa: BLE001
            return err(f"No se pudo mostrar la página: {e}", 500)

    return router


BUCKET = "documentos"


def ruta_original(document_id: str) -> str:
    import re
    return re.sub(r"[^A-Za-z0-9_.-]", "_", document_id)[:80] + ".pdf"


def guardar_original(sb, document_id: str, datos: bytes):
    """Guarda el PDF original en Storage. Si el bucket no existe, avisa en el log y sigue (no rompe la subida)."""
    try:
        sb.storage.from_(BUCKET).upload(ruta_original(document_id), datos,
                                        {"content-type": "application/pdf", "upsert": "true"})
    except Exception as e:  # noqa: BLE001
        print(f"[LECTURA] No se guardó el original de {document_id} (¿existe el bucket '{BUCKET}'?): {e}", flush=True)


def borrar_original(sb, document_id: str):
    try:
        sb.storage.from_(BUCKET).remove([ruta_original(document_id)])
    except Exception:  # noqa: BLE001
        pass
