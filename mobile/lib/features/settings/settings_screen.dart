import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/stage_theme.dart';
import '../../core/updater/app_updater.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  bool _isTesting = false;
  String? _testResult;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = _api.baseUrl;
    _nameController.text = _api.userName;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final url = _urlController.text.trim();
    final name = _nameController.text.trim();
    if (url.isEmpty || name.isEmpty) return;

    await _api.updateSettings(url, name);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Ajustes guardados correctamente")),
    );
  }

  Future<void> _testConnection() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
      final cleanUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      final response = await dio.get("$cleanUrl/");
      stopwatch.stop();

      if (response.statusCode == 200) {
        setState(() {
          _isSuccess = true;
          _testResult = "Conexión exitosa con el servidor (${stopwatch.elapsedMilliseconds} ms)\nVersión: ${response.data["version"] ?? "1.0.0"}";
        });
      } else {
        setState(() {
          _isSuccess = false;
          _testResult = "Respuesta inesperada: Código ${response.statusCode}";
        });
      }
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _isSuccess = false;
        _testResult = "Error de conexión: No se pudo conectar con $url\nComprueba que el backend de Docker está levantado y en la misma red Wi-Fi o túnel.";
      });
    } finally {
      setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Configuración & Conexión"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabecera con la ilustración de Olla Gitana
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Image.asset(
                    "assets/images/band_hero.jpg",
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    color: StageTheme.surfaceElevated,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.local_fire_department, color: StageTheme.flameOrange),
                        SizedBox(width: 8),
                        Text(
                          "OLLA GITANA - APP OFICIAL",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: StageTheme.amberGold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Tarjeta de Actualizaciones de la App
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Actualizaciones de la App",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: StageTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: StageTheme.amberGold),
                          ),
                          child: const Text(
                            AppUpdater.currentVersion,
                            style: TextStyle(
                              color: StageTheme.amberGold,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Comprueba si hay una nueva versión del APK en GitHub para descargar e instalar mejoras en los móviles de la banda.",
                      style: TextStyle(color: StageTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.system_update),
                      label: const Text("Comprobar Actualizaciones"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StageTheme.surfaceElevated,
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: StageTheme.border),
                      ),
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Buscando actualizaciones en GitHub...")),
                        );
                        final update = await AppUpdater.checkForUpdates();
                        if (update != null && update["hasUpdate"] == true) {
                          AppUpdater.showUpdateDialog(context, update);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: StageTheme.electricGreen,
                              content: Text("¡Ya tienes instalada la última versión! (v1.0.0)"),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Identificación en la Banda",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Tu nombre o instrumento para firmar propuestas y votos en el repertorio.",
                      style: TextStyle(color: StageTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: "Nombre / Rol",
                        hintText: "Ej: Carlos (Guitarra) o Ana (Voz)",
                        filled: true,
                        fillColor: StageTheme.surfaceElevated,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Servidor Backend (Mac / Linux)",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Introduce la IP local de tu Mac (ej: http://192.168.1.45:8000), 10.0.2.2:8000 para emulador, o tu URL de túnel (Cloudflare / Tailscale).",
                      style: TextStyle(color: StageTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        labelText: "URL del Backend",
                        hintText: "http://192.168.1.X:8000",
                        filled: true,
                        fillColor: StageTheme.surfaceElevated,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.network_check),
                            label: const Text("Probar Conexión"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: StageTheme.amberGold,
                              side: const BorderSide(color: StageTheme.amberGold),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _isTesting ? null : _testConnection,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.save),
                            label: const Text("Guardar"),
                            onPressed: _saveSettings,
                          ),
                        ),
                      ],
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isSuccess
                              ? StageTheme.electricGreen.withOpacity(0.15)
                              : StageTheme.alertRed.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isSuccess ? StageTheme.electricGreen : StageTheme.alertRed,
                          ),
                        ),
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            color: _isSuccess ? StageTheme.electricGreen : StageTheme.alertRed,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
