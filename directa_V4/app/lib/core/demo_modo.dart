import 'package:flutter/foundation.dart';

/// Acceso demo: se entra desde el login con el botón "Abrir demo".
///
/// Sirve para entrar a la app cuando el inicio de sesión o el registro no funcionan. No usa
/// Supabase Auth, pero la app trabaja con el servidor igual que con una cuenta normal
/// (subir documentos, análisis, chat, dashboard…).
class DemoModo extends ChangeNotifier {
  DemoModo._();
  static final DemoModo instance = DemoModo._();

  bool activo = false;

  void entrar() {
    activo = true;
    notifyListeners();
  }

  void salir() {
    activo = false;
    notifyListeners();
  }
}
