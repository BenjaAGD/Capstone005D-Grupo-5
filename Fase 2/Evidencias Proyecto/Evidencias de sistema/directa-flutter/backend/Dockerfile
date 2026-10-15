# Backend DIRECTA — FastAPI (main.py + dashboard, memoria, indicadores, guía)
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Librerías del sistema que necesita xhtml2pdf (cairo para svglib) al compilar sus dependencias
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc pkg-config libcairo2-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

EXPOSE 8000
# Comprueba que el servidor responde (GET / devuelve un mensaje JSON)
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/' % os.getenv('PORT', '8000'))" || exit 1

# El puerto sale de la variable PORT (la usan Render, Railway, Cloud Run, etc.); por defecto 8000.
ENV PORT=8000
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
