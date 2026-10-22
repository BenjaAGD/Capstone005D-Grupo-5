# -*- coding: utf-8 -*-
"""
Recalcula con Gemini los embeddings de los documentos que se indexaron con NVIDIA.

Los vectores de modelos distintos NO son comparables (aunque ambos tengan 2048 dimensiones): si no se
recalculan, la búsqueda del chat devuelve fragmentos irrelevantes. Este script no toca el texto ni los
análisis: solo reescribe la columna `embedding` de `document_chunks`.

    python reindexar_embeddings.py --solo-contar          # cuántos fragmentos hay, sin cambiar nada
    python reindexar_embeddings.py                        # recalcula todos los documentos
    python reindexar_embeddings.py --doc ID1 --doc ID2    # solo esos documentos
    python reindexar_embeddings.py --lote 32              # tamaño de lote (por defecto 32)

Se puede interrumpir con Ctrl+C y volver a correr: marca el avance en reindexar_avance.json
(usa --desde-cero para ignorarlo). Requiere SUPABASE_URL, SUPABASE_KEY y GEMINI_API_KEY en .env.
"""
import argparse
import json
import os
import sys
import time

from dotenv import load_dotenv

load_dotenv()

AVANCE = "reindexar_avance.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--doc", action="append", default=[])
    ap.add_argument("--lote", type=int, default=32)
    ap.add_argument("--solo-contar", action="store_true")
    ap.add_argument("--desde-cero", action="store_true")
    a = ap.parse_args()

    url, key = os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_KEY")
    if not url or not key:
        print("Faltan SUPABASE_URL y SUPABASE_KEY en el .env")
        return 2
    from supabase import create_client
    import ia_config as ia
    if not a.solo_contar and not ia.estado_ia()["llaves_configuradas"]:
        print("Falta GEMINI_API_KEY en el .env")
        return 2
    sb = create_client(url, key)

    docs = [d["id"] for d in (sb.table("documentos").select("id,titulo").execute().data or [])] if not a.doc else a.doc
    hechos = {}
    if not a.desde_cero and os.path.exists(AVANCE):
        try:
            hechos = json.load(open(AVANCE, encoding="utf-8"))
        except Exception:
            hechos = {}

    total = 0
    pendientes = {}
    for d in docs:
        ids = []
        desde = 0
        while True:                       # paginado: Supabase entrega máximo 1.000 filas por consulta
            filas = sb.table("document_chunks").select("id").eq("document_id", d).order("id").range(desde, desde + 999).execute().data or []
            ids += [f["id"] for f in filas]
            if len(filas) < 1000:
                break
            desde += 1000
        ya = set(hechos.get(d, []))
        pendientes[d] = [i for i in ids if i not in ya]
        total += len(pendientes[d])
        print(f"  {d}: {len(ids)} fragmentos, {len(pendientes[d])} por recalcular")
    print(f"Total por recalcular: {total}")
    if a.solo_contar or not total:
        return 0

    n = 0
    t0 = time.time()
    try:
        for d, ids in pendientes.items():
            for i in range(0, len(ids), a.lote):
                lote = ids[i:i + a.lote]
                filas = sb.table("document_chunks").select("id,content").in_("id", lote).execute().data or []
                if not filas:
                    continue
                embs = ia.generar_embeddings_batch([f["content"] for f in filas], tarea="documento")
                for f, e in zip(filas, embs):
                    sb.table("document_chunks").update({"embedding": e}).eq("id", f["id"]).execute()
                hechos.setdefault(d, []).extend(f["id"] for f in filas)
                json.dump(hechos, open(AVANCE, "w", encoding="utf-8"))
                n += len(filas)
                print(f"\r  {n}/{total} fragmentos ({time.time() - t0:.0f} s)", end="", flush=True)
    except KeyboardInterrupt:
        print("\nInterrumpido. Vuelve a correr el script para continuar donde quedó.")
        return 130
    print("\nListo. Si todo salió bien puedes borrar", AVANCE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
