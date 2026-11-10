# Versión web de la app Flutter servida con nginx.
# nginx además reenvía /api/ al backend, así la app usa el mismo dominio (sin problemas de CORS).

# ---- 1) Compilar Flutter web --------------------------------------------------
FROM debian:bookworm-slim AS build
ARG FLUTTER_VERSION=3.47.7
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates git xz-utils unzip \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C /opt
ENV PATH="/opt/flutter/bin:${PATH}" \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    CI=true
RUN git config --global --add safe.directory '*' && flutter --disable-analytics && flutter precache --web

WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
# Vacío = la app usa el mismo dominio donde se publica (nginx reenvía /api al backend)
ARG API_BASE_URL=
RUN flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

# ---- 2) Servir con nginx -----------------------------------------------------
FROM nginx:1.27-alpine
ENV BACKEND_URL=http://backend:8000 \
    NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /src/build/web /usr/share/nginx/html
EXPOSE 80
