import re
import unicodedata

from fastapi import APIRouter, Body
from fastapi.responses import JSONResponse

MANUAL = """DIRECTA es el panel del Gerente General para preparar reuniones de directorio.
Pantallas: Inicio (resumen y siguientes pasos); Documentos (subir PDF/Word; al subirlo, 14 agentes lo analizan UNA vez y se guarda);
Preguntar a IA (chat sobre el documento elegido); Resultados (análisis por agente: señales, omisiones, preguntas probables, recomendaciones);
Informe IA (arma y descarga el informe formal en PDF con lo analizado); Dashboard (puntaje global 0-100, alertas por gravedad, plan de acción, comparación con otro documento/período/empresa, descarga PDF y Excel);
Memoria Anual (capítulos de la NCG 461 de la CMF: qué evidencia hay en los documentos, qué dicen los agentes, notas de redacción y 'Sugerir borrador con IA');
Indicadores (KPI = mide logros, KRI = mide riesgos; semáforo verde/amarillo/rojo; soluciones sugeridas; se pueden agregar propios; PDF).
El selector 'Documento' de arriba cambia el documento en todas las pantallas. Los análisis no se repiten: se hacen al subir.
Si un documento quedó incompleto, elimínalo y vuélvelo a subir sin abrir otros módulos mientras procesa.
Reglas: el sistema no inventa datos; todo sale del documento subido. Las sugerencias de IA son borradores para revisar."""

FAQ = [
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
    (["subir", "subo", "subir un documento", "como subo", "cargar", "cargo", "agregar documento", "nuevo documento"], "Ve a «Documentos», arrastra o elige tu PDF/Word y espera a que termine el análisis (los 14 agentes lo leen una sola vez). Mientras procesa, evita abrir otros módulos."),
    (["dashboard", "puntaje", "semaforo global"], "El Dashboard resume el documento: puntaje global de 0 a 100 (más alto = mejor preparado), alertas por gravedad, estado por área y plan de acción. Puedes descargar PDF o Excel."),
    (["memoria", "ncg", "capitulo"], "Memoria Anual ordena el trabajo por los capítulos de la NCG 461: eliges un capítulo, ves qué evidencia hay en tus documentos, qué alertan los agentes, y escribes tu borrador. El botón «Sugerir borrador con IA» te deja un primer texto."),
    (["kpi", "kri", "indicador"], "KPI mide logros (ej. cumplimiento del plan) y KRI mide riesgos (ej. alertas críticas). El semáforo se calcula con valor, meta y límite. Puedes agregar los tuyos en «Indicadores»."),
    (["comparar", "comparacion", "competencia", "otra empresa"], "En el Dashboard, «Comparar con otro documento» muestra qué mejoró o empeoró entre dos documentos (otro período u otra empresa si subiste su memoria). Un módulo completo de competencia aún está pendiente."),
    (["informe", "pdf", "directorio"], "En «Informe IA» eliges qué incluir y descargas el PDF formal para el directorio. Dashboard, Indicadores y Memoria tienen su propio PDF."),
    (["excel", "plan de accion"], "El botón «Excel» del Dashboard descarga el plan de acción en una planilla ordenada, con encabezado fijo para filtrar."),
    (["lento", "demora", "carga"], "Los módulos quedan cargados en segundo plano. Si algo tarda, pulsa «Actualizar datos». Los análisis se guardan, así que no se recalculan."),
    (["preguntar", "chat"], "En «Preguntar a IA» consulta sobre el documento activo (por ejemplo «¿de qué trata?»). Responde solo con lo que dice el documento."),
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