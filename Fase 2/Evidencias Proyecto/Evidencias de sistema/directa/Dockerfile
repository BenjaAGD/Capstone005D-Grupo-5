# DIRECTA — imagen de la aplicación (backend FastAPI + pantallas web).
# La llave de Gemini y las credenciales de Supabase NO van en la imagen: se entregan al arrancar
# el contenedor (docker compose las lee de tu archivo .env, que está en .dockerignore).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    MPLBACKEND=Agg \
    MPLCONFIGDIR=/tmp/matplotlib \
    DIRECTA_DATOS_DIR=/app/datos_locales

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

# usuario sin privilegios; datos_locales es el volumen donde se guardan los datos si no hay Supabase
RUN useradd --create-home --uid 10001 directa \
    && mkdir -p /app/datos_locales \
    && chown -R directa:directa /app
USER directa

EXPOSE 8000
VOLUME ["/app/datos_locales"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/agentes', timeout=4).status == 200 else 1)"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
