import 'package:web/web.dart' as web;

/// Recarga la PWA en el navegador (fuerza la descarga del bundle nuevo).
void reloadApp() {
  web.window.location.reload();
}
