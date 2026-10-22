# DIRECTA — módulo del Gerente General (v3)

Panel para que el Gerente General prepare la reunión de directorio: sube un documento, **14 agentes** lo analizan una vez y luego puede
preguntar (cada respuesta con **doble verificación**), armar el informe, preparar su reunión en un clic y construir la **Memoria Anual**
con el tono de las memorias anteriores. IA: **Gemini** (Groq y NVIDIA ya no se usan).

## Arranque rápido con Docker

```bash
cp .env.example .env          # pega tu GEMINI_API_KEY y los datos de Supabase (este archivo NO se comparte ni entra a la imagen)
docker compose up --build     # http://localhost:8000/app
```

- Sin Supabase puedes probar en **modo demo** (todo en memoria): en `.env` descomenta `DIRECTA_DB=memoria`.
- Los datos locales (aprendizaje de los agentes, borradores) quedan en el volumen `directa_datos`.
- Para publicar la imagen en Docker Hub (necesitas tu cuenta; las credenciales las pones tú, no se guardan aquí):

```bash
docker login
docker tag directa-gerente-general:v3 TU_USUARIO/directa-gerente-general:v3
docker push TU_USUARIO/directa-gerente-general:v3
```

## Arranque sin Docker

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env           # completa tus llaves
python probar_gemini.py        # comprueba la llave (chat, JSON y embeddings)
uvicorn main:app --port 8000   # http://localhost:8000/app
```

## Base de datos (Supabase)

1. **Instalación nueva:** ejecuta `base_de_datos.txt` (¡borra y recrea las tablas originales!) y luego `migracion_v3.sql`.
2. **Ya tienes la base de la v2:** ejecuta solo `migracion_v3.sql` (es aditiva y se puede repetir). Si no lo haces, la app funciona igual y guarda lo nuevo en `datos_locales/`.
3. **Documentos indexados con NVIDIA:** los vectores no sirven con Gemini. Recalcúlalos:
   ```bash
   python reindexar_embeddings.py --solo-contar   # cuántos fragmentos hay
   python reindexar_embeddings.py                 # recalcula (se puede interrumpir y retomar)
   ```

## Pantallas

| Pantalla | Para qué |
|---|---|
| Inicio | **Preparar mi reunión** (un clic): señales clave + preguntas probables del directorio respondidas y verificadas + PDF |
| Documentos | Subir PDF/Word/Excel; marcar el documento activo |
| Preguntar a IA | Chat en modo **Automático** (elige al especialista), sello de verificación, 👍/👎, siguiente pregunta guiada |
| Resultados / Informe IA / Dashboard / Indicadores | Análisis de los 14 agentes, informe PDF, semáforo, KPI/KRI |
| Mejora de agentes | Lo que aprendió cada agente, reglas, versiones, informe de mejora |
| Memoria Anual | **Armar memoria** en un clic con el tono de las memorias anteriores, borradores editables, PDF con gráficos y dashboard |

## Pruebas

```bash
pip install -r requirements-dev.txt
python -m pytest          # 109 pruebas, ~25 s, con un Gemini simulado (no gasta cuota)
```

## Seguridad

- La llave de Gemini vive solo en `.env` (excluido por `.gitignore` y `.dockerignore`) y se entrega al contenedor al arrancar. No está en la imagen, el código ni los logs.
- `/api/estado` no devuelve llaves. Las "lecciones" que aprenden los agentes no pueden contener cifras, direcciones ni órdenes al sistema.
- Las políticas de la base (`RLS`) son abiertas, como en el MVP: antes de producción real, ligarlas a usuarios autenticados.

## Documentos

- `docs/Reparto_de_agentes_equipo.md` — quién hizo qué entre los 4 integrantes (**completar nombres**).
- `docs/Mejora_IA_Agentes.md` — mejoras de la IA de los agentes, verificación y aprendizaje.
