# DIRECTA · Módulo Gerencia General

Proyecto completo del MVP: **backend FastAPI** (el que ya existía), **app Flutter** (móvil y web) y **Docker**.

```
directa/
├── backend/                  MVP FastAPI (main.py v2.9 + dashboard, memoria, indicadores, guía)
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── .env.example          copia a .env y pon tus llaves (Supabase, NVIDIA, Groq)
│   ├── base_de_datos.sql     tablas y función de búsqueda para Supabase
│   └── demo/                 MODO DEMO: base en memoria + IA simulada (sin llaves)
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
| Inicio | KPIs, pasos de preparación, siguiente paso | `/api/documentos`, `/api/analisis-completos/{id}` |
| Documentos | Subir PDF/Word/Excel con progreso, activar, eliminar | `/api/subir-informe/`, `/api/progreso/{id}`, `DELETE /api/documentos/{id}` |
| Preguntar | Chat con los 14 agentes (respuesta en streaming), fuentes, sugerencias | `/api/consultar-stream/`, `/api/consultar/`, `/api/sugerencias/` |
| Resultados | Puntaje global, señales con filtros, omisiones, preguntas, detalle por agente | `/api/analisis-completos/{id}` |
| Más → Informe IA | Elegir contenidos y descargar el PDF | `/api/informe/` |
| Más → Dashboard | Gráficos, semáforo, señales, plan de acción, Excel, comparación | `/api/dashboard/…` |
| Más → Memoria Anual | Capítulos NCG 461, evidencia, notas, borrador con IA, PDF | `/api/memoria/…` |
| Más → Indicadores | KPI/KRI sugeridos y propios, soluciones con IA, PDF, copia | `/api/indicadores/…` |
| Más → Guía de uso | Preguntas sobre cómo usar la app | `/api/guia/preguntar` |
| Más → Servidor | Cambiar la dirección del backend, tema y tamaño de letra | — |

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

## 3. Publicar (el "Vercel" de cada parte)

Vercel solo aloja sitios web. Una app móvil necesita **dos cosas**: un lugar donde el backend esté en internet y una forma de entregar el instalador.

### 3.1 Backend en internet → Render (recomendado)
La app instalada en un teléfono no puede usar `localhost`: necesita el backend publicado.
**Render** funciona como Vercel pero para contenedores Docker: conectas GitHub y publica solo.

1. Sube esta carpeta a GitHub (sin `backend/.env`).
2. render.com → **New → Blueprint** → elige el repositorio. Usa el `render.yaml` incluido.
3. Queda en una dirección como `https://directa-backend.onrender.com`.
4. En la app: **Más → Servidor y apariencia** → pega esa dirección.

Plan gratuito: 750 horas al mes; el servicio se "duerme" tras 15 minutos sin uso y tarda cerca de 1 minuto en despertar (abre la dirección un rato antes de presentar). El `render.yaml` arranca en **modo demo**; para el modo real, sigue el comentario del archivo.

### 3.2 Instalador de la app → Codemagic + Firebase App Distribution
| Plataforma | Para qué | Costo |
|---|---|---|
| **Codemagic** | Compila el APK (y el iOS) en la nube desde GitHub en cada push. Es lo más parecido a Vercel para apps. Ya está el `codemagic.yaml`. | Gratis: 500 min/mes en macOS M2, 1 compilación a la vez |
| **Firebase App Distribution** | Reparte el APK a testers (profesor, cliente) por correo; instalan con un enlace. | Gratis |
| **BetaDrop / Diawi** | Subes el APK y te da un enlace de descarga al instante. | Planes gratis con límites (enlaces que vencen, pocos testers) |
| **Appetize.io** | Corre la app en el navegador (emulador online), útil para una presentación. | Gratis: 30 min/mes |
| **Google Play (prueba interna)** / **TestFlight** | Publicación oficial en las tiendas. | Play: pago único · Apple: suscripción anual |

Recomendación: **Render** para el backend, **Codemagic** para compilar y **Firebase App Distribution** para entregar el APK.

## 4. Notas importantes

- **Seguridad**: el backend del MVP no tiene login, CORS está abierto y las políticas de Supabase son `using (true)`. Sirve para demostrar, no para datos reales en internet. Si alguna llave quedó expuesta en un `.env` compartido, cámbiala.
- **Modo demo**: usa el `main.py` real, pero reemplaza Supabase por una base en memoria y la IA por respuestas fijas. Se borra al reiniciar. No sirve para evaluar la calidad del análisis.
- El servidor en modo real necesita las variables de `backend/.env.example`.
