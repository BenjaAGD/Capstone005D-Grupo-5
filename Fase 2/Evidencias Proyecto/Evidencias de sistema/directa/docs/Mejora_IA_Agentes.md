# Mejora de la IA que hace funcionar a los agentes (v3)

Este documento explica **qué se mejoró en la IA detrás de los 14 agentes del Gerente General**, cómo se comprueba que las respuestas son correctas y
cómo los agentes **mejoran solos con cada interacción**. El sistema también genera una versión *viva* de este informe con los datos reales de uso
(pantalla **Mejora de agentes** → *Informe PDF* o *Markdown*, o `GET /api/mejora/informe?formato=pdf|md`).

> **Alcance de lo comprobado.** Todo lo descrito está cubierto por 109 pruebas automáticas que usan un Gemini **simulado**. No se pudo probar con tu llave real
> de Gemini ni con tu Supabase desde el entorno donde se construyó. Antes de usarlo con el directorio, corre `python probar_gemini.py` y revisa 5–10 respuestas a mano.

## 1. De qué problema partimos

| Problema de la versión anterior | Qué se hizo |
|---|---|
| Las respuestas de la IA no se comprobaban: una cifra inventada llegaba tal cual al gerente | **Doble verificación** (código + segundo prompt de IA) y una **tercera capa** que contrasta con las Memorias Anuales; un corrector reescribe lo señalado |
| Los agentes eran genéricos (hablaban para un analista) | Los **14 agentes** se reescribieron para el **Gerente General**: qué debe decir en el directorio, qué le preguntarán, qué cifras llevar |
| El gerente no sabía qué preguntar | Cada agente tiene **6 preguntas guiadas** (panorama → diagnóstico → decisión) y una pregunta dinámica sobre su alerta más grave |
| Los agentes no aprendían de lo que el gerente aprobaba o rechazaba | **Memoria de los agentes**: reglas de comportamiento aprendidas de 👍/👎 y de la verificación, con versiones y reversa |
| Dependencia de dos proveedores (Groq, NVIDIA) | Todo pasa por **Gemini**: chat, JSON y embeddings (2048 dimensiones) |
| Muchos clics para llegar a algo útil | Agente **automático**, sugerencias con un clic, **Preparar mi reunión** y **Armar memoria** en un clic |

## 2. La IA: Gemini en una sola capa (`ia_config.py`)

- Un único módulo habla con Gemini. Variables: `GEMINI_API_KEY` (o varias en `GEMINI_API_KEYS`), `GEMINI_MODEL`, `GEMINI_MODEL_FALLBACKS`,
  `GEMINI_MODEL_VERIFICADOR` (opcional: **otro modelo revisa al primero**, lo que vuelve más independiente la verificación) y `EMBEDDING_MODEL`.
- Si una llave se agota o un modelo falla, rota a la siguiente llave y luego al modelo de respaldo; reintenta con pausas; respeta un plazo máximo por consulta.
- La llave **nunca** se imprime, no viaja en `/api/estado` ni entra a la imagen de Docker.
- Los vectores de NVIDIA **no son compatibles** con los de Gemini (aunque ambos usen 2048 dimensiones): los documentos ya subidos hay que reindexarlos con `python reindexar_embeddings.py`.

## 3. Verificación de cada respuesta (`verificador.py`)

Toda respuesta del chat pasa por tres controles independientes y recibe un sello:

1. **Código (sin IA).** Cada cifra, porcentaje, página y cita entre comillas debe existir en los fragmentos del documento, o poder derivarse con una resta, suma o razón simple.
   Es determinista: la IA no puede "convencerlo".
2. **Segundo prompt (IA verificadora).** Otro rol, sin ver el razonamiento del agente, dividido en tres **sub-agentes**:
   *cifras* (montos, unidades, base de comparación, cálculos), *evidencia* (cada afirmación respaldada) y *coherencia* (empresa, período, norma aplicable).
   `VERIFICADOR_SUBAGENTES=unificado` usa una llamada con los tres roles; `separado` usa tres llamadas en paralelo.
3. **Memorias Anuales.** Contrasta con las memorias cargadas: coincide / difiere / no consta.

Si hay problemas de gravedad alta o media, el **corrector** reescribe solo lo señalado y se vuelve a verificar. Sellos:
**Verificada** (pasaron todas las capas que corrieron, incluida la IA), **Con reservas** o **No verificable**. Si la IA verificadora falla o no responde, el sello **nunca** es *Verificada*.
El gerente ve el sello en cada respuesta y, al pulsarlo, el detalle de las tres capas.

## 4. Agentes que mejoran con cada interacción (`memoria_agentes.py`)

```
respuesta ─► verificación ─► se guarda la interacción (pregunta, sello, problemas)
                                  │
   el gerente pulsa 👍 / 👎 (+ motivo) ─┤
                                  ▼
        ¿se repite lo mismo? ──► nace una LECCIÓN (regla de comportamiento) ──► se inyecta en el prompt del agente
```

**Tres fuentes de aprendizaje**
1. **El gerente:** 👎 con un motivo (cifra incorrecta, sin fuente, no respondió, muy largo, faltó detalle, no sirve para el directorio). Con 2 👎 iguales nace una lección (`UMBRAL_VALORACIONES`).
2. **El verificador:** si el mismo tipo de problema aparece en 3 de las últimas 15 respuestas de un agente, nace una lección.
3. **El mejorador (IA):** botón *Que la IA proponga mejoras*; lee valoraciones y problemas recientes y propone hasta 3 reglas nuevas y cuáles retirar.

**Protecciones**
- Una lección es una **regla de forma**, nunca un dato: se rechaza todo texto con cifras, años o porcentajes.
- Se rechazan frases que intentan dar órdenes al sistema (*"ignora las instrucciones"*, claves, direcciones web, *"no verifiques"*…).
- Máximo 8 reglas activas por agente (sale la de menor respaldo); sin duplicados.
- Los fragmentos del documento **siempre mandan** sobre una lección.
- Cada cambio crea una **versión**; el gerente puede **volver a cualquier versión** o retirar una regla, y también escribir reglas propias.

**Cómo ver si mejoran.** La pantalla *Mejora de agentes* muestra, por agente y por versión: consultas, % verificadas, puntaje promedio de verificación y % de 👍/👎;
y compara la primera mitad de las consultas con la segunda. La mejora **no se asume**: se mide con los datos que genere el uso real.

## 5. Tono de la Memoria Anual (`tono_memoria.py`)

- El tono se **mide por código** en las memorias anteriores (largo de oraciones, persona gramatical, fórmulas recurrentes, cifras por mil palabras). Viene una semilla medida sobre las memorias 2017–2020 y 2022.
- La IA solo **describe** ese tono; cualquier fórmula que proponga y que no aparezca literalmente en las memorias se descarta.
- **No se usa hasta que el gerente lo aprueba**; mientras tanto se aplican solo las medidas.
- Al redactar un capítulo, cada cifra se revisa por código: si no está en la evidencia se retira y queda como `[COMPLETAR]`. Lo que el gerente edita a mano no se pisa.

## 6. Configuración recomendada

| Variable | Valor | Para qué |
|---|---|---|
| `VERIFICACION_MODO` | `completa` | Las tres capas |
| `VERIFICADOR_SUBAGENTES` | `unificado` (más barato) o `separado` (más independiente) | Sub-agentes |
| `GEMINI_MODEL_VERIFICADOR` | un modelo distinto del principal | Que alguien distinto revise |
| `AGENTES_APRENDEN` | `1` | Activa el aprendizaje (`0` lo apaga) |
| `UMBRAL_VALORACIONES` | `2` | 👎 iguales para crear una regla |

## 7. Limitaciones conocidas

- **No probado con Gemini real.** Los nombres de modelo por defecto (`gemini-3.8-flash`…) pueden no existir en tu cuenta: `python probar_gemini.py --modelos` los lista.
- La verificación detecta cifras sin respaldo y contradicciones, pero **no reemplaza la lectura del gerente**: un texto *Verificada* es coherente con el documento, no necesariamente completo.
- Las memorias 2021, 2023, 2024 y 2025 no están en la semilla de tono; se miden solas cuando se suben al sistema.
- Con un solo documento y pocas interacciones las métricas de mejora no son concluyentes; hacen falta decenas de consultas valoradas.
- La búsqueda de fragmentos usa palabras clave además de vectores: si ninguna calza, el agente responde con el análisis guardado (diseño original, no cambió).
