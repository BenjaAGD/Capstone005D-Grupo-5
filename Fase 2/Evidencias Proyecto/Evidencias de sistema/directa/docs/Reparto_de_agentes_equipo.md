# Reparto del trabajo de los agentes entre los 4 integrantes del grupo

**Proyecto:** DIRECTA — módulo del Gerente General
**Versión del sistema:** v3 (Gemini, doble verificación, agentes que aprenden)

> **Antes de entregar este documento, completa y confirma:** los nombres de los integrantes y quién hizo realmente cada parte.
> El reparto de abajo es una **propuesta armada a partir de los módulos reales del código** (cada módulo tiene un dueño natural);
> la herramienta que lo redactó no sabe quién del grupo escribió qué. Reemplaza `[nombre]` y ajusta lo que no calce.

## 1. Idea general

El trabajo de los agentes se dividió en dos dimensiones, para que cada integrante tuviera un área propia **y** una pieza común del sistema:

- **A. Los 14 agentes por área de negocio.** Cada integrante es dueño de 3 o 4 agentes: afina su rol dirigido al Gerente General,
  su secuencia de 6 preguntas guiadas y revisa que sus respuestas pasen la verificación.
- **B. Una pieza transversal.** Cada integrante es además dueño de un componente que usan todos los agentes.

Todos los agentes están orientados al **Gerente General** (no al analista): hablan de "lo que debes decir en el directorio", anticipan las
preguntas de los directores y siempre separan el hecho que consta del documento de la interpretación.

## 2. Reparto

| Integrante | A. Agentes que cuida (área) | B. Pieza transversal que construyó |
|---|---|---|
| **Integrante 1 — [nombre]** | **Finanzas y capital:** Financiero, Asignación de Capital, Compensación, Comercial | **Los agentes y su secuencia de preguntas** (`agentes.py`, `preguntas_guia.py`): rol dirigido al Gerente General, 5 olas de análisis, 6 preguntas por agente (2 de panorama, 2 de diagnóstico, 2 de decisión) y la pregunta dinámica según la alerta más grave del análisis |
| **Integrante 2 — [nombre]** | **Control y cumplimiento:** Auditoría, Legal, Riesgos, Ciberseguridad | **Verificación de las respuestas** (`verificador.py`): control por código, segundo prompt con sub-agentes (cifras, evidencia, coherencia), capa de Memorias Anuales, corrector automático y sellos *Verificada / Con reservas / No verificable* |
| **Integrante 3 — [nombre]** | **Operación y tecnología:** Operaciones, Tecnología, RRHH | **La IA detrás de los agentes y su memoria** (`ia_config.py`, `memoria_agentes.py`): cambio a Gemini (se quitaron Groq y NVIDIA), rotación de llaves y modelos de respaldo, 👍/👎, lecciones por agente con versiones y reversa, informe de mejora (`docs/Mejora_IA_Agentes.md`) |
| **Integrante 4 — [nombre]** | **Sostenibilidad y estrategia:** ESG, Stakeholders, Estrategia | **Experiencia del Gerente General** (`index.html`, `memoria.html`, `reunion.py`, `tono_memoria.py`, `memoria_completa.py`, `memoria_graficos.py`, Docker): "Preparar mi reunión" en un clic, chat en modo automático, Memoria Anual con tono y PDF con gráficos y dashboard, despliegue en Docker |

## 3. Qué hizo cada integrante

### Integrante 1 — [nombre] · Agentes de finanzas y capital + secuencia de preguntas
- Dejó los agentes **Financiero, Asignación de Capital, Compensación y Comercial** hablándole al Gerente General (qué cifra memorizar, qué le preguntará un director).
- Definió, para **cada uno de los 14 agentes**, 6 preguntas en orden: *panorama → diagnóstico → decisión*, sin repetirse entre agentes.
- Programó la **pregunta dinámica**: si el análisis marcó una alerta alta o crítica, se inserta una pregunta sobre esa alerta.
- Resultado para el gerente: el botón **Preguntar** del chat le propone la siguiente pregunta y muestra el avance (por ejemplo 2/6).

### Integrante 2 — [nombre] · Agentes de control + verificación
- Dejó los agentes **Auditoría, Legal, Riesgos y Ciberseguridad** con foco en contingencias, hallazgos abiertos y cumplimiento.
- Construyó la **doble verificación**: (1) código que comprueba que cada cifra, página y cita exista en el documento; (2) un segundo prompt, independiente,
  dividido en tres sub-agentes de verificación; (3) contraste con las Memorias Anuales ya cargadas.
- Construyó el **corrector**: si hay un problema alto o medio, reescribe quitando solo lo señalado y vuelve a verificar. El texto original se conserva.
- Resultado para el gerente: cada respuesta trae su **sello** y, al pulsarlo, el detalle de las tres capas.

### Integrante 3 — [nombre] · Agentes de operación y tecnología + IA y memoria
- Dejó los agentes **Operaciones, Tecnología y RRHH** orientados a continuidad operativa, deuda técnica y sucesión.
- Cambió toda la IA a **Gemini** (chat, JSON y embeddings de 2048 dimensiones), con varias llaves, modelos de respaldo y reintentos; eliminó Groq y NVIDIA.
- Construyó la **memoria de los agentes**: con cada 👍/👎 y con cada problema que detecta la verificación, el agente puede aprender una regla de comportamiento
  (nunca datos), con límite de 8 reglas, versiones y posibilidad de volver atrás.
- Resultado para el gerente: pantalla **Mejora de agentes** con lo que aprendió cada uno, e informe descargable.

### Integrante 4 — [nombre] · Agentes de sostenibilidad y estrategia + experiencia del gerente
- Dejó los agentes **ESG, Stakeholders y Estrategia** (cumplimiento NCG 461, reputación, coherencia del plan estratégico).
- Construyó **Preparar mi reunión**: un clic que reúne las señales más graves, responde las preguntas probables del directorio con doble verificación y entrega un PDF.
- Construyó la **Memoria Anual**: tono de la compañía medido por código en las memorias anteriores (el gerente lo aprueba), borradores por capítulo con cifras revisadas por código
  y PDF con gráficos y dashboard de avance.
- Redujo los clics del gerente: agente automático, sugerencias que se envían con un clic, guía de la siguiente pregunta.
- Empaquetó todo en **Docker** (`Dockerfile`, `docker-compose.yml`, la llave de Gemini entra por `.env`, nunca dentro de la imagen).

## 4. Cómo se integra el trabajo de los cuatro

```
Pregunta del gerente
   └─► (Integrante 4) elección automática del especialista
          └─► (Integrante 1) agente con su rol + preguntas guiadas
                 └─► (Integrante 3) Gemini + reglas aprendidas del agente
                        └─► (Integrante 2) verificación en 3 capas + corrección + sello
                               └─► (Integrante 4) pantalla, 👍/👎 ──► (Integrante 3) el agente aprende
```

## 5. Verificación del trabajo conjunto

El proyecto trae **109 pruebas automáticas** que recorren este circuito completo con un Gemini simulado (`tests/`): agentes, verificación, aprendizaje, tono de la Memoria,
"Preparar mi reunión", scripts de apoyo y coherencia del frontend con el backend. Se ejecutan con `python -m pytest`.
