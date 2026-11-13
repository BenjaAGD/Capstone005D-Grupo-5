# Login DIRECTA: prueba local y revisión

Pantalla Flutter real, adaptable a computador y móvil, con azul marino, blanco
y celeste. El acceso se abre después de verificar Supabase Auth, correo,
segundo factor, membresía activa y respuesta del backend. Incluye recuperación
de contraseña, selector de organización cuando corresponda y cierre de sesión.

## Descargar la rama de trabajo

La rama `rodrigo/directa` parte del merge
`4e55be460906095a05285c13dd2af632056aa09f` del repositorio
`BenjaAGD/Capstone005D-Grupo-5`. Conserva la nueva navegación, la lectura de
documentos y el rediseño de Memoria Anual y sus PDF. Los archivos del login
están bajo `directa_V4`. Las migraciones SQL conservan su versión original.

Desde tu copia del repositorio:

```powershell
git fetch origin
git switch rodrigo/directa
```

Si Git detecta cambios locales incompatibles, se detiene: revisa esos cambios
antes de cambiar de rama. Revisar o probar esta rama no requiere ejecutar SQL
en Supabase remoto. El arranque local de abajo crea su propio laboratorio.

## Arrancar la prueba

Requiere Docker Desktop abierto, Git, Node.js 20 o posterior, Python 3.10 o
posterior y Flutter 3.47.7 / Dart 3.13.5 o una versión compatible con pubspec.
No hace falta iniciar sesión en Supabase CLI, enlazar un proyecto remoto ni
copiar la service_role del proyecto real. La primera ejecución descarga las
imágenes de Supabase y construye el backend; puede tardar varios minutos.

Desde `directa_V4`, en PowerShell:

```powershell
python dev/bootstrap_local.py --init --start
cd app
flutter run -d chrome --web-port=8085 --dart-define-from-file=../.directa/auth.local.web.json
```

Si Windows usa el lanzador `py` en vez de `python`, usa
`py -3 dev/bootstrap_local.py --init --start` para el primer comando.

Abrir la dirección que indique Flutter. Ingresar:

| Campo | Valor del ejemplo local |
| --- | --- |
| Usuario | `admin` |
| Contraseña | `admin` |

La primera vez aparece la configuración del autenticador: escanea el QR con
tu aplicación de autenticación y escribe su código de seis dígitos. En los
siguientes ingresos, usa el código del mismo autenticador. El bootstrap
confirma explícitamente el correo de la cuenta de laboratorio; las cuentas
reales deben confirmar su correo por el flujo de Supabase. Se conservan los
factores ya configurados al ejecutar nuevamente el bootstrap.

Después se abre el espacio de Gerencia General. El laboratorio empieza vacío;
los documentos de tu base remota no se copian ni se asignan a esta cuenta.
Para salir: Más → Servidor y apariencia → Cerrar sesión.

Sin una clave NVIDIA real, puedes probar login, MFA, navegación y los estados
vacíos. El procesamiento de documentos y las consultas IA requieren las claves
del proveedor: el bootstrap copia solo `NVIDIA_API_KEY`, `GROQ_API_KEY` y
`GROQ_API_KEY_1` a `GROQ_API_KEY_4` si ya existen en `backend/.env`. No simula respuestas de IA.

Para detener el backend sin eliminar datos:

```powershell
docker compose -f docker-compose.login-local.yml stop
```

Para detener Supabase local conservando sus volúmenes:

```powershell
npx --yes supabase@3.1.0 stop --workdir dev/local-auth
```

## Qué crea el bootstrap

- Una instancia Supabase dedicada `directa-login-local`, API en `55421`,
  PostgreSQL en `55422` y buzón de prueba en `http://127.0.0.1:55424`.
- Las siete tablas vacías del MVP, pgvector de 2048 dimensiones y las
  migraciones 001/002/003 únicamente en ese laboratorio nuevo. Si ya existen
  tablas o usuarios ajenos, aborta. No ejecuta `base_de_datos.sql`, que contiene
  borrados; usa un esquema inicial separado y sin políticas abiertas.
- Un usuario real en Auth, una organización y una membresía admin, mediante
  alta explícita y registro administrativo. No eleva membresías existentes ni
  restablece contraseñas o MFA al repetirlo.
- Configuración privada en `.directa/`, ignorada por Git, con archivos separados
  para Flutter (solo clave pública) y backend (credencial de servidor).
- Un backend independiente en `http://127.0.0.1:8001`; no reemplaza el que
  puedas tener en `8000`.

Las credenciales de ejemplo se copian a `.directa/local-login.env` con `--init`.
Puedes cambiarlas allí antes del primer arranque. No están hardcodeadas en el
login. GoTrue exige una contraseña más larga que `admin`: solo para esta
cuenta local, cliente y bootstrap usan la misma derivación SHA-256 con un
prefijo fijo antes de llamar a Auth. Esto adapta la prueba a esa restricción;
no mejora la fortaleza de `admin` y no sustituye la validación del servidor.
La cuenta solo se habilita con build debug, `DIRECTA_ENV=local`, endpoints
locales y bandera explícita. En producción no se activa ese alias.

## Sesión y datos

El cliente verifica la sesión online y envía el JWT y la organización en
peticiones JSON, archivos y SSE. No envía tokens a URLs arbitrarias elegidas
en Ajustes. El backend verifica Auth y la membresía antes de los endpoints
privados; las lecturas usan el JWT del usuario y RLS. Los workers conservan
organización y permisos, y sus escrituras añaden pertenencia y autoría.

En móvil los tokens se guardan mediante almacenamiento seguro del sistema;
en web permanecen en memoria y recargar solicita iniciar sesión otra vez.
La caché de negocio nueva se separa por usuario/organización y se limpia al
salir; usa SharedPreferences, no almacenamiento cifrado. La caché histórica
sin identidad queda conservada pero no se lee ni se asigna automáticamente.
La recuperación web usa PKCE y debe completarse en el mismo navegador.

## Configuración de un entorno real

Usar cuentas reales y contraseñas propias. Flutter requiere únicamente las
variables públicas `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_BASE_URL` y
`AUTH_REDIRECT_URL`, con HTTPS y `DIRECTA_ENV=production`. Omitir todas las
variables `DIRECTA_LOCAL_*`. La service_role permanece exclusivamente en el
backend. Configurar el origen web permitido en `DIRECTA_ALLOWED_ORIGINS` y las
redirecciones de Auth. Se incluye el callback móvil `directa://auth-callback`.

El overlay `docker-compose.auth.yml` pasa las variables públicas de la web al
build de Flutter. Requiere `SUPABASE_PUBLIC_URL`, `SUPABASE_PUBLIC_KEY` y
`DIRECTA_PUBLIC_URL` en el entorno de Docker Compose (URL HTTPS de Supabase,
clave anon/publicable, URL HTTPS de la app). No poner una service_role ahí.
Arrancar con `docker compose -f docker-compose.yml -f docker-compose.auth.yml
up --build` solo cuando el backend y el proxy HTTPS del entorno real estén
configurados. El build comprueba la clave antes de compilar el cliente.

Esta entrega conserva FastAPI para poder probar la app actual. La migración
completa del backend a TypeScript y la auditoría integral del despliegue son
trabajo separado. Las migraciones 001/002 ya ejecutadas en tu base remota no
se repiten: la 003 remota sigue dependiendo de asignar y revisar sus datos
históricos; el laboratorio vacío no valida esa base remota.

## Validación de esta entrega

Las pruebas de Flutter y del middleware usan dobles de Auth; dos prueban el
protocolo del SDK Supabase real mediante HTTP simulado. El esquema se comprueba
con PostgreSQL/PGlite y pgvector. No son una prueba end-to-end de GoTrue.
La prueba completa con Supabase, Docker Desktop y autenticador se ejecuta con
los comandos de arriba en tu equipo.
