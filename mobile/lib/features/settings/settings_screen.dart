import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../core/audio/stem_cache.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/stage_theme.dart';
import '../../core/updater/app_updater.dart';
import '../../core/widgets/member_selector_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  bool _isTesting = false;
  String? _testResult;
  bool _isSuccess = false;
  int _cacheSizeBytes = 0;

  @override
  void initState() {
    super.initState();
    _urlController.text = _api.baseUrl;
    _nameController.text = _api.userName;
    _tokenController.text = _api.apiToken;
    _api.userNameNotifier.addListener(_onUserNameChanged);
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final size = await StemCache.instance.cacheSize();
    if (mounted) setState(() => _cacheSizeBytes = size);
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 MB";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(0)} KB";
    if (bytes < 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  }

  void _onUserNameChanged() {
    if (mounted) {
      if (_nameController.text != _api.userName) {
        _nameController.text = _api.userName;
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _api.userNameNotifier.removeListener(_onUserNameChanged);
    _urlController.dispose();
    _nameController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final url = _urlController.text.trim();
    final name = _nameController.text.trim();
    if (url.isEmpty || name.isEmpty) return;

    await _api.updateSettings(url, name, apiToken: _tokenController.text);
    // Asegurar que también se registre como miembro en el backend si es nuevo
    _api.addBandMember(name);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: StageTheme.electricGreen,
          content: Text("Ajustes guardados: Músico activo '$name'"),
        ),
      );
    }
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
                            border: Border.all(color: kIsWeb ? StageTheme.electricGreen : StageTheme.amberGold),
                          ),
                          child: Text(
                            kIsWeb ? "${AppUpdater.currentVersion} (Web PWA)" : AppUpdater.currentVersion,
                            style: TextStyle(
                              color: kIsWeb ? StageTheme.electricGreen : StageTheme.amberGold,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kIsWeb
                          ? "Estás en la versión Web PWA para iOS / Navegador. Se actualiza sola desde el servidor; si el navegador guardó una copia antigua, aquí podrás detectarlo y recargar."
                          : "Comprueba si hay una nueva versión del APK en GitHub para descargar e instalar mejoras en los móviles de la banda.",
                      style: const TextStyle(color: StageTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.system_update),
                      label: Text(kIsWeb ? "Comprobar Versión Web" : "Comprobar Actualizaciones"),
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
                        } else if (update != null && update["success"] == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: StageTheme.electricGreen,
                              content: Text("¡Ya tienes instalada la última versión! (${AppUpdater.currentVersion})"),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: StageTheme.alertRed,
                              content: Text("No se pudo conectar con GitHub para comprobar. Revisa tu conexión."),
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
                      "Tus votos, canciones y eventos se guardarán con tu nombre:",
                      style: TextStyle(color: StageTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<String>(
                      valueListenable: _api.userNameNotifier,
                      builder: (context, currentName, _) {
                        final isIdentified = _api.isUserIdentified;
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: StageTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isIdentified ? StageTheme.amberGold : StageTheme.border,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: isIdentified ? StageTheme.amberGold : StageTheme.border,
                                foregroundColor: isIdentified ? Colors.black : StageTheme.textSecondary,
                                child: const Icon(Icons.person, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Músico Activo:", style: TextStyle(color: StageTheme.textSecondary, fontSize: 11)),
                                    Text(
                                      isIdentified ? currentName : "Sin seleccionar",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: isIdentified ? StageTheme.amberGold : StageTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.swap_horiz, size: 18),
                                label: const Text("Cambiar"),
                                style: ElevatedButton.styleFrom(backgroundColor: StageTheme.flameOrange),
                                onPressed: () async {
                                  final chosen = await showMemberSelectorDialog(context);
                                  if (chosen != null && mounted) {
                                    _nameController.text = chosen;
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: "O escribe un nombre personalizado",
                        hintText: "Ej: Champi, Rubén, Mario, Miguel...",
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tokenController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "Token de seguridad (opcional)",
                        hintText: "Igual que API_TOKEN en el servidor",
                        helperText: "Obligatorio si el servidor está expuesto por túnel a Internet",
                        helperStyle: const TextStyle(fontSize: 11),
                        filled: true,
                        fillColor: StageTheme.surfaceElevated,
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
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
                              ? StageTheme.electricGreen.withValues(alpha: 0.15)
                              : StageTheme.alertRed.withValues(alpha: 0.15),
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
            const SizedBox(height: 16),
            // Tarjeta de almacenamiento del ensayo (pistas cacheadas offline)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Almacenamiento de Ensayo",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Las pistas que cargas en el mezclador se guardan en el teléfono para ensayar sin cortes y sin conexión. Ocupan espacio: puedes liberarlo aquí.",
                      style: const TextStyle(color: StageTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.sd_storage, color: StageTheme.amberGold),
                        const SizedBox(width: 8),
                        Text(
                          "Pistas guardadas: ${_formatBytes(_cacheSizeBytes)}",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_sweep),
                      label: const Text("Liberar espacio de pistas"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: StageTheme.alertRed,
                        side: const BorderSide(color: StageTheme.alertRed),
                      ),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: StageTheme.surface,
                            title: const Text("Liberar espacio"),
                            content: const Text(
                              "Se borrarán las pistas descargadas en este teléfono. "
                              "Podrás volver a cargarlas desde el servidor cuando quieras, "
                              "pero hasta entonces no podrás ensayar sin conexión.",
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text("Cancelar", style: TextStyle(color: StageTheme.textSecondary)),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: StageTheme.alertRed,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text("Liberar"),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        await StemCache.instance.clear();
                        await _loadCacheSize();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Caché de pistas liberada")),
                          );
                        }
                      },
                    ),
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
