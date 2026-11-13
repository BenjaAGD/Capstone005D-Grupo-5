"""Controles del bootstrap, sin Docker y sin escribir en Supabase."""
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('bootstrap', Path(__file__).with_name('bootstrap_local.py'))
bootstrap = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bootstrap)
VALUES = {'LOCAL_ADMIN_LOGIN': 'operador', 'LOCAL_ADMIN_PASSWORD': 'clave-local',
          'LOCAL_ADMIN_EMAIL': 'operador@directa.local', 'LOCAL_ORGANIZATION': 'Laboratorio',
          'LOCAL_DISPLAY_NAME': 'Prueba'}
STATUS = {'API_URL': 'http://127.0.0.1:55421', 'DB_URL': 'postgresql://postgres:postgres@127.0.0.1:55422/postgres',
          'ANON_KEY': 'sb_publishable_test', 'SERVICE_ROLE_KEY': 'sb_secret_test'}


class BootstrapTests(unittest.TestCase):
    def test_docker_debe_ser_del_equipo_local(self):
        for endpoint in ('unix:///var/run/docker.sock', 'npipe:////./pipe/dockerDesktopLinuxEngine', 'tcp://127.0.0.1:2375'):
            bootstrap.local_docker(endpoint)
        for endpoint in ('ssh://servidor.example', 'tcp://10.0.0.8:2375', 'https://docker.example:2376'):
            with self.subTest(endpoint=endpoint), self.assertRaises(bootstrap.SetupError):
                bootstrap.local_docker(endpoint)
    def test_solo_el_puerto_de_la_instancia_local(self):
        for url in ('https://proyecto.supabase.co', 'http://127.0.0.1:54321', 'http://10.0.0.8:55421',
                    'http://user:pass@127.0.0.1:55421', 'http://127.0.0.1:55421/otra',
                    'http://127.0.0.1:55421?url=remoto'):
            with self.subTest(url=url), self.assertRaises(bootstrap.SetupError):
                bootstrap.checked_url(url, 'http', 55421)
    def test_configuracion_cliente_no_lleva_secretos(self):
        config = bootstrap.public_config(STATUS, VALUES)
        encoded = json.dumps(config)
        self.assertNotIn(STATUS['SERVICE_ROLE_KEY'], encoded)
        self.assertNotIn(VALUES['LOCAL_ADMIN_PASSWORD'], encoded)
        self.assertNotIn('SUPABASE_KEY', config)
        self.assertEqual(config['DIRECTA_ENV'], 'local')
        self.assertTrue(config['DIRECTA_LOCAL_TEST_ACCOUNT'])
    def test_clave_privada_no_se_compila(self):
        for key in ('sb_secret_otra', STATUS['SERVICE_ROLE_KEY']):
            with self.subTest(key=key), self.assertRaises(bootstrap.SetupError):
                bootstrap.public_config({**STATUS, 'ANON_KEY': key}, VALUES)
    def test_destino_remoto_rechazado_antes_de_red_y_sql(self):
        with patch.object(bootstrap, 'sql') as sql, patch.object(bootstrap, 'auth_request') as http:
            with self.assertRaises(bootstrap.SetupError):
                bootstrap.configure(VALUES, {**STATUS, 'API_URL': 'https://remoto.supabase.co'})
            sql.assert_not_called(); http.assert_not_called()
    def test_cuenta_previa_ajena_no_se_sobrescribe(self):
        with patch.object(bootstrap, 'auth_request', return_value={'users': [{'id': 'ajeno', 'email': VALUES['LOCAL_ADMIN_EMAIL']}]}) as http:
            with self.assertRaises(bootstrap.SetupError):
                bootstrap.create_or_find_user(STATUS['API_URL'], STATUS['SERVICE_ROLE_KEY'], VALUES)
            self.assertTrue(all(c.args[2] == 'GET' for c in http.call_args_list))
    def test_alta_real_con_derivacion_sin_bypass(self):
        calls = []
        def request(*args):
            calls.append(args)
            return {'users': []} if args[2] == 'GET' else {'id': '10000000-0000-4000-8000-000000000001'}
        with patch.object(bootstrap, 'auth_request', side_effect=request):
            bootstrap.create_or_find_user(STATUS['API_URL'], STATUS['SERVICE_ROLE_KEY'], VALUES)
        payload = calls[-1][4]
        self.assertEqual(payload['password'], bootstrap.local_password(VALUES['LOCAL_ADMIN_PASSWORD']))
        self.assertEqual(len(payload['password']), 64)
        self.assertNotEqual(payload['password'], bootstrap.local_password('incorrecta'))
        self.assertTrue(payload['email_confirm'])
        self.assertNotIn('factors', payload)
    def test_sql_local_no_borra_tablas(self):
        sql = (bootstrap.LOCAL / 'initial_schema.sql').read_text()
        self.assertNotIn('drop table', sql.lower())
        self.assertNotIn('using (true)', sql.lower())
        self.assertIn('auth.users', sql)
        self.assertIn('directa-login-local', sql)


if __name__ == '__main__':
    unittest.main()
