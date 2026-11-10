# DIRECTA · Módulo Gerencia General

Proyecto completo del MVP: **backend FastAPI** (el que ya existía), **app Flutter** (móvil y web) y **Docker**.

```
directa/
├── backend/                  MVP FastAPI (main.py v2.9 + dashboard, memoria, indicadores, guía)
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── .env.example          copia a .env y pon tus llaves (Supabase, NVIDIA, Groq)
│   ├── base_de_datos.sql     tablas y función de búsqueda para Supabase (instalación desde cero)
│   ├── migracion_v3.sql      tablas nuevas: valoraciones, lecciones, perfiles de tono (solo agrega)
│   ├── verificador.py        revisa cada respuesta en 3 capas (código, otro modelo, corrección)
│   ├── aprendizaje.py        valoraciones 👍/👎 y lecciones por agente (con aprobación y prueba)
│   ├── tono.py               perfil de tono de la memoria, aprendido de memorias anteriores
│   ├── memoria_pdf.py        borrador completo de la memoria en PDF (portada, carta, capítulos)
│   ├── graficos.py           gráficos de los PDF (matplotlib)
│   ├── persistencia.py       guarda en Supabase; si falta la tabla, en un archivo local
│   ├── pruebas/              conjunto de prueba (memoria CSAV 2024) y evaluador del verificador
│   ├── web/                  páginas web del MVP, con HTML, CSS y JavaScript separados
│   │   ├── index.html        panel principal (se abre con ?api=URL-del-backend)
│   │   ├── dashboard.html    ┐
│   │   ├── memoria.html      ├ el backend las sirve en /dashboard.html, /memoria.html, /indicadores.html
│   │   ├── indicadores.html  ┘
│   │   ├── css/              base-modulos.css (común a los 3 módulos) + un .css por página
│   │   └── js/               tema.js (tema claro/oscuro) + un .js por página
│   └── demo/                 MODO DEMO: base en memoria + IA simulada (sin llaves)
├── docs/auditoria_agentes.md  revisión de los 14 agentes y resultados del verificador
├── app/                      App Flutter "DIRECTA GG" (Android, iOS y web)
│   ├── Dockerfile            versión web servida con nginx
│   └── nginx.conf.template   reenvía /api/ al backend
├── docker-compose.yml        backend real + app web
├── docker-compose.demo.yml   cambia el backend a modo demo
├── render.yaml               publicar el backend en Render (Docker, gratis)
└── codemagic.yaml            compilar el APK en la nube (Codemagic)
```

## 1. Levantar todo con Docker

Requisito: Docker Desktop.

**Modo demo** (no necesita llaves; carga dos memorias ficticias de "Andes Demo S.A."):
```bash
docker compose -f docker-compose.yml -f docker-compose.demo.yml up --build
```

**Modo real** (tus llaves de Supabase y de la IA):
```bash
cp backend/.env.example backend/.env     # y complétalo
docker compose up --build
```

- App web: <http://localhost:8080>
- Backend: <http://localhost:8000> (documentación automática en <http://localhost:8000/docs>)

La primera construcción de la app web tarda unos minutos porque descarga Flutter.

## 2. La app móvil

Hecha en Flutter con las mismas pantallas del `index.html` del MVP:

| Pestaña / menú | Qué hace | Endpoints |
|---|---|---|
| Inicio | Estado del documento, acción principal, atajos y pasos de preparación | `/api/documentos`, `/api/analisis-completos/{id}` |
| Documentos | Subir PDF/Word/Excel con progreso, activar, eliminar | `/api/subir-informe/`, `/api/progreso/{id}`, `DELETE /api/documentos/{id}` |
| Preguntar | Chat con los 14 agentes en streaming, **sello de verificación**, fuentes, 👍/👎, **ruta de preguntas guía** por agente | `/api/consultar-stream/`, `/api/verificar/`, `/api/ruta-preguntas/{id}/{agente}`, `/api/valoraciones` |
| Resultados | Puntaje global, señales (con marca si el verificador las revisó), omisiones, preguntas, por agente | `/api/analisis-completos/{id}`, `/api/verificar-analisis/{id}` |
| Más → Preparar mi reunión | Preguntas probables del directorio por severidad, con respuesta sugerida revisada | `/api/preparar-reunion/{id}`, `/api/preparar-reunion/{id}/respuestas` |
| Más → Informe IA | Elegir contenidos y descargar el PDF | `/api/informe/` |
| Más → Dashboard | Gráficos, semáforo, señales, plan de acción, Excel, comparación | `/api/dashboard/…` |
| Más → Memoria Anual | Pestañas **Borrador en un paso** (PDF completo con gráficos), **Capítulos** NCG 461 y **Perfil de tono** | `/api/memoria/…`, `/api/memoria/borrador`, `/api/memoria/perfil-tono` |
| Más → Indicadores | KPI/KRI sugeridos y propios, soluciones con IA, PDF, copia | `/api/indicadores/…` |
| Más → Aprendizaje de los agentes | Resumen de valoraciones y lecciones: aprobar, rechazar, editar, probar, revertir | `/api/valoraciones/resumen`, `/api/lecciones…` |
| Asistente (botón flotante) | Pestañas "Preguntar al documento" y "Ayuda de la app", con sugerencias según la pantalla | `/api/consultar/`, `/api/guia/preguntar` |
| Más → Servidor | Dirección del backend, estado del servidor (llaves, verificador, tablas), tema y letra | `/api/estado` |

Lo que en el MVP se guardaba en el navegador (chat, ítems del informe, plan de acción, notas de la memoria, indicadores propios) aquí se guarda en el teléfono.

**Probarla en un emulador o teléfono** (requiere Flutter instalado):
```bash
cd app
flutter pub get
flutter run
```
Luego, en **Más → Servidor y apariencia**, escribe la dirección del backend:
- emulador Android con Docker en el mismo computador: `http://10.0.2.2:8000`
- teléfono real en la misma WiFi: `http://IP-de-tu-computador:8000`

**Compilar el instalador de Android (APK)**:
```bash
cd app
flutter build apk --release --dart-define=API_BASE_URL=https://tu-backend
# queda en app/build/app/outputs/flutter-apk/app-release.apk
```
El APK queda firmado con la llave de pruebas de Flutter: sirve para instalarlo y repartirlo a testers. Para Google Play hay que crear una llave propia (`keystore`).

**Pruebas automáticas**: `cd app && flutter test` (usan respuestas reales grabadas del backend).

## 3. Funciones nuevas del backend (versión 3)

### 3.1 Antes de usarlas: migración de la base de datos
En Supabase → **SQL Editor**, pega `backend/migracion_v3.sql` y presiona **Run**. Solo **agrega** tres tablas
(`valoraciones`, `lecciones`, `perfiles_tono`); no toca los documentos ni los análisis que ya tienes.

> **No vuelvas a correr `base_de_datos.sql`**: ese archivo empieza borrando todas las tablas.

Si la migración no se corre, la app funciona igual, pero valoraciones, lecciones y perfil de tono se guardan en
`backend/datos_locales/` (un archivo del servidor). En Render ese archivo se borra en cada reinicio o despliegue.
**Más → Servidor y apariencia** muestra dónde se está guardando.

### 3.2 Verificación de respuestas
Cada respuesta del chat y cada señal alta o crítica del análisis pasa por tres capas:
1. **Código** (sin IA): cada cifra, porcentaje, variación, página, cita y plazo se busca en el documento.
2. **Verificador**: otro modelo (si Groq redactó, revisa NVIDIA, y al revés) revisa afirmación por afirmación: cifras, evidencia y período.
3. **Corrección**: si algo no está respaldado, el redactor corrige una vez y se guarda el texto original.

El resultado es un sello: **Verificada**, **Con reservas** o **No verificable**. Las señales contradichas bajan a severidad baja (se conserva la original) y no entran a los resúmenes.

| Variable (opcional) | Por defecto | Para qué |
|---|---|---|
| `VERIFICAR_CHAT` | `1` | `0` desactiva la verificación del chat |
| `VERIFICAR_ANALISIS` | `1` | `0` desactiva la revisión de señales del análisis |
| `VERIFICADOR_PROVEEDOR` | `auto` | `auto` usa el proveedor distinto al que redactó; o `groq` / `nvidia` |
| `VERIFICADOR_SUBAGENTES` | `unificado` | `separado` revisa cifras, evidencia y período en tres llamadas (más preciso, más lento) |

Si el otro proveedor no está disponible (sin llave o sin respuesta), revisa el mismo modelo que redactó y el detalle del sello lo avisa.

### 3.3 Aprendizaje y tono
- **Valoraciones y lecciones**: con 3 o más 👎 de un agente se pueden generar lecciones. Cada lección queda *pendiente* hasta que la apruebas; antes puedes **probarla** (compara respuestas con y sin la lección usando la capa 1). Máximo 5 activas por agente; se pueden revertir. Las lecciones no pueden contener cifras ni copiar respuestas.
- **Perfil de tono**: el Redactor lee memorias anteriores ya subidas y propone un perfil (persona, formalidad, largo, vocabulario, cómo presenta las cifras y los cierres). Lo editas y apruebas; desde ahí los borradores de capítulos lo usan. Cada borrador avisa si trae cifras de otro año.

### 3.4 Pruebas del verificador
```bash
cd backend
python pruebas/evaluar.py                      # capa 1 sobre 36 respuestas correctas y 15 errores sembrados
python pruebas/evaluar.py --con-ia             # agrega la capa 2 (necesita llaves)
python pruebas/evaluar.py --linea-base --api https://tu-backend --doc csav2024=ID-del-documento
```
Los resultados quedan en `backend/pruebas/resultados/`. La revisión de los agentes está en `docs/auditoria_agentes.md`.

## 4. Publicar (el "Vercel" de cada parte)

Vercel solo aloja sitios web. Una app móvil necesita **dos cosas**: un lugar donde el backend esté en internet y una forma de entregar el instalador.

### 4.1 Backend en internet → Render (recomendado)
La app instalada en un teléfono no puede usar `localhost`: necesita el backend publicado.
**Render** funciona como Vercel pero para contenedores Docker: conectas GitHub y publica solo.

1. Sube esta carpeta a GitHub (sin `backend/.env`).
2. render.com → **New → Blueprint** → elige el repositorio. Usa el `render.yaml` incluido.
3. Queda en una dirección como `https://directa-backend.onrender.com`.
4. En la app: **Más → Servidor y apariencia** → pega esa dirección.

Plan gratuito: 750 horas al mes; el servicio se "duerme" tras 15 minutos sin uso y tarda cerca de 1 minuto en despertar (abre la dirección un rato antes de presentar). El `render.yaml` arranca en **modo demo**; para el modo real, sigue el comentario del archivo.

### 4.2 Instalador de la app → Codemagic + Firebase App Distribution
| Plataforma | Para qué | Costo |
|---|---|---|
| **Codemagic** | Compila el APK (y el iOS) en la nube desde GitHub en cada push. Es lo más parecido a Vercel para apps. Ya está el `codemagic.yaml`. | Gratis: 500 min/mes en macOS M2, 1 compilación a la vez |
| **Firebase App Distribution** | Reparte el APK a testers (profesor, cliente) por correo; instalan con un enlace. | Gratis |
| **BetaDrop / Diawi** | Subes el APK y te da un enlace de descarga al instante. | Planes gratis con límites (enlaces que vencen, pocos testers) |
| **Appetize.io** | Corre la app en el navegador (emulador online), útil para una presentación. | Gratis: 30 min/mes |
| **Google Play (prueba interna)** / **TestFlight** | Publicación oficial en las tiendas. | Play: pago único · Apple: suscripción anual |

Recomendación: **Render** para el backend, **Codemagic** para compilar y **Firebase App Distribution** para entregar el APK.

## 5. Notas importantes

- **Seguridad**: el backend del MVP no tiene login, CORS está abierto y las políticas de Supabase son `using (true)`. Sirve para demostrar, no para datos reales en internet. Si alguna llave quedó expuesta en un `.env` compartido, cámbiala.
- **Modo demo**: usa el `main.py` real, pero reemplaza Supabase por una base en memoria y la IA por respuestas fijas. Se borra al reiniciar. No sirve para evaluar la calidad del análisis.
- El servidor en modo real necesita las variables de `backend/.env.example`.
- **Páginas web**: las páginas del MVP muestran el sello de verificación en el chat; las funciones nuevas (preparar reunión, valoraciones, lecciones, perfil de tono, borrador PDF) están solo en la app.
- **Archivos de las páginas web**: los estilos van en `backend/web/css/` y la lógica en `backend/web/js/`; el HTML solo tiene la estructura. Si cambias un `.css` o `.js`, cambia también el número `?v=` de su `<link>` o `<script>` en el HTML (cualquier valor nuevo) para que el navegador no use la versión anterior guardada.
