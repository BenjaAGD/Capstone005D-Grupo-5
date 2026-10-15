/// Textos de ayuda "¿Para qué sirve esta pantalla?" tomados del MVP (index.html, dashboard.html, memoria.html, indicadores.html).
const ayudas = <String, ({List<String> p, List<String> pasos})>{
  'inicio': (
    p: ['DIRECTA ayuda al Gerente General a preparar la reunión de directorio a partir de los documentos de la empresa: detecta riesgos, anticipa las preguntas que puede hacer el directorio y ordena la información para los informes y la memoria anual.'],
    pasos: ['Entra a **Documentos** y sube el informe (PDF, Word o Excel). Se lee y se analiza una sola vez.', 'En **Resultados** ves el puntaje y las alertas por área.', 'En **Preguntar a IA** consultas dudas sobre el documento.', 'En **Informe IA** armas el PDF para llevar al directorio.', '**Dashboard**, **Memoria Anual** e **Indicadores** (en «Más») convierten el análisis en gráficos, listas de trabajo y metas.'],
  ),
  'docs': (
    p: ['Aquí subes y administras los documentos que se van a analizar. Cada archivo se procesa una sola vez; después todas las pantallas usan ese resultado.'],
    pasos: ['Elige un archivo (PDF, Word o Excel).', 'Espera a que termine el proceso: verás el avance en pantalla.', 'Marca el documento como activo para trabajar con él en las demás pantallas (también puedes cambiarlo desde el selector de arriba).', 'Si un documento terminó con error o incompleto, elimínalo y vuelve a subirlo.'],
  ),
  'chat': (
    p: ['Conversa con los especialistas de la IA sobre el documento activo. Responden usando los fragmentos del documento y el análisis ya hecho.'],
    pasos: ['Elige un agente (Financiero, Legal, Riesgos…) o deja el asistente general.', 'Escribe tu pregunta o usa una sugerencia. Puedes pedir cosas como *"¿de qué trata el documento?"* o *"¿por qué cayó el EBITDA?"*.', 'Las repreguntas se entienden en contexto.', 'Con el botón de agregar, la respuesta pasa al Informe IA.'],
  ),
  'resultados': (
    p: ['Muestra el análisis completo del documento activo: puntaje de preparación, señales de alerta, omisiones y preguntas probables del directorio.'],
    pasos: ['Mira primero el puntaje global y las áreas con menor puntaje.', 'Filtra las señales por gravedad (crítica, alta, media, baja) o por agente.', 'Revisa las **omisiones**: lo que el documento debería contar y no cuenta.', 'Agrega al Informe IA lo que quieras llevar al directorio.'],
  ),
  'informe': (
    p: ['Arma el informe final para la reunión de directorio con los análisis y respuestas que elijas, y lo descarga como PDF.'],
    pasos: ['Agrega análisis o respuestas del chat desde Resultados y Preguntar a IA.', 'Marca u oculta los ítems que quieras incluir.', 'Revisa la vista previa y descarga el PDF.'],
  ),
  'dashboard': (
    p: ['**El Dashboard resume en una sola vista cómo está preparado el documento** que se va a presentar al directorio: un puntaje global, el estado de cada área, las alertas por gravedad y un plan de acción.',
        '**Puntaje global:** de 0 a 100; mientras más alto, mejor preparado. Es el promedio de las áreas que encontraron información.'],
    pasos: ['Revisa los gráficos: alertas por gravedad y áreas con menor puntaje.', 'En **Semáforo por agente** toca un área para ver solo sus señales.', 'En **Señales** empieza por las críticas y altas.', 'En **Plan de acción** asigna responsable, fecha y estado a cada recomendación.', '**Comparar con otro documento** muestra qué mejoró o empeoró frente a otro período.', 'El PDF es el informe formal; el Excel trae el plan de acción para trabajarlo en equipo.'],
  ),
  'memoria': (
    p: ['**La memoria anual** es el documento con que la empresa rinde cuentas cada año al directorio, a los accionistas y a la CMF. La norma NCG 461 exige ciertos capítulos y temas.',
        '**Esta pantalla es una lista de trabajo para armarla:** por capítulo ves qué temas pide la norma, si hay evidencia en tus documentos (y en qué página), qué alertan los agentes y tus notas de redacción.'],
    pasos: ['Elige en qué documentos buscar.', 'Recorre los capítulos y marca cada tema como revisado.', 'Donde diga "Sin evidencia", pide ese dato al área responsable.', 'Cambia el estado del capítulo (pendiente, en redacción, listo).', 'Descarga el PDF para compartir el avance. *Ojo: no revisa que el texto cumpla la norma; solo indica dónde mirar.*'],
  ),
  'indicadores': (
    p: ['**KPI** (desempeño) responde *"¿cumplimos lo que nos propusimos?"*: mientras más alto, mejor. **KRI** (riesgo) responde *"¿qué tan cerca estamos de un problema?"*: mientras más bajo, mejor.',
        '**Semáforo:** verde = cumple la meta; amarillo = no la cumple pero aún no pasa el límite; rojo = pasó el límite y hay que actuar. Los **sugeridos** se calculan con el análisis; los **propios** los agregas tú y se guardan en este teléfono.'],
    pasos: ['Revisa los indicadores en rojo y amarillo.', 'Asigna solución, responsable y fecha.', 'Agrega tus indicadores con «+ Agregar indicador» (puedes pedir ayuda a la IA).', 'Usa «Guardar copia» para respaldarlos y «Descargar PDF» para compartirlos.'],
  ),
};
