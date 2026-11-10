# -*- coding: utf-8 -*-
"""Perfil de tono de la memoria anual (Frente D1) y agente Redactor de memoria.

El gerente elige memorias anteriores ya subidas (al menos tres). El Redactor extrae un perfil de tono
editable: persona y formalidad, largo típico, vocabulario frecuente y a evitar, cómo se presentan las
cifras y cómo cierran las secciones. El gerente lo corrige y lo aprueba; desde ahí los borradores de la
memoria lo siguen. Cuando una memoria nueva se aprueba, se suma al corpus y el perfil se vuelve a extraer.

Cuidados: el perfil guarda rasgos y patrones breves, nunca párrafos copiados; y las cifras de años
pasados no deben colarse en el texto del año actual (lo revisa el verificador en memoria.py).
"""
import re
import unicodedata
from collections import Counter
from datetime import datetime

from fastapi import APIRouter, Body
from fastapi.responses import JSONResponse

from persistencia import Tabla, ahora_iso

MARCA_REDACTOR = "[REDACTOR TONO DIRECTA]"
MIN_MEMORIAS = 3
EMPRESA_DEFECTO = "principal"
CAMPOS_TEXTO = ("persona", "formalidad", "largo_capitulos", "cifras", "cierres")
CAMPOS_LISTA = ("vocabulario_frecuente", "vocabulario_evitar", "rasgos")

_VACIAS = set("""de la que el en y a los del se las por un para con no una su al lo como mas pero sus le ya o este si porque
esta entre cuando muy sin sobre tambien me hasta hay donde quien desde todo nos durante todos uno les ni contra otros ese eso
ante ellos e esto mi antes algunos que unos yo otro otras otra el tanto esa estos mucho quienes nada muchos cual poco ella
estar estas algunas algo nosotros cada ano anos ser fue son han sido esta este estos estas asi dicho dicha cuyo mediante
segun parte respecto ademas tanto dentro bajo tras via compania sociedad empresa""".split())


def _norm(t):
    t = unicodedata.normalize("NFD", str(t or "").lower())
    return "".join(c for c in t if unicodedata.category(c) != "Mn")


def anio_de(nombre, chunks=None):
    """Año del documento: primero el nombre del archivo; si no, la fecha de corte del texto."""
    m = re.findall(r"(?<!\d)(20\d{2}|19\d{2})(?!\d)", str(nombre or ""))
    if m:
        return int(m[-1])
    if chunks:
        try:
            import verificador
            fc = verificador.inferir_fecha_corte(chunks[:200])
            if fc:
                return fc.year
        except Exception:  # noqa: BLE001
            pass
    return None


def medidas_estilo(textos):
    """Rasgos medidos por código (no dependen de la IA)."""
    texto = " ".join(textos)
    oraciones = [o for o in re.split(r"(?<=[.!?])\s+", texto) if len(o.split()) >= 4]
    palabras_or = [len(o.split()) for o in oraciones]
    n = _norm(texto)
    primera = len(re.findall(r"\b(nuestr[oa]s?|hemos|logramos|alcanzamos|seguimos|contamos|queremos|nosotros)\b", n))
    tercera = len(re.findall(r"\b(la compania|la sociedad|la empresa|el grupo)\b", n))
    formatos = {
        "US$ millones": len(re.findall(r"us\$\s?[\d.,]+\s+millones", n)),
        "MUS$": len(re.findall(r"\bmus\$", n)),
        "MMUS$": len(re.findall(r"\bmmus\$", n)),
        "MM$": len(re.findall(r"\bmm\$", n)),
        "UF": len(re.findall(r"\buf\b", n)),
        "porcentajes": len(re.findall(r"\d\s?%", n)),
    }
    cuenta = Counter(w for w in re.findall(r"[a-zñ]{6,}", n) if w not in _VACIAS)
    total_pers = max(1, primera + tercera)
    return {
        "oraciones_medidas": len(palabras_or),
        "palabras_por_oracion": round(sum(palabras_or) / max(1, len(palabras_or)), 1),
        "primera_persona_pct": round(100 * primera / total_pers),
        "tercera_persona_pct": round(100 * tercera / total_pers),
        "formatos_cifras": {k: v for k, v in formatos.items() if v},
        "terminos_frecuentes": [w for w, _ in cuenta.most_common(15)],
    }


def _muestra(chunks, max_chars=5000):
    """Carta del presidente o gerente (inicio del documento) + fragmentos repartidos por el resto."""
    textos = [(c.get("content") or "").strip() for c in chunks if (c.get("content") or "").strip()]
    if not textos:
        return ""
    carta = [t for t in textos[:40] if re.search(r"(?i)se[ñn]ores accionistas|carta del|estimad[oa]s", t)]
    base = (carta[:3] or textos[:3])
    paso = max(1, len(textos) // 6)
    resto = [t for i, t in enumerate(textos) if i % paso == 0 and t not in base][:6]
    out, total = [], 0
    for t in base + resto:
        t = re.sub(r"\s+", " ", t)[:900]
        if total + len(t) > max_chars:
            break
        out.append(t)
        total += len(t)
    return "\n---\n".join(out)


def _copia_textual(texto, corpus_norm):
    pal = _norm(texto).split()
    for i in range(0, max(0, len(pal) - 7)):
        if " ".join(pal[i:i + 8]) in corpus_norm:
            return True
    return False


def _sanear_perfil(data, corpus_norm):
    """El perfil guarda rasgos breves: textos de hasta 300 caracteres, listas cortas y nada copiado del corpus."""
    p = {}
    for k in CAMPOS_TEXTO:
        v = " ".join(str((data or {}).get(k) or "").split())[:300]
        p[k] = "" if _copia_textual(v, corpus_norm) else v
    for k in CAMPOS_LISTA:
        lista = (data or {}).get(k) or []
        if isinstance(lista, str):
            lista = [x.strip() for x in re.split(r"[;\n]", lista)]
        limpia = []
        for x in lista:
            x = " ".join(str(x).split())[:90]
            if x and not _copia_textual(x, corpus_norm) and x not in limpia:
                limpia.append(x)
        p[k] = limpia[:12]
    return p


def extraer_perfil(get_sb, ids, empresa=None):
    import ia_config as _ia
    from modulos_base import cargar_chunks, info_documento
    sb = get_sb()
    if not ids:
        raise ValueError("Elige al menos una memoria anterior.")
    corpus, textos, muestras = [], [], []
    for did in ids:
        chunks = cargar_chunks(sb, did)
        info = info_documento(sb, did) or {}
        nombre = info.get("nombre") or info.get("titulo") or info.get("nombre_archivo") or did
        corpus.append({"document_id": did, "nombre": nombre, "anio": anio_de(nombre, chunks)})
        textos.extend(c.get("content") or "" for c in chunks)
        muestras.append(f"### {nombre}\n{_muestra(chunks)}")
    medidas = medidas_estilo(textos)
    corpus_norm = " ".join(" ".join(_norm(t).split()) for t in textos)
    sistema = (
        f"{MARCA_REDACTOR}\nEres el Redactor de memoria de DIRECTA. Lee extractos de memorias anuales anteriores de una "
        "empresa y describe su TONO para que los borradores nuevos suenen como ellas. Devuelve rasgos y patrones breves, "
        "NUNCA frases copiadas de los extractos ni cifras. Responde ÚNICAMENTE con este JSON:\n"
        '{"persona":"en qué persona escribe (primera del plural, tercera: la Compañía…) y a quién se dirige",'
        '"formalidad":"nivel de formalidad y registro","largo_capitulos":"largo típico de párrafos y capítulos",'
        '"vocabulario_frecuente":["palabras o giros típicos"],"vocabulario_evitar":["palabras o giros que no usa"],'
        '"cifras":"cómo presenta las cifras (unidad, decimales, comparación con el año anterior)",'
        '"cierres":"cómo cierra las secciones y la carta","rasgos":["otros rasgos de estilo"]}'
    )
    usuario = (f"MEDIDAS POR CÓDIGO: {medidas}\n\nEXTRACTOS DE LAS MEMORIAS:\n" + "\n\n".join(muestras)[:14000]
               + "\n\nDevuelve el JSON.")
    texto = _ia.llamar_llm_chat(sistema, usuario, temperatura=0.2, max_tokens=1200, json_mode=True)
    perfil = _sanear_perfil(_ia.parsear_json_respuesta(texto), corpus_norm)
    tabla = Tabla(get_sb, "perfiles_tono")
    previos = tabla.listar(limite=1, empresa=empresa or EMPRESA_DEFECTO)
    version = int((previos[0].get("version") if previos else 0) or 0) + 1
    return tabla.insertar({
        "empresa": empresa or EMPRESA_DEFECTO, "version": version, "estado": "borrador",
        "perfil": perfil, "medidas": medidas, "corpus": corpus, "editado": False,
        "aviso": (f"Se usaron {len(ids)} memorias; se recomiendan al menos {MIN_MEMORIAS}." if len(ids) < MIN_MEMORIAS else ""),
        "actualizado_en": ahora_iso(),
    })


def perfil_actual(get_sb, empresa=None):
    filas = Tabla(get_sb, "perfiles_tono").listar(limite=20, empresa=empresa or EMPRESA_DEFECTO)
    return filas[0] if filas else None


def perfil_aprobado(get_sb, empresa=None):
    filas = Tabla(get_sb, "perfiles_tono").listar(limite=20, empresa=empresa or EMPRESA_DEFECTO, estado="aprobado")
    return filas[0] if filas else None


def guardar_perfil(get_sb, id_, perfil=None, aprobar=False):
    tabla = Tabla(get_sb, "perfiles_tono")
    fila = tabla.obtener(id_)
    if not fila:
        raise ValueError("Perfil no encontrado")
    cambios = {"actualizado_en": ahora_iso()}
    if perfil is not None:
        cambios["perfil"] = _sanear_perfil(perfil, "")
        cambios["editado"] = True
    if aprobar:
        cambios["estado"] = "aprobado"
        cambios["aprobado_en"] = ahora_iso()
        # Solo un perfil aprobado por empresa: los anteriores quedan como históricos.
        for otro in tabla.listar(limite=50, empresa=fila.get("empresa"), estado="aprobado"):
            if otro["id"] != id_:
                tabla.actualizar(otro["id"], {"estado": "historico"})
    return tabla.actualizar(id_, cambios)


def agregar_al_corpus(get_sb, document_id, empresa=None):
    """Una memoria nueva aprobada se suma al corpus y el perfil se vuelve a extraer (queda en borrador)."""
    actual = perfil_aprobado(get_sb, empresa) or perfil_actual(get_sb, empresa)
    ids = [c["document_id"] for c in (actual or {}).get("corpus", [])]
    if document_id not in ids:
        ids.append(document_id)
    return extraer_perfil(get_sb, ids, empresa)


def bloque_para_prompt(perfil_fila):
    """Texto que se agrega al prompt del borrador de memoria."""
    if not perfil_fila:
        return ""
    p = perfil_fila.get("perfil") or {}
    m = perfil_fila.get("medidas") or {}
    lineas = [f"- Persona: {p.get('persona')}" if p.get("persona") else "",
              f"- Formalidad: {p.get('formalidad')}" if p.get("formalidad") else "",
              f"- Largo: {p.get('largo_capitulos')}" if p.get("largo_capitulos") else "",
              f"- Cifras: {p.get('cifras')}" if p.get("cifras") else "",
              f"- Cierres: {p.get('cierres')}" if p.get("cierres") else "",
              ("- Vocabulario típico: " + ", ".join(p["vocabulario_frecuente"])) if p.get("vocabulario_frecuente") else "",
              ("- Evita: " + ", ".join(p["vocabulario_evitar"])) if p.get("vocabulario_evitar") else "",
              ("- Otros rasgos: " + "; ".join(p["rasgos"])) if p.get("rasgos") else "",
              f"- Oraciones de unas {m.get('palabras_por_oracion')} palabras en promedio." if m.get("palabras_por_oracion") else ""]
    return ("PERFIL DE TONO DE LA EMPRESA (aprobado por el Gerente General). Escribe como sus memorias anteriores, "
            "sin copiar frases de ellas y sin usar cifras de otros años:\n" + "\n".join(x for x in lineas if x))


def crear_router(get_supabase):
    router = APIRouter()

    def err(e):
        return JSONResponse({"ok": False, "error": str(e)[:300]})

    @router.get("/api/memoria/perfil-tono")
    def api_perfil(empresa: str = ""):
        try:
            return {"ok": True, "perfil": perfil_actual(get_supabase, empresa or None),
                    "aprobado": perfil_aprobado(get_supabase, empresa or None), "minimo_memorias": MIN_MEMORIAS}
        except Exception as e:  # noqa: BLE001
            return err(e)

    @router.post("/api/memoria/perfil-tono/extraer")
    def api_extraer(payload: dict = Body(default={})):
        try:
            ids = [str(x) for x in ((payload or {}).get("documentos") or []) if str(x).strip()]
            return {"ok": True, "perfil": extraer_perfil(get_supabase, ids, (payload or {}).get("empresa") or None)}
        except Exception as e:  # noqa: BLE001
            return err(e)

    @router.put("/api/memoria/perfil-tono/{id_}")
    def api_guardar(id_: str, payload: dict = Body(default={})):
        try:
            p = (payload or {}).get("perfil")
            return {"ok": True, "perfil": guardar_perfil(get_supabase, id_, p if isinstance(p, dict) else None,
                                                         bool((payload or {}).get("aprobar")))}
        except Exception as e:  # noqa: BLE001
            return err(e)

    @router.post("/api/memoria/perfil-tono/corpus")
    def api_corpus(payload: dict = Body(default={})):
        try:
            did = str((payload or {}).get("document_id") or "")
            if not did:
                return err("Falta document_id")
            return {"ok": True, "perfil": agregar_al_corpus(get_supabase, did, (payload or {}).get("empresa") or None)}
        except Exception as e:  # noqa: BLE001
            return err(e)

    return router


if __name__ == "__main__":  # prueba rápida de las medidas
    print(medidas_estilo(["Señores accionistas: Durante el ejercicio 2024 la Compañía alcanzó una utilidad de US$ 388,3 "
                          "millones. Hemos seguido avanzando en nuestra estrategia."]), datetime.now())
