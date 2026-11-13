"""Alta explícita de una cuenta de laboratorio en Supabase LOCAL, sin reset.

Python 3.10+, Node 20+, Docker Desktop y Flutter. Solo biblioteca estándar.
No acepta una URL de destino ni lee credenciales del Supabase remoto.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from urllib.parse import urlparse
import uuid

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / '.directa'
LOCAL = ROOT / 'dev' / 'local-auth'
PROJECT = 'directa-login-local'
CONTAINER = 'supabase_db_' + PROJECT
CLI = ['npx', '--yes', 'supabase@3.1.0']
PREFIX = 'DIRECTA_LOCAL_PASSWORD_V1\0'
TABLES = ('usuarios', 'documentos', 'document_chunks', 'analisis', 'valoraciones', 'lecciones', 'perfiles_tono')


class SetupError(Exception):
    pass


def local_password(value):
    return hashlib.sha256((PREFIX + value).encode('utf-8')).hexdigest()


def local_docker(endpoint):
    p = urlparse(endpoint)
    if p.scheme == 'unix' and not p.netloc and p.path.startswith('/'):
        return
    if p.scheme == 'npipe' and not p.netloc and p.path.startswith('//./pipe/'):
        return
    if p.scheme in ('tcp', 'http', 'https') and p.hostname in ('localhost', '127.0.0.1', '::1'):
        return
    raise SetupError('El contexto Docker no es local. Selecciona Docker Desktop antes de continuar.')


def checked_url(value, scheme, port):
    p = urlparse(value)
    if (p.scheme != scheme or p.hostname not in ('127.0.0.1', 'localhost', '::1')
            or p.port != port or p.query or p.fragment):
        raise SetupError('El destino no es la instancia local dedicada. Operación detenida.')
    if scheme == 'http' and (p.username or p.password or p.path not in ('', '/')):
        raise SetupError('URL local inesperada. Operación detenida.')
    return value.rstrip('/')


def read_env(path):
    result = {}
    if not path.exists():
        return result
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1]
        result[key.strip()] = value
    return result


def private_write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Los secretos nunca se imprimen ni entran en un Docker build context.
    path.write_text(value, encoding='utf-8')
    try:
        path.chmod(0o600)
    except OSError:
        pass  # En Windows aplican las ACL de la carpeta del usuario.


def command(args, *, input=None, label='comando', timeout=1800):
    executable = shutil.which(args[0])
    if not executable:
        raise SetupError('Falta instalar o agregar al PATH: ' + args[0])
    argv = [executable, *args[1:]]
    if os.name == 'nt' and Path(executable).suffix.lower() in ('.cmd', '.bat'):
        # Ejecutar el npx JavaScript con Node evita cmd.exe, sus escapes y
        # WinError 193 al iniciar un .cmd desde Python en Windows.
        node = shutil.which('node')
        roots = [Path(executable).parent, Path(node).parent] if node else []
        entry = next((p / 'node_modules/npm/bin/npx-cli.js' for p in roots
                      if (p / 'node_modules/npm/bin/npx-cli.js').is_file()), None)
        if not node or entry is None or args[0] != 'npx':
            raise SetupError('Revisa la instalación de Node.js/npm: falta el ejecutor npx para Windows.')
        argv = [node, str(entry), *args[1:]]
    try:
        env = os.environ.copy()
        if args[0] == 'npx':
            # Evitar overrides de un proyecto/puerto/host o token de la sesión
            # del usuario. Este CLI solo trabaja con el config local dedicado.
            env = {key: value for key, value in env.items() if not key.startswith('SUPABASE_')}
            env['DO_NOT_TRACK'] = '1'
        result = subprocess.run(argv, cwd=ROOT, input=input, env=env,
                                text=True, encoding='utf-8', errors='replace',
                                capture_output=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise SetupError('No se pudo completar ' + label + '. Revisa Docker Desktop y vuelve a ejecutar.') from None
    if result.returncode:
        log = PRIVATE / (label + '.log')
        private_write(log, result.stdout + '\n' + result.stderr)
        raise SetupError('Falló ' + label + '. Revisa el registro privado: ' + str(log))
    return result.stdout


def sql(text):
    return command(['docker', 'exec', '-i', CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres',
                    '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'], input=text, label='base-local').strip()


def literal(value):
    # Usado solamente para valores de la configuración local, nunca identificadores.
    return "'" + str(value).replace("'", "''") + "'"


def public_config(status, values, *, android=False):
    api = checked_url(status['API_URL'], 'http', 55421)
    host = '10.0.2.2' if android else '127.0.0.1'
    if android:
        api = 'http://10.0.2.2:55421'
    key = status['ANON_KEY']
    if key.startswith('sb_secret_') or key == status.get('SERVICE_ROLE_KEY'):
        raise SetupError('La clave de cliente no es pública.')
    if key.count('.') == 2:
        import base64
        claims = json.loads(base64.urlsafe_b64decode(key.split('.')[1] + '==='))
        if claims.get('role') != 'anon':
            raise SetupError('La clave de cliente no es pública.')
    elif not key.startswith('sb_publishable_'):
        raise SetupError('La clave pública local no tiene un formato admitido.')
    return {
        'SUPABASE_URL': api, 'SUPABASE_ANON_KEY': key,
        'API_BASE_URL': 'http://' + host + ':8001', 'DIRECTA_ENV': 'local',
        'DIRECTA_LOCAL_TEST_ACCOUNT': True,
        'DIRECTA_LOCAL_LOGIN': values['LOCAL_ADMIN_LOGIN'],
        'DIRECTA_LOCAL_EMAIL': values['LOCAL_ADMIN_EMAIL'],
        'AUTH_REDIRECT_URL': 'directa://auth-callback' if android else 'http://localhost:8085/',
    }


def auth_request(api, service_key, method, path, payload=None):
    checked_url(api, 'http', 55421)
    request = urllib.request.Request(api + '/auth/v1' + path, method=method,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={'apikey': service_key, 'Authorization': 'Bearer ' + service_key,
                 'Content-Type': 'application/json'})
    try:
        # Ningún proxy corporativo recibe las credenciales locales.
        with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(request, timeout=15) as response:
            return json.load(response)
    except (urllib.error.URLError, ValueError):
        raise SetupError('Supabase Auth local no completó el alta. Revisa su contenedor; no se borraron usuarios.') from None


def create_or_find_user(api, key, values):
    email = values['LOCAL_ADMIN_EMAIL'].lower()
    matches = []
    for page in range(1, 101):
        response = auth_request(api, key, 'GET', '/admin/users?page=' + str(page) + '&per_page=100')
        users = response.get('users', [])
        matches.extend(user for user in users if user.get('email', '').lower() == email)
        if len(users) < 100:
            break
    else:
        raise SetupError('Demasiados usuarios para el laboratorio. Revisa manualmente la instancia local.')
    if len(matches) > 1:
        raise SetupError('El correo no es único. No se modificó ninguna cuenta.')
    if matches:
        user = matches[0]
        if (user.get('app_metadata') or {}).get('directa_local_project') != PROJECT:
            raise SetupError('Ese correo ya pertenece a otra cuenta. No se modifica ni se toma su control.')
        print('Cuenta local ya existente; contraseña y segundo factor conservados.')
    else:
        user = auth_request(api, key, 'POST', '/admin/users', {
            'email': email, 'password': local_password(values['LOCAL_ADMIN_PASSWORD']),
            'email_confirm': True,
            'app_metadata': {'directa_local_project': PROJECT},
            'user_metadata': {'directa_local_test': True},
        })
    try:
        return str(uuid.UUID(user['id']))
    except (KeyError, ValueError, TypeError):
        raise SetupError('Auth no devolvió una identidad válida; el alta no se puede continuar.') from None


def assign_local_membership(user_id, values):
    name, email = values['LOCAL_ORGANIZATION'], values['LOCAL_ADMIN_EMAIL'].lower()
    # Una transacción; no se asignan documentos previos ni se elevan roles existentes.
    sql('''BEGIN;
DO $local$
DECLARE org uuid; existing public.memberships; profile public.usuarios;
BEGIN
 IF (SELECT count(*) FROM public.organizations WHERE name=%(name)s)>1 THEN
   RAISE EXCEPTION 'Hay organizaciones duplicadas; revisar sin modificar';
 END IF;
 SELECT id INTO org FROM public.organizations WHERE name=%(name)s AND active;
 IF org IS NULL THEN
   IF EXISTS(SELECT 1 FROM public.organizations WHERE name=%(name)s) THEN
     RAISE EXCEPTION 'La organización existe y está desactivada';
   END IF;
   org=directa_private.register_organization(%(name)s,'Bootstrap explícito del laboratorio local de login');
 END IF;
 SELECT * INTO existing FROM public.memberships WHERE tenant_id=org AND user_id=%(uid)s::uuid;
 IF FOUND THEN
   IF existing.role<>'admin' OR NOT existing.active THEN
     RAISE EXCEPTION 'No cambiar automáticamente una membresía existente';
   END IF;
 ELSE
   PERFORM directa_private.register_member(org,%(uid)s::uuid,'admin','Cuenta Auth de prueba creada en Supabase local aislado');
 END IF;
 SELECT * INTO profile FROM public.usuarios WHERE correo=%(email)s;
 IF FOUND THEN
   IF profile.auth_user_id IS DISTINCT FROM %(uid)s::uuid OR profile.tenant_id IS DISTINCT FROM org THEN
     RAISE EXCEPTION 'El perfil existente corresponde a otra identidad';
   END IF;
 ELSE
   INSERT INTO public.usuarios(nombre,correo,rol,tenant_id,auth_user_id)
     VALUES(%(display)s,%(email)s,'admin',org,%(uid)s::uuid);
 END IF;
END $local$;
NOTIFY pgrst,'reload schema';
COMMIT;''' % {'name': literal(name), 'email': literal(email), 'uid': literal(user_id),
             'display': literal(values['LOCAL_DISPLAY_NAME'])})


def configure(values, status):
    api = checked_url(status['API_URL'], 'http', 55421)
    checked_url(status['DB_URL'], 'postgresql', 55422)
    for key in ('ANON_KEY', 'SERVICE_ROLE_KEY'):
        if not status.get(key):
            raise SetupError('El estado de Supabase local no incluye las claves necesarias.')
    # Validar la separación pública antes de crear cuentas o escribir configuración.
    web = public_config(status, values)
    if sql("SELECT to_regclass('directa_local_test.bootstrap') IS NOT NULL;") == 'f':
        sql((LOCAL / 'initial_schema.sql').read_text(encoding='utf-8'))
    if sql("SELECT project_id FROM directa_local_test.bootstrap;") != PROJECT:
        raise SetupError('La base no tiene la marca de este laboratorio. No continuar.')
    for number, name in ((1, '001_identity_tenants_rls_vector'), (2, '002_reviewed_legacy_assignment')):
        applied = sql("SELECT to_regclass('directa_private.migration_log') IS NOT NULL;") == 't'
        if applied and sql('SELECT count(*) FROM directa_private.migration_log WHERE migration_id=' + literal(name) + ';') == '1':
            continue
        sql((ROOT / 'database' / 'migrations' / (name + '.sql')).read_text(encoding='utf-8'))
        print('Migración local ' + str(number) + ' aplicada.')
    user_id = create_or_find_user(api, status['SERVICE_ROLE_KEY'], values)
    assign_local_membership(user_id, values)
    third = '003_validate_assigned_data'
    if sql('SELECT count(*) FROM directa_private.migration_log WHERE migration_id=' + literal(third) + ';') == '0':
        sql((ROOT / 'database' / 'migrations' / (third + '.sql')).read_text(encoding='utf-8'))
    for target, config in (('web', web), ('android', public_config(status, values, android=True))):
        private_write(PRIVATE / ('auth.local.' + target + '.json'), json.dumps(config, ensure_ascii=False, indent=2) + '\n')
    backend = {
        'SUPABASE_URL': 'http://host.docker.internal:55421',
        'SUPABASE_AUTH_ISSUER': api + '/auth/v1',
        'SUPABASE_ANON_KEY': status['ANON_KEY'], 'SUPABASE_KEY': status['SERVICE_ROLE_KEY'],
        'DIRECTA_ENV': 'local', 'DIRECTA_LOGIN_TEST': '1',
        'DIRECTA_ALLOWED_ORIGINS': 'http://localhost:8085,http://127.0.0.1:8085',
    }
    # Recuperar únicamente claves del proveedor IA que ya tenga el usuario.
    # Nunca copiar SUPABASE_URL/KEY del proyecto remoto.
    provider = read_env(ROOT / 'backend' / '.env')
    for key in ('NVIDIA_API_KEY', 'GROQ_API_KEY', 'GROQ_API_KEY_1', 'GROQ_API_KEY_2', 'GROQ_API_KEY_3', 'GROQ_API_KEY_4'):
        if provider.get(key):
            backend[key] = provider[key]
    if any('\n' in value or '\r' in value or "'" in value for value in backend.values()):
        raise SetupError('Una variable contiene caracteres no admitidos en el archivo de entorno.')
    private_write(PRIVATE / 'backend.local.env', '\n'.join(key + "='" + value + "'" for key, value in backend.items()) + '\n')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--init', action='store_true', help='Copiar credenciales de ejemplo si aún no existen')
    parser.add_argument('--start', action='store_true', help='Construir e iniciar además el backend local en el puerto 8001')
    args = parser.parse_args(argv)
    PRIVATE.mkdir(exist_ok=True)
    # Docker Desktop de Windows puede estar instalado por usuario.
    candidates = [Path(os.getenv('LOCALAPPDATA', '')) / 'Programs/DockerDesktop/resources/bin',
                  Path(os.getenv('ProgramFiles', 'C:/Program Files')) / 'Docker/Docker/resources/bin']
    os.environ['PATH'] = os.pathsep.join([*(str(p) for p in candidates if p.is_dir()), os.environ.get('PATH', '')])
    settings = PRIVATE / 'local-login.env'
    if args.init and not settings.exists():
        private_write(settings, (ROOT / 'dev' / 'local-login.example').read_text(encoding='utf-8'))
    values = read_env(settings)
    needed = ('LOCAL_ADMIN_LOGIN', 'LOCAL_ADMIN_PASSWORD', 'LOCAL_ADMIN_EMAIL', 'LOCAL_ORGANIZATION', 'LOCAL_DISPLAY_NAME')
    if not all(values.get(key) for key in needed):
        raise SetupError('Falta .directa/local-login.env. Ejecuta con --init para crear el laboratorio por primera vez.')
    if not all('\n' not in values[key] and '\x00' not in values[key] and '$' not in values[key] for key in needed):
        raise SetupError('La configuración local contiene caracteres no admitidos.')
    if '@' not in values['LOCAL_ADMIN_EMAIL']:
        raise SetupError('Configura un correo válido exclusivamente para pruebas locales.')
    config = (LOCAL / 'supabase' / 'config.toml').read_text(encoding='utf-8')
    if not re.search(r'^project_id\s*=\s*"' + re.escape(PROJECT) + r'"\s*$', config, re.M):
        raise SetupError('El config no corresponde al laboratorio dedicado. No continuar.')
    if (LOCAL / 'supabase' / '.temp' / 'project-ref').exists():
        raise SetupError('El directorio del laboratorio está enlazado a otro proyecto. Revisa esa configuración antes de continuar.')
    if os.getenv('DOCKER_HOST'):
        local_docker(os.environ['DOCKER_HOST'])
    endpoint = command(['docker', 'context', 'inspect', '--format', '{{json .Endpoints.docker.Host}}'], label='docker-context', timeout=30)
    try:
        local_docker(json.loads(endpoint))
    except (ValueError, TypeError):
        raise SetupError('No se pudo comprobar que el contexto Docker sea local.') from None
    command(['docker', 'info', '--format', '{{.ServerVersion}}'], label='docker', timeout=30)
    print('Iniciando Supabase local aislado (primera ejecución: descarga de imágenes)...', flush=True)
    command([*CLI, 'start', '--workdir', str(LOCAL)], label='supabase-start')
    raw = command([*CLI, 'status', '--workdir', str(LOCAL), '-o', 'json'], label='supabase-status', timeout=60)
    try:
        status = json.loads(raw)
    except ValueError:
        raise SetupError('No se pudo interpretar el estado de Supabase local.') from None
    configure(values, status)
    if args.start:
        print('Construyendo el backend local de DIRECTA...', flush=True)
        command(['docker', 'compose', '-f', 'docker-compose.login-local.yml', 'up', '-d', '--build'], label='backend-start')
    print('Laboratorio preparado. No se contactó ni modificó Supabase remoto.')
    print('La cuenta de prueba conserva MFA; configura el autenticador al entrar por primera vez.')
    print('Desde directa_V4/app:')
    print('flutter run -d chrome --web-port=8085 --dart-define-from-file=../.directa/auth.local.web.json')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (SetupError, KeyError) as error:
        print('No se completó el laboratorio: ' + str(error), file=sys.stderr)
        sys.exit(1)
