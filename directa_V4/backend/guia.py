import re
import unicodedata

from fastapi import APIRouter, Body
from fastapi.responses import JSONResponse

MANUAL = """DIRECTA es el panel del Gerente General para preparar reuniones de directorio.
Pantallas: Inicio (cifras clave arriba y UNA acción principal: subir un documento o «Preparar mi reunión»; atajos como «Informe PDF directo»);
Documentos (subir PDF/Word/Excel; al subirlo, 14 agentes lo analizan UNA vez y se guarda);
Preguntar (chat con un agente; cada agente responde en cuatro partes: hallazgo, lo que preguntará el directorio, respuesta sugerida y qué falta; además tiene una «ruta» de 6 preguntas guía: situación, profundización y directorio, y la siguiente aparece cuando la anterior tiene respuesta);
Resultados (puntaje y señales por gravedad en una franja arriba; pestañas: resumen, señales, preguntas probables, omisiones y por agente);
Preparar mi reunión (en Inicio o Más: preguntas probables del directorio ordenadas por gravedad, con «Sugerir respuestas» y botón para llevarlas al informe);
Informe IA (arma y descarga el informe formal en PDF);
Dashboard (puntaje global, alertas, plan de acción, comparación con otro documento, PDF y Excel);
Memoria Anual (capítulos de la NCG 461; «Perfil de tono» aprende el estilo de memorias anteriores; «Borrador de memoria» elige el año y entrega un PDF con portada, gráficos y cobertura);
Indicadores (KPI = logros, KRI = riesgos; semáforo; propios; PDF);
Aprendizaje de los agentes (en Más: valoraciones con pulgares y lecciones por agente que una persona aprueba, prueba o revierte).
Sello del verificador: bajo cada respuesta aparece «Verificada» (todo respaldado por el documento), «Con reservas» (algo impreciso, corregido o sin respaldo) o «No verificable». Tocándolo se ve cada afirmación con la página que la respalda. Comprueba que la respuesta sea fiel al documento, no que el documento sea cierto.
Asistente: el botón redondo de la esquina abre «Preguntar al documento» y «Ayuda de la app» desde cualquier pantalla.
El selector 'Documento' de arriba cambia el documento en todas las pantallas. Los análisis no se repiten: se hacen al subir.
Reglas: el sistema no inventa datos; todo sale del documento subido. Las sugerencias de IA son borradores para revisar."""

FAQ = [
    (["sello", "verificada", "verificado", "con reservas", "no verificable", "verificador"],
     "El sello bajo cada respuesta lo pone un verificador distinto del agente que respondió:\n• Verificada: cada afirmación está respaldada por el documento.\n• Con reservas: hay algo impreciso, corregido o sin respaldo.\n• No verificable: no hubo fragmentos o el verificador no respondió.\nTócalo para ver cada afirmación con la página que la respalda. El verificador comprueba que la respuesta sea fiel al documento, no que el documento sea cierto."),
    (["ruta de preguntas", "preguntas guia", "ruta", "siguiente pregunta"],
     "En «Preguntar», al elegir un agente aparece su ruta de 6 preguntas guía (situación, profundización y directorio). Pulsa «Preguntar» para enviar la pregunta; la siguiente aparece cuando llega la respuesta. Las que abordan una señal grave del análisis suben primero, y puedes «Saltar» las que el documento no permite responder."),
    (["preparar mi reunion", "preparar la reunion", "preparo mi reunion", "preguntas probables", "respuesta sugerida"],
     "Pulsa «Preparar mi reunión» en Inicio (o en Más). Verás lo más grave del documento y las preguntas que probablemente te hará el directorio, de la más grave a la menos grave. «Sugerir respuestas» redacta cómo responder con datos del documento; cada pregunta tiene «Preguntar al agente» y «Al informe»."),
    (["perfil de tono", "tono", "estilo de la memoria", "memorias anteriores"],
     "En «Memoria Anual», sección «Perfil de tono»: elige al menos tres memorias anteriores ya subidas y pulsa «Extraer perfil». Revisa y corrige el perfil (persona, formalidad, largo, vocabulario, cifras y cierres) y apruébalo. Desde ahí, los borradores de la memoria siguen ese tono."),
    (["leccion", "lecciones", "aprendizaje", "valoracion", "pulgar", "me gusta"],
     "Bajo cada respuesta hay pulgares. Con «abajo» eliges el motivo en un toque. En «Más → Aprendizaje de los agentes» puedes generar lecciones a partir de las valoraciones negativas; cada lección queda pendiente hasta que una persona la prueba y la aprueba, y se puede revertir. Las respuestas bien valoradas y verificadas sirven de ejemplo."),
    (["informe pdf directo", "pdf directo", "informe en un paso", "informe rapido"],
     "En Inicio pulsa «Informe PDF directo»: agrega todo el análisis del documento activo y descarga el PDF con los valores por defecto. Si quieres elegir contenidos, usa «Informe IA»."),
    (["borrador de memoria", "memoria en un paso", "pdf de la memoria", "graficos de la memoria"],
     "En «Memoria Anual», «Borrador de memoria»: elige el año, revisa la marca (nombre y color) y pulsa «Generar PDF». Incluye portada, índice, carta, gráficos, página tipo dashboard y tabla de cobertura de la NCG 461."),
    (["como hago un kpi", "como hago un kri", "como creo un kpi", "como creo un kri", "crear un kpi", "crear un kri", "crear kpi", "crear kri",
      "agregar un kpi", "agregar un kri", "agregar kpi", "agregar kri", "agregar un indicador", "agregar indicador", "crear un indicador",
      "crear indicador", "nuevo kpi", "nuevo kri", "nuevo indicador", "hacer un kpi", "hacer un kri", "armar un kpi", "como agrego un indicador"],
     "Para crear un KPI o KRI:\n1) Entra a «Indicadores» en el menú.\n2) Pulsa «+ Agregar indicador».\n3) Elige el tipo: KPI (más alto es mejor) o KRI (más bajo es mejor).\n4) Escribe el nombre, el valor actual, la meta y el límite (desde ahí pasa a rojo). Si quieres ayuda, pulsa «Sugerir con IA»: propone unidad, meta, límite y solución.\n5) Pulsa «Guardar indicador». El semáforo se calcula solo.\nSe guarda en este navegador; usa «Guardar copia» para respaldarlo."),
    (["como comparo", "como comparar", "comparar dos documentos", "comparar documentos"],
     "Ve a «Dashboard», baja hasta «Comparar con otro documento», elige el documento anterior y verás qué mejoró o empeoró. Puedes bajar la comparación en PDF."),
    (["como lleno la memoria", "como relleno la memoria", "como armo la memoria", "como uso la memoria", "borrador de la memoria", "sugerir borrador"],
     "En «Memoria Anual» elige un capítulo, revisa qué evidencia hay, marca los temas que ya revisaste y pulsa «Sugerir borrador con IA». Aparece una tarjeta con el texto: pulsa «Usar en mis notas» para guardarlo y edítalo. En el PDF puedes incluir solo los temas marcados."),
    (["como descargo", "como bajo el informe", "como genero el informe", "descargar el informe", "descargar pdf"],
     "Cada pantalla tiene su botón «Descargar PDF». El informe completo para el directorio se arma en «Informe IA»; el plan de acción en Excel está en el Dashboard."),
    (["subir", "subo", "subir un documento", "como subo", "cargar", "cargo", "agregar documento", "nuevo documento"], "Ve a «Documentos», pulsa «Subir un documento» y elige tu PDF, Word o Excel. El análisis arranca solo (los 14 agentes lo leen una sola vez) y las señales graves pasan por el verificador."),
    (["dashboard", "puntaje", "semaforo global"], "El Dashboard resume el documento: puntaje global de 0 a 100 (más alto = mejor preparado), alertas por gravedad, estado por área y plan de acción. Puedes descargar PDF o Excel."),
    (["memoria", "ncg", "capitulo"], "Memoria Anual ordena el trabajo por los capítulos de la NCG 461: eliges un capítulo, ves qué evidencia hay en tus documentos, qué alertan los agentes, y escribes tu borrador. El botón «Sugerir borrador con IA» te deja un primer texto."),
    (["kpi", "kri", "indicador"], "KPI mide logros (ej. cumplimiento del plan) y KRI mide riesgos (ej. alertas críticas). El semáforo se calcula con valor, meta y límite. Puedes agregar los tuyos en «Indicadores»."),
    (["comparar", "comparacion", "competencia", "otra empresa"], "En el Dashboard, «Comparar con otro documento» muestra qué mejoró o empeoró entre dos documentos (otro período u otra empresa si subiste su memoria). Un módulo completo de competencia aún está pendiente."),
    (["informe", "pdf", "directorio"], "En «Informe IA» eliges qué incluir y descargas el PDF formal para el directorio. Dashboard, Indicadores y Memoria tienen su propio PDF."),
    (["excel", "plan de accion"], "El botón «Excel» del Dashboard descarga el plan de acción en una planilla ordenada, con encabezado fijo para filtrar."),
    (["lento", "demora", "carga"], "Los módulos quedan cargados en segundo plano. Si algo tarda, pulsa «Actualizar datos». Los análisis se guardan, así que no se recalculan."),
    (["preguntar", "chat"], "En «Preguntar» eliges un agente y consultas el documento activo. Cada agente responde en cuatro partes (hallazgo, lo que preguntará el directorio, respuesta sugerida y qué falta) y la respuesta lleva el sello del verificador. También puedes preguntar desde el botón del asistente en cualquier pantalla."),
]
_CACHE = {}


def _norm(t):
    t = unicodedata.normalize("NFD", (t or "").lower())
    return re.sub(r"[̀-ͯ]", "", t)


def responder(pregunta, pantalla=""):
    q = _norm(pregunta)[:300]
    if len(q) < 3:
        return {"ok": False, "error": "Escribe tu pregunta."}
    mejor, pts = None, 0
    for claves, resp in FAQ:
        p = sum(len(c.split()) for c in claves if c in q)   
        if p > pts:
            mejor, pts = resp, p
    if mejor:
        return {"ok": True, "texto": mejor, "fuente": "faq"}
    if q in _CACHE:
        return {"ok": True, "texto": _CACHE[q], "fuente": "cache"}
    from ia_config import llamar_llm_chat
    sistema = ("Eres la guía de uso de la aplicación DIRECTA. Responde en español, en máximo 4 frases, "
               "indicando en qué pantalla hacerlo y los pasos. Si no está en el manual, dilo.\n\nMANUAL:\n" + MANUAL)
    texto = (llamar_llm_chat(sistema, f"Pantalla actual: {pantalla or 'desconocida'}. Pregunta: {pregunta[:300]}", temperatura=0.2, max_tokens=600) or "").strip()
    if not texto:
        return {"ok": False, "error": "La guía no pudo responder ahora. Intenta de nuevo."}
    texto = re.sub(r"[*#`]+", "", texto).strip()
    _CACHE[q] = texto
    return {"ok": True, "texto": texto, "fuente": "ia"}


def crear_router(get_supabase=None):
    router = APIRouter()

    @router.post("/api/guia/preguntar")
    def api_guia(payload: dict = Body(default={})):
        try:
            return responder(str((payload or {}).get("pregunta") or ""), str((payload or {}).get("pantalla") or ""))
        except Exception as e:
            print(f"[GUIA] Error: {e}", flush=True)
            return JSONResponse({"ok": False, "error": "No se pudo consultar la guía."})

    return router