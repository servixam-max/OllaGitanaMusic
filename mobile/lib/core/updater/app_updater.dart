import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/stage_theme.dart';

class AppUpdater {
  static const String currentVersion = "v1.0.16";
  static const String repoUrl = "https://api.github.com/repos/servixam-max/OllaGitanaMusic/releases/latest";

  /// Comprueba semánticamente si una versión es superior a otra (ej. v1.0.12 > v1.0.9)
  static bool isNewerVersion(String latest, String current) {
    try {
      // Quitar sufijos de build (+12) o prerelease (-beta) antes de limpiar
      final cleanLatest = latest.split(RegExp(r'[-+]')).first.replaceAll(RegExp(r'[^0-9.]'), '');
      final cleanCurrent = current.split(RegExp(r'[-+]')).first.replaceAll(RegExp(r'[^0-9.]'), '');
      final latestParts = cleanLatest.split('.').where((s) => s.isNotEmpty).map(int.parse).toList();
      final currentParts = cleanCurrent.split('.').where((s) => s.isNotEmpty).map(int.parse).toList();
      final maxLength = latestParts.length > currentParts.length ? latestParts.length : currentParts.length;
      for (int i = 0; i < maxLength; i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (_) {
      return latest.trim() != current.trim();
    }
  }

  /// Comprueba en GitHub Releases si hay una versión superior a la instalada
  static Future<Map<String, dynamic>?> checkForUpdates() async {
    if (kIsWeb) {
      return {
        "success": true,
        "hasUpdate": false,
        "currentVersion": currentVersion,
        "isWeb": true,
      };
    }
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          "User-Agent": "OllaGitanaMusic-App/1.0",
          "Accept": "application/vnd.github.v3+json",
        },
      ));

      Response response;
      try {
        response = await dio.get(repoUrl);
      } catch (_) {
        response = await dio.get("https://api.github.com/repos/servixam-max/OllaGitanaMusic/releases");
      }

      dynamic data;
      if (response.statusCode == 200) {
        if (response.data is List && (response.data as List).isNotEmpty) {
          data = response.data[0];
        } else if (response.data is Map) {
          data = response.data;
        }
      }

      if (data != null) {
        final latestTag = (data["tag_name"] ?? "").toString().trim();

        // Buscar el archivo .apk entre los assets de la release
        final assets = data["assets"] as List<dynamic>? ?? [];
        String? apkDownloadUrl;
        for (final asset in assets) {
          final name = asset["name"]?.toString().toLowerCase() ?? "";
          if (name.endsWith(".apk")) {
            apkDownloadUrl = asset["browser_download_url"];
            break;
          }
        }

        // Si no hay asset específico, usar el enlace web de la release
        apkDownloadUrl ??= data["html_url"];

        final hasUpdate = latestTag.isNotEmpty && isNewerVersion(latestTag, currentVersion);

        return {
          "success": true,
          "hasUpdate": hasUpdate,
          "latestVersion": latestTag,
          "currentVersion": currentVersion,
          "downloadUrl": apkDownloadUrl,
          "releaseNotes": data["body"] ?? "Mejoras de rendimiento y nuevas funciones para Olla Gitana.",
        };
      }
    } catch (e) {
      print("[AppUpdater] Error comprobando actualizaciones: $e");
      return {
        "success": false,
        "hasUpdate": false,
        "currentVersion": currentVersion,
        "error": e.toString(),
      };
    }
    return {
      "success": false,
      "hasUpdate": false,
      "currentVersion": currentVersion,
    };
  }

  /// Descarga el APK abriendo el navegador del teléfono para instalarlo
  static Future<void> launchUpdateUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      print("[AppUpdater] Error abriendo URL de actualización: $e");
    }
  }

  /// Muestra un modal elegante de actualización en la pantalla
  static void showUpdateDialog(BuildContext context, Map<String, dynamic> updateInfo) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: StageTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: StageTheme.flameOrange, width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.system_update, color: StageTheme.amberGold, size: 28),
              const SizedBox(width: 10),
              const Text(
                "¡Nueva Versión!",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Hay una nueva versión disponible de Olla Gitana Music:\n${updateInfo["latestVersion"]} (Versión actual: ${updateInfo["currentVersion"]})",
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: StageTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  updateInfo["releaseNotes"] ?? "Novedades disponibles.",
                  style: const TextStyle(color: StageTheme.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Más tarde", style: TextStyle(color: StageTheme.textSecondary)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text("Descargar e Instalar"),
              style: ElevatedButton.styleFrom(
                backgroundColor: StageTheme.flameOrange,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                final downloadUrl = updateInfo["downloadUrl"];
                if (downloadUrl != null) {
                  launchUpdateUrl(downloadUrl);
                }
              },
            ),
          ],
        );
      },
    );
  }
}
