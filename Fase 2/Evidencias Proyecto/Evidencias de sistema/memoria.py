# -*- coding: utf-8 -*-
"""
DIRECTA v2 — Módulo Memoria Anual (sin IA).

Organiza la memoria anual por los capítulos que define la NCG 461 de la CMF y, para cada uno,
muestra (1) qué evidencia hay en los documentos subidos y (2) qué señalaron los agentes
relacionados. NO verifica el cumplimiento de la norma: busca palabras clave en los fragmentos
guardados y sirve como lista de trabajo para el equipo que redacta.

Referencia de la estructura: NCG 461 (2021) de la CMF. La lista de capítulos y temas se tomó de un
resumen de la norma; confirmarla contra el texto oficial antes de usarla como checklist formal.

Conexión en main.py (3 líneas, después de crear `app`):

    from memoria import crear_router as _mem
    app.include_router(_mem(lambda: supabase))
"""
import os
import re
from datetime import datetime
from functools import lru_cache

from fastapi import APIRouter, Body
from fastapi.responses import FileResponse, JSONResponse, Response

from modulos_base import (
    normalizar, cargar_chunks, cargar_analisis, info_documento, listar_documentos,
    senales_de, score_de, tiene_info, nombre_corto, agentes_analizables, esc_pdf, html_a_pdf, pagina_pdf,
)

# Cada tema: id, nombre y palabras clave (sin tildes, en minúscula). Una palabra clave coincide si
# aparece como inicio de palabra ("accidente" coincide con "accidentes"). Son frases lo bastante
# específicas para no confundirse con texto financiero corriente.
CAPITULOS = [
    {"id": "indice", "numero": 1, "titulo": "Índice de contenidos",
     "descripcion": "Referencia a estándares internacionales y ubicación de cada contenido de la norma.",
     "agentes": [],
     "temas": [
         {"id": "indice", "nombre": "Índice o tabla de contenidos", "claves": ["indice de contenido", "tabla de contenido", "indice de la norma", "contenidos de la norma", "indice ncg", "indice gri", "indice sasb"], "claves_inicio": ["indice"]},
         {"id": "estandares", "nombre": "Referencia a estándares de reporte", "claves": ["gri ", "sasb", "iirc", "tcfd", "ifrs s1", "ifrs s2", "global reporting initiative"]},
     ]},
    {"id": "perfil", "numero": 2, "titulo": "Perfil de la entidad",
     "descripcion": "Misión, visión, propósito y valores; historia; control y accionistas; acciones y otros valores.",
     "agentes": ["legal", "estrategia"],
     "temas": [
         {"id": "mision", "nombre": "Misión, visión, propósito y valores", "claves": ["mision", "vision", "proposito", "nuestros valores", "valores corporativos", "principios corporativos"]},
         {"id": "historia", "nombre": "Reseña histórica desde la constitución", "claves": ["resena historica", "historia de la compania", "historia de la sociedad", "se constituyo", "fue constituida", "fundada en", "constitucion de la sociedad"]},
         {"id": "control", "nombre": "Situación de control y accionistas mayoritarios", "claves": ["controlador", "accionistas mayoritarios", "principales accionistas", "grupo controlador", "situacion de control", "12 mayores accionistas"]},
         {"id": "acciones", "nombre": "Acciones, series y derechos", "claves": ["serie de acciones", "acciones suscritas", "acciones pagadas", "derechos de las acciones", "capital suscrito", "politica de dividendos", "numero de acciones"]},
         {"id": "valores", "nombre": "Otros valores emitidos", "claves": ["bonos emitidos", "lineas de bonos", "efectos de comercio", "adr ", "otros valores emitidos", "clasificacion de riesgo"]},
     ]},
    {"id": "gobierno", "numero": 3, "titulo": "Gobierno corporativo",
     "descripcion": "Marco de gobernanza, directorio y comités, ejecutivos, buenas prácticas, riesgos y grupos de interés.",
     "agentes": ["legal", "riesgos", "compensacion", "stakeholders"],
     "temas": [
         {"id": "marco", "nombre": "Marco de gobernanza y estructura organizacional", "claves": ["gobierno corporativo", "gobernanza", "estructura organizacional", "organigrama", "marco de gobernanza"]},
         {"id": "directorio", "nombre": "Composición y funcionamiento del directorio", "claves": ["composicion del directorio", "miembros del directorio", "presidente del directorio", "sesiones del directorio", "director independiente", "directores independientes", "diversidad del directorio"]},
         {"id": "comites", "nombre": "Comités del directorio", "claves": ["comite de directores", "comite de auditoria", "comite de riesgos", "comite de compensaciones", "comite de sostenibilidad", "comites del directorio"]},
         {"id": "ejecutivos", "nombre": "Ejecutivos principales", "claves": ["ejecutivos principales", "gerente general", "plana ejecutiva", "alta administracion"]},
         {"id": "codigos", "nombre": "Adherencia a códigos de buen gobierno", "claves": ["buenas practicas", "codigo de etica", "codigo de conducta", "codigo de buen gobierno", "adherencia", "canal de denuncias", "modelo de prevencion de delitos"]},
         {"id": "riesgos", "nombre": "Gestión de riesgos", "claves": ["gestion de riesgos", "administracion de riesgos", "matriz de riesgos", "riesgos corporativos", "apetito de riesgo", "factores de riesgo", "riesgos financieros", "riesgo de liquidez", "riesgo de credito", "riesgo de mercado", "riesgos de la operacion", "ciberseguridad", "seguridad de la informacion"]},
         {"id": "interes", "nombre": "Relación con grupos de interés", "claves": ["grupos de interes", "partes interesadas", "stakeholders", "relacion con la comunidad", "relacion con inversionistas"]},
     ]},
    {"id": "estrategia", "numero": 4, "titulo": "Estrategia",
     "descripcion": "Horizontes de tiempo, objetivos estratégicos y planes de inversión.",
     "agentes": ["estrategia", "capital", "esg"],
     "temas": [
         {"id": "horizontes", "nombre": "Horizontes de tiempo (corto, mediano y largo plazo)", "claves": ["corto plazo", "mediano plazo", "largo plazo", "horizonte de tiempo", "horizontes"]},
         {"id": "objetivos", "nombre": "Objetivos estratégicos", "claves": ["objetivos estrategicos", "plan estrategico", "pilares estrategicos", "metas estrategicas", "estrategia de la compania"]},
         {"id": "inversion", "nombre": "Planes de inversión", "claves": ["plan de inversion", "planes de inversion", "capex", "proyectos de inversion", "inversiones planificadas"]},
         {"id": "clima", "nombre": "Estrategia climática y de sostenibilidad", "claves": ["cambio climatico", "descarbonizacion", "neutralidad de carbono", "objetivos de desarrollo sostenible", "ods ", "derechos humanos"]},
     ]},
    {"id": "personas", "numero": 5, "titulo": "Personas",
     "descripcion": "Dotación, formalidad laboral, equidad salarial, acoso, seguridad, postnatal, capacitación y subcontratación.",
     "agentes": ["rrhh", "compensacion"],
     "temas": [
         {"id": "dotacion", "nombre": "Dotación por sexo, nacionalidad, edad, antigüedad y discapacidad", "claves": ["dotacion", "numero de trabajadores", "nacionalidad", "antiguedad", "personas con discapacidad", "rango de edad"]},
         {"id": "formalidad", "nombre": "Formalidad laboral y adaptabilidad", "claves": ["formalidad laboral", "contrato indefinido", "plazo fijo", "adaptabilidad laboral", "teletrabajo"]},
         {"id": "equidad", "nombre": "Equidad salarial por sexo", "claves": ["equidad salarial", "brecha salarial", "igualdad salarial", "brecha de genero", "remuneracion promedio"]},
         {"id": "acoso", "nombre": "Acoso laboral y sexual", "claves": ["acoso laboral", "acoso sexual", "ley karin", "protocolo de acoso", "denuncias de acoso"]},
         {"id": "seguridad", "nombre": "Seguridad laboral", "claves": ["seguridad laboral", "accidentabilidad", "accidentes laborales", "seguridad y salud", "tasa de accidentes", "enfermedades profesionales"]},
         {"id": "postnatal", "nombre": "Permiso postnatal", "claves": ["postnatal", "permiso parental", "sala cuna"]},
         {"id": "capacitacion", "nombre": "Capacitación y beneficios", "claves": ["capacitacion", "horas de formacion", "beneficios sociales", "beneficios para los trabajadores", "desarrollo de talento", "plan de formacion"]},
         {"id": "subcontratacion", "nombre": "Política de subcontratación", "claves": ["subcontratacion", "subcontratistas", "contratistas", "trabajadores externos", "empresas de servicios transitorios"]},
     ]},
    {"id": "negocios", "numero": 6, "titulo": "Modelo de negocios",
     "descripcion": "Sector industrial, descripción de los negocios, grupos de interés, propiedades e inversiones.",
     "agentes": ["comercial", "operaciones"],
     "temas": [
         {"id": "sector", "nombre": "Sector industrial", "claves": ["sector industrial", "industria en que", "mercado en que opera", "competidores", "participacion de mercado"]},
         {"id": "descripcion", "nombre": "Descripción de los negocios", "claves": ["descripcion del negocio", "lineas de negocio", "productos y servicios", "modelo de negocio", "clientes principales"]},
         {"id": "propiedades", "nombre": "Propiedades e instalaciones", "claves": ["propiedades e instalaciones", "plantas productivas", "centros de distribucion", "bienes raices", "capacidad instalada"]},
         {"id": "filiales", "nombre": "Subsidiarias, asociadas e inversiones", "claves": ["subsidiarias", "filiales", "coligadas", "asociadas", "negocios conjuntos", "participacion en sociedades"]},
     ]},
    {"id": "proveedores", "numero": 7, "titulo": "Gestión de proveedores",
     "descripcion": "Política de pago a proveedores y evaluación de proveedores.",
     "agentes": ["operaciones"],
     "temas": [
         {"id": "pago", "nombre": "Política de pago a proveedores", "claves": ["politica de pago", "pago a proveedores", "plazo de pago", "periodo medio de pago", "ley de pago a 30 dias"]},
         {"id": "evaluacion", "nombre": "Evaluación de proveedores", "claves": ["evaluacion de proveedores", "homologacion de proveedores", "seleccion de proveedores", "auditoria a proveedores", "criterios ambientales y sociales"]},
     ]},
    {"id": "indicadores", "numero": 8, "titulo": "Indicadores",
     "descripcion": "Cumplimiento legal y normativo (clientes, trabajadores, medioambiente, libre competencia) e indicadores de sostenibilidad del sector.",
     "agentes": ["esg", "legal", "ciberseguridad"],
     "temas": [
         {"id": "cumplimiento_clientes", "nombre": "Cumplimiento: derechos de clientes y consumidores", "claves": ["derechos del consumidor", "proteccion al consumidor", "sernac", "reclamos de clientes", "sanciones a la compania"]},
         {"id": "cumplimiento_trabajadores", "nombre": "Cumplimiento: derechos de los trabajadores", "claves": ["inspeccion del trabajo", "normativa laboral", "multas laborales", "incumplimientos laborales"]},
         {"id": "cumplimiento_ambiental", "nombre": "Cumplimiento: obligaciones medioambientales", "claves": ["superintendencia del medio ambiente", "normativa ambiental", "obligaciones medioambientales", "resolucion de calificacion ambiental", "sancion ambiental", "materias medioambientales", "legislacion ambiental"], "claves_debiles": ["medio ambiente", "medioambient", "incidentes ambientales"]},
         {"id": "libre_competencia", "nombre": "Cumplimiento: libre competencia", "claves": ["libre competencia", "fne ", "fiscalia nacional economica", "defensa de la competencia"]},
         {"id": "sostenibilidad", "nombre": "Indicadores de sostenibilidad del sector", "claves": ["emisiones", "alcance 1", "alcance 2", "alcance 3", "huella de carbono", "consumo de energia", "consumo de agua", "residuos", "tco2"]},
     ]},
    {"id": "hechos", "numero": 9, "titulo": "Hechos relevantes o esenciales",
     "descripcion": "Resumen de los hechos divulgados en el período y su impacto en la entidad.",
     "agentes": ["legal", "financiero"],
     "temas": [
         {"id": "hechos", "nombre": "Resumen de hechos relevantes o esenciales del período", "claves": ["hecho esencial", "hechos esenciales", "hecho relevante", "hechos relevantes", "informacion esencial"]},
     ]},
    {"id": "comentarios", "numero": 10, "titulo": "Comentarios de accionistas y del comité de directores",
     "descripcion": "Síntesis de comentarios sobre la marcha de los negocios y proposiciones.",
     "agentes": ["stakeholders", "legal"],
     "temas": [
         {"id": "accionistas", "nombre": "Comentarios y proposiciones de accionistas", "claves": ["comentarios de accionistas", "proposiciones de accionistas", "accionistas minoritarios", "junta de accionistas", "carta de accionistas"]},
         {"id": "comite_dir", "nombre": "Comentarios y proposiciones del comité de directores", "claves": ["comite de directores", "proposiciones del comite", "informe del comite de directores"]},
     ]},
    {"id": "financieros", "numero": 11, "titulo": "Informes financieros",
     "descripcion": "Referencia a los estados financieros y sitios web donde están disponibles.",
     "agentes": ["financiero", "auditoria"],
     "temas": [
         {"id": "eeff", "nombre": "Estados financieros", "claves": ["estados financieros", "estado de situacion financiera", "estado de resultados", "estado de flujos de efectivo", "informe de los auditores", "opinion de los auditores"]},
         {"id": "sitio", "nombre": "Sitio web y disponibilidad", "claves": ["www.", "sitio web", "pagina web", "https://"]},
     ]},
]

MAX_PAGINAS_POR_TEMA = 8


@lru_cache(maxsize=None)
def _patron(clave):
    # inicio de palabra; las claves que terminan en espacio (p. ej. 'adr ') exigen palabra completa
    cola = r"(?![a-z0-9])" if clave.endswith(" ") else ""
    return re.compile(r"(?<![a-z0-9])" + re.escape(clave.strip()) + cola)


def _fragmento(original, pos, largo):
    a = max(0, pos - 70)
    b = min(len(original), pos + largo + 90)
    t = " ".join(original[a:b].split())
    return ("…" if a > 0 else "") + t + ("…" if b < len(original) else "")


PAGINA_INICIAL_MAX = 8   # las claves de "claves_inicio" (p. ej. el título "Índice") solo cuentan en estas primeras páginas


def buscar_evidencia(fuentes_chunks):
    """fuentes_chunks: [(doc_nombre, [chunks])]. Devuelve {(cap_id, tema_id): {...}}.

    Cada tema puede traer:
      claves         palabras específicas del tema (una sola ya basta para 'evidencia débil'; dos o una en 2+ páginas, 'fuerte')
      claves_debiles palabras más genéricas (p. ej. 'medio ambiente'): suman como pista pero nunca pasan de 'débil'
      claves_inicio  palabras que solo valen en las primeras páginas (p. ej. el título 'Índice')
    Las páginas que se muestran son las que más palabras distintas del tema reúnen (no solo las primeras del documento)."""
    textos = []
    for doc_nombre, chunks in fuentes_chunks:
        for c in chunks:
            contenido = c.get("content") or ""
            textos.append((doc_nombre, c.get("page_number"), contenido, normalizar(contenido)))
    out = {}
    for cap in CAPITULOS:
        for tema in cap["temas"]:
            fuertes = [(k, False) for k in tema["claves"]] + [(k, True) for k in tema.get("claves_inicio", [])]
            debiles = [(k, True) for k in tema.get("claves_debiles", [])]
            claves_vistas, fuertes_vistas, puntaje_pag, fragmento = set(), set(), {}, None
            for doc_nombre, pagina, original, norm in textos:
                for clave, solo_inicio in fuertes + debiles:
                    if solo_inicio and clave in tema.get("claves_inicio", []) and (pagina is None or pagina > PAGINA_INICIAL_MAX):
                        continue
                    m = _patron(clave).search(norm)
                    if not m:
                        continue
                    es_debil = (clave, True) in debiles
                    claves_vistas.add(clave)
                    if not es_debil:
                        fuertes_vistas.add(clave)
                    llave = (doc_nombre, pagina)
                    puntaje_pag.setdefault(llave, set()).add(clave)
                    if fragmento is None or (not es_debil and fragmento.get("debil")):
                        fragmento = {"doc": doc_nombre, "pagina": pagina, "debil": es_debil,
                                     "texto": _fragmento(original, m.start(), len(clave))}
            if not claves_vistas:
                nivel = "ninguna"
            elif fuertes_vistas and (len(fuertes_vistas) >= 2 or len(puntaje_pag) >= 2
                                     or fuertes_vistas & set(tema.get("claves_inicio", []))):
                nivel = "fuerte"
            else:
                nivel = "debil"
            # las páginas con más palabras distintas primero; luego se muestran en orden de lectura
            mejores = sorted(puntaje_pag.items(), key=lambda kv: (-len(kv[1]), kv[0][0], kv[0][1] or 0))[:MAX_PAGINAS_POR_TEMA]
            paginas = sorted(({"doc": d, "pagina": pg} for (d, pg), _ in mejores), key=lambda p: (p["doc"], p["pagina"] or 0))
            if fragmento:
                fragmento = {k: v for k, v in fragmento.items() if k != "debil"}
            out[(cap["id"], tema["id"])] = {
                "nivel": nivel, "claves": sorted(claves_vistas), "paginas": paginas,
                "n_paginas": len(puntaje_pag), "fragmento": fragmento,
            }
    return out


def construir_cobertura(sb, ids_documentos=None):
    docs_all = listar_documentos(sb)
    nombres = {d["id"]: (d.get("titulo") or d.get("nombre_archivo") or str(d["id"])) for d in docs_all}
    if not ids_documentos:
        ids_documentos = [d["id"] for d in docs_all]
    ids_documentos = [i for i in ids_documentos if i in nombres]
    if not ids_documentos:
        return {"ok": False, "error": "No hay documentos para analizar."}

    fuentes_chunks, analisis_por_doc = [], {}
    for did in ids_documentos:
        fuentes_chunks.append((nombres[did], cargar_chunks(sb, did)))
        analisis_por_doc[did] = cargar_analisis(sb, did)
    evidencia = buscar_evidencia(fuentes_chunks)
    unico = len(ids_documentos) == 1

    capitulos, tot = [], {"fuerte": 0, "debil": 0, "ninguna": 0}
    for cap in CAPITULOS:
        temas = []
        for t in cap["temas"]:
            ev = evidencia[(cap["id"], t["id"])]
            tot[ev["nivel"]] += 1
            temas.append({"id": t["id"], "nombre": t["nombre"], **ev})
        agentes = []
        for key in cap["agentes"]:
            sen, score = [], None
            for did in ids_documentos:
                res = analisis_por_doc[did].get(key)
                if not res:
                    continue
                for s in senales_de(key, res):
                    s["doc"] = nombres[did]
                    sen.append(s)
                if unico and tiene_info(res):
                    score = score_de(res)
            analizado = any(key in analisis_por_doc[d] for d in ids_documentos)
            agentes.append({"key": key, "nombre": nombre_corto(key), "analizado": analizado,
                            "score": score, "senales": sen})
        capitulos.append({
            "id": cap["id"], "numero": cap["numero"], "titulo": cap["titulo"],
            "descripcion": cap["descripcion"], "temas": temas,
            "con_evidencia": sum(1 for t in temas if t["nivel"] != "ninguna"),
            "total_temas": len(temas), "agentes": agentes,
        })
    return {
        "ok": True,
        "fuentes": [{"id": i, "nombre": nombres[i]} for i in ids_documentos],
        "capitulos": capitulos,
        "resumen": {"temas_total": sum(tot.values()), "fuertes": tot["fuerte"],
                    "debiles": tot["debil"], "sin_evidencia": tot["ninguna"]},
        "aviso": "La evidencia es una búsqueda por palabras clave en los documentos subidos: indica dónde "
                 "mirar, no que el contenido cumpla la norma.",
        "referencia": "Estructura según la NCG 461 (CMF, 2021), tomada de un resumen de la norma; confirmar con el texto oficial.",
    }


_EST_CAP = {"pend": "Pendiente", "curso": "En redacción", "listo": "Listo"}
_EV_TXT = {"fuerte": "Con evidencia", "debil": "Evidencia débil", "ninguna": "Sin evidencia"}
_CLS_SEV = {"crítica": "crit", "alta": "alta", "media": "media", "baja": "baja"}


def html_pdf_memoria(d, estado=None):
    """HTML del PDF del esquema. `estado` = {id_capitulo: {estado, notas, revisados: {id_tema: bool}}} (viene del navegador)."""
    estado = estado or {}
    multi = len(d["fuentes"]) > 1
    r = d["resumen"]
    listos = sum(1 for c in d["capitulos"] if (estado.get(c["id"]) or {}).get("estado") == "listo")
    cab = (f"<p><b>Fuentes:</b> {esc_pdf(', '.join(f['nombre'] for f in d['fuentes']))}</p>"
           f"<p class='small muted'>{esc_pdf(d['aviso'])} {esc_pdf(d.get('referencia', ''))}</p>"
           f"<table class='kpi'><tr><td><span class='big'>{listos}</span><span class='muted'>/{len(d['capitulos'])}</span><br/>capítulos listos</td>"
           f"<td><span class='big'>{r['fuertes'] + r['debiles']}</span><span class='muted'>/{r['temas_total']}</span><br/>temas con evidencia</td>"
           f"<td><span class='big'>{r['debiles']}</span><br/>con evidencia débil</td>"
           f"<td><span class='big'>{r['sin_evidencia']}</span><br/>sin evidencia</td></tr></table>")
    cuerpo = ""
    for c in d["capitulos"]:
        m = estado.get(c["id"]) or {}
        rev = m.get("revisados") or {}
        filas = ""
        for t in c["temas"]:
            pg = ", ".join(((p["doc"] + " ") if multi else "") + f"pág. {p['pagina'] if p['pagina'] is not None else '?'}" for p in t["paginas"])
            if t.get("n_paginas", 0) > len(t["paginas"]):
                pg += f" (+{t['n_paginas'] - len(t['paginas'])} más)"
            filas += (f"<tr><td style='width:6%'>{'[x]' if rev.get(t['id']) else '[ ]'}</td><td><b>{esc_pdf(t['nombre'])}</b></td>"
                      f"<td style='width:18%'>{_EV_TXT.get(t['nivel'], '')}</td><td style='width:30%' class='small'>{esc_pdf(pg) or '-'}</td></tr>")
        cuerpo += (f"<h2>{c['numero']}. {esc_pdf(c['titulo'])} <span class='small muted'>- {_EST_CAP.get(m.get('estado'), 'Pendiente')}</span></h2>"
                   f"<table><tr><th></th><th>Tema que pide la norma</th><th>Evidencia</th><th>Dónde mirar</th></tr>{filas}</table>")
        sen = [(a["nombre"], x) for a in c["agentes"] for x in a["senales"]]
        if sen:
            cuerpo += "<h3>Señales de los agentes</h3><table>" + "".join(
                f"<tr><td style='width:16%'>{esc_pdf(n)}</td><td>{esc_pdf(x['titulo'])}</td>"
                f"<td style='width:12%'><span class='{_CLS_SEV.get(x['severidad'], '')}'>{esc_pdf(x['severidad'])}</span></td></tr>" for n, x in sen) + "</table>"
        notas = (m.get("notas") or "").strip()
        if notas:
            cuerpo += f"<h3>Notas de redacción</h3><p>{esc_pdf(notas)}</p>"
    return pagina_pdf("Esquema de Memoria Anual (NCG 461)", f"Generado el {datetime.now().strftime('%d/%m/%Y %H:%M')}", cab + cuerpo)


def crear_router(get_supabase):
    router = APIRouter()
    aqui = os.path.dirname(os.path.abspath(__file__))

    @router.get("/api/memoria/cobertura")
    def api_cobertura(docs: str = ""):
        try:
            ids = [d for d in docs.split(",") if d.strip()]
            return construir_cobertura(get_supabase(), ids or None)
        except Exception as e:
            print(f"[MEMORIA] Error: {e}", flush=True)
            return JSONResponse({"ok": False, "error": str(e)})

    @router.post("/api/memoria/pdf")
    def api_memoria_pdf(payload: dict = Body(default={})):
        try:
            payload = payload or {}
            docs = str(payload.get("docs") or "")
            ids = [x for x in docs.split(",") if x.strip() and x != "__todos__"]
            data = construir_cobertura(get_supabase(), ids or None)
            if not data.get("ok"):
                return JSONResponse(data, status_code=404)
            pdf = html_a_pdf(html_pdf_memoria(data, payload.get("caps")))
        except Exception as e:
            print(f"[MEMORIA] Error PDF: {e}", flush=True)
            return JSONResponse({"ok": False, "error": str(e)}, status_code=500)
        nombre = f"Directa_Memoria_Anual_{datetime.now().strftime('%Y-%m-%d')}.pdf"
        return Response(content=pdf, media_type="application/pdf",
                        headers={"Content-Disposition": f'attachment; filename="{nombre}"'})

    @router.get("/memoria.html")
    def pagina_memoria():
        ruta = os.path.join(aqui, "memoria.html")
        if os.path.exists(ruta):
            return FileResponse(ruta, media_type="text/html")
        return JSONResponse({"ok": False, "error": "memoria.html no está junto a main.py"}, status_code=404)

    return router