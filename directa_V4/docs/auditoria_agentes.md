# Auditoría de los agentes de DIRECTA GG (Frente C1)

**Fecha:** 15 de octubre de 2026  
**Revisó:** Claude, como herramienta de desarrollo. No queda instalado en la app.  
**Alcance:** los 14 agentes y el asistente general (`backend/agentes.py`), y la lógica que los ejecuta (`backend/main.py`).

## 1. Método

1. **Revisión de prompts:** se leyeron los prompts `rol_chat` y `rol_analisis` de cada agente buscando tres cosas:
   - contradicciones con las reglas (a) a (n);
   - instrucciones que empujan a inventar;
   - falta de orientación al Gerente General.
2. **Revisión del flujo:** se revisó cómo se eligen los fragmentos, cómo pasan las señales de una ola a la siguiente y cómo se arma el chat.
3. **Prueba con el conjunto de pruebas** (`backend/pruebas/conjunto_pruebas.json`): 36 preguntas sobre la Memoria 2024 de CSAV, con respuesta esperada y evidencia literal, más 15 respuestas con errores sembrados. La capa de código del verificador ya se midió (sección 5). La prueba de los agentes con los modelos reales queda pendiente: necesita las llaves de Groq y NVIDIA, que no están en este entorno. Para correrla basta un comando (sección 6).

## 2. Hallazgos transversales

| # | Hallazgo | Riesgo | Cambio aplicado |
|---|---|---|---|
| 1 | Los prompts de chat describían a un analista ("Eres el Agente X del módulo…"), no a un asesor que prepara al GG. Ninguno anticipaba las preguntas del directorio. | Respuestas útiles para un analista, pero no para llegar preparado a la sesión. | Se reescribió el `rol_chat` de los 14 agentes como asesor del GG. Toda respuesta de agente sigue un formato de 4 pasos (`FORMATO_RESPUESTA_GG`): hallazgo con cifra y página, lo que preguntará el directorio, respuesta sugerida y qué falta. |
| 2 | Las reglas (a) a (n) solo existían dentro del prompt del mismo modelo que escribe, que se autocorregía en una pasada. | Errores de cifras y alcance sin un segundo revisor. | Se agregó un verificador independiente en 3 capas (`verificador.py`), con 3 sub-agentes que absorben las reglas. Las reglas siguen en los prompts como prevención y el verificador actúa como detección. |
| 3 | Las señales de una ola pasan a los integradores (Riesgos y Estrategia) sin ningún filtro. | Los integradores correlacionan hechos que podrían no estar en el documento. | Las señales que el verificador marcó sin respaldo o contradichas ya no pasan a la ola 5 (`_resumen_extendido`). |
| 4 | La búsqueda del texto contiguo a un fragmento usaba el `id` (UUID aleatorio) como si fuera el orden de lectura. El inicio del documento se buscaba igual. | Se agregaba un fragmento cualquiera en lugar del siguiente: menos contexto y más riesgo de responder "no consta". | Ahora se busca en la misma página y la siguiente (`ampliar_chunks`), y el inicio del documento se ordena por página. |
| 5 | El chat llamaba a la IA dentro de una función asíncrona sin liberar el servidor. | Mientras un usuario esperaba su respuesta, el resto de las peticiones quedaban bloqueadas. | Las llamadas del chat y del verificador se ejecutan en un hilo (`run_in_threadpool`). |
| 6 | Las páginas que cita el agente son las del PDF (1, 2, 3…), no las impresas en la memoria (una memoria impresa suele empezar a numerar después de la portada). | El gerente busca "pág. 90" en la memoria impresa y no la encuentra. | No se cambió. Se propone mostrar "pág. del PDF" en la interfaz. |
| 7 | Algunas palabras clave se repiten entre agentes. "Huelga" y "negociación colectiva" están en RRHH y en Stakeholders; "concentración" en Comercial y en Riesgos. | Dos agentes reportan el mismo hecho y el puntaje global lo cuenta dos veces. | Ya existían cláusulas "Limítate a…" en los prompts. Se mantienen. El verificador no corrige duplicados. |

## 3. Revisión por agente

En todos los agentes se aplicó el mismo cambio base, que la tabla no repite:
- `rol_chat` reescrito como asesor del GG;
- formato de 4 pasos;
- `pregunta_directorio`;
- 6 preguntas guía, 2 por nivel (situación, profundización, directorio).

| Agente | Problema en el prompt anterior | Ajuste adicional | Preguntas en el conjunto |
|---|---|---|---|
| Financiero | El chat pedía siempre EBITDA ajustado frente al contable, pero el análisis dice "no exijas EBITDA ajustado si el documento no lo usa". | El chat ahora pide EBITDA ajustado "solo si el documento lo usa". | 6 |
| Ciberseguridad | El chat pedía "identifica brechas no mencionadas que deberían estar cubiertas", lo que invita a inventar y contradice la regla (l). | Se quitó esa instrucción. Ahora pide fechas, plazos y responsables que consten en el documento. | 1 |
| Auditoría | Sin problemas de fondo. | Se agregó el foco en el comité de auditoría y en distinguir lo material. | 2 |
| Legal | El chat no traía el criterio NIC 37 (probable, posible, remota) que sí usa el análisis. | NIC 37, covenants y dispensas incluidos en el chat. | 2 |
| Asignación de capital | El chat no comparaba el retorno con el costo de capital. | ROIC frente al costo de capital, y TIR, VAN y escenarios. | 2 |
| Operaciones | El chat no comparaba los inventarios con la política. | Inventarios frente a la política y productividad frente a la meta. | 1 |
| Comercial | Sin problemas de fondo. | Pide cifras con su período. | 3 |
| RRHH | El chat no comparaba la rotación con el histórico. | Rotación frente al histórico y nombres de los cargos sin sucesor. | 3 |
| Tecnología | Sin problemas de fondo. El umbral de 25% de atraso solo estaba en el análisis. | El umbral de 25% quedó en la ruta de preguntas guía. | 1 |
| Compensación | "Benchmarks de sueldos de mercado" podía llevar a citar datos externos. | Solo benchmarks que estén en el documento (además, la regla común del chat lo exige). | 2 |
| ESG | El chat citaba la NCG 461 sin el período en que rige, lo que contradice la regla (m). | NCG 461 "para ejercicios 2021 en adelante". | 2 |
| Stakeholders | Sin problemas de fondo. | Agrega el mensaje para accionistas y mercado. | 4 |
| Estrategia | Sin problemas de fondo: ya decía "si el plan no está, dilo". | Agrega el avance de cada pilar frente a su meta. | 2 |
| Riesgos | El chat usaba una escala de 3 niveles (alta, media, baja), distinta de la escala única de 4 de la regla (f). | Se quitó la escala propia. Ahora exige citar hechos de al menos dos áreas. | 1 |
| Asistente general | Sin problemas. | Sugiere qué agente especialista consultar. Mantiene su formato libre, sin los 4 pasos, porque responde consultas generales. | 4 |

## 4. Cambios propuestos que no se aplicaron

1. **Mostrar "pág. del PDF".** Cambio de interfaz que conviene acordar con el Product Owner.
2. **Más preguntas en el conjunto para Ciberseguridad, Operaciones, Riesgos y Tecnología.** La Memoria de CSAV casi no trata esos temas, porque CSAV es un holding sin operación propia. Hay que sumar documentos del cliente.
3. **Medir la latencia del verificador con los modelos reales.** Si supera los 20 segundos por respuesta, usar `VERIFICADOR_SUBAGENTES=unificado` (ya es el valor por defecto) o verificar solo las respuestas con cifras.

## 5. Resultados de la prueba disponible (capa de código del verificador)

Comando: `python pruebas/evaluar.py`. Resultado en `backend/pruebas/resultados/verificador_capa1.md`.

| Métrica | Resultado | Meta propuesta |
|---|---|---|
| Errores numéricos sembrados detectados por la capa 1 | 9 de 9 (100%) | 85% |
| Todos los errores sembrados detectados por la capa 1 | 10 de 15 (67%) | — |
| Respuestas correctas marcadas por error (falsos positivos) | 0 de 36 (0%) | 10% como máximo |

Los otros 5 errores son semánticos y la capa 1 no puede verlos: una cifra de otro año presentada como actual, un hecho falso sin cifras, una unidad cambiada y una base de comparación cambiada. Esos los debe detectar la capa 2, que se mide con `--con-ia`.

**Advertencia.** Las reglas de la capa 1 se ajustaron con este mismo conjunto, así que el 100% y el 0% son optimistas. Para medir de verdad hay que agregar casos nuevos que no se usaron para ajustar, idealmente redactados por otra persona del equipo.

## 6. Prueba pendiente con los modelos reales

Con las llaves en `backend/.env` y la Memoria 2024 de CSAV subida al backend:

```bash
cd backend
python pruebas/evaluar.py --con-ia                       # capas 1 + 2 sobre los errores sembrados
python pruebas/evaluar.py --linea-base --api https://directa-backend.onrender.com --doc csav2024=<document_id>
```

La línea base registra, por agente, si la respuesta trae las cifras clave y qué sello le puso el verificador. El resultado se guarda en `pruebas/resultados/linea_base.md`. Con eso se completa la columna "Evidencia" de esta auditoría.

## 7. Registro de cambios aplicados

- `agentes.py`:
  - `FORMATO_RESPUESTA_GG`, `NIVELES_GUIA`, `_PARA_GG` (rol de chat, pregunta del directorio y 6 preguntas guía por agente);
  - `AGENTES_SOPORTE` (Verificador y Redactor de memoria);
  - validación de las preguntas guía.
- `main.py`:
  - formato de 4 pasos en el chat;
  - `/api/ruta-preguntas`;
  - `/api/preparar-reunion`;
  - filtro de señales no respaldadas hacia los integradores;
  - corrección del fragmento contiguo;
  - llamadas de IA fuera del hilo principal.
- `verificador.py`, `ia_config.llamar_llm_verificador`, `pruebas/`: nuevos.
