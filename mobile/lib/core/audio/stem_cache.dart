import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Descarga y guarda en disco las pistas separadas para:
/// - Reproducir sin cortes ni rebuffering (clave para el bucle A-B de ensayo).
/// - Poder ensayar sin conexión al servidor.
class StemCache {
  StemCache._();
  static final StemCache instance = StemCache._();

  Directory? _cacheDir;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
  ));

  Future<Directory?> _dir() async {
    if (kIsWeb) return null;
    if (_cacheDir != null) return _cacheDir;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory("${base.path}/stems_cache");
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _cacheDir = dir;
      return dir;
    } catch (e) {
      print("[StemCache] No se pudo preparar el directorio de caché: $e");
      return null;
    }
  }

  String _fileNameFor(String url) {
    final clean = url.split("?").first;
    final base = clean.split("/").last;
    final key = clean.hashCode.abs().toRadixString(16);
    return "$key-$base";
  }

  /// Devuelve la ruta local de la pista, descargándola si hace falta.
  /// Si algo falla, devuelve null y se reproducirá en streaming.
  Future<String?> localPathFor(String url, {void Function(int received, int total)? onProgress}) async {
    if (kIsWeb) return null;
    final dir = await _dir();
    if (dir == null) return null;

    final file = File("${dir.path}/${_fileNameFor(url)}");
    try {
      if (file.existsSync() && file.lengthSync() > 1000) {
        return file.path;
      }

      final tmp = File("${file.path}.part");
      await _dio.download(url, tmp.path, onReceiveProgress: onProgress);
      if (!tmp.existsSync() || tmp.lengthSync() < 1000) {
        tmp.deleteSync();
        return null;
      }
      if (file.existsSync()) file.deleteSync();
      tmp.renameSync(file.path);
      return file.path;
    } catch (e) {
      print("[StemCache] Error cacheando $url: $e");
      return null;
    }
  }

  /// Tamaño total de la caché en bytes.
  Future<int> cacheSize() async {
    final dir = await _dir();
    if (dir == null) return 0;
    int total = 0;
    try {
      for (final entity in dir.listSync()) {
        if (entity is File) total += entity.lengthSync();
      }
    } catch (_) {}
    return total;
  }

  Future<void> clear() async {
    final dir = await _dir();
    if (dir == null) return;
    try {
      for (final entity in dir.listSync()) {
        if (entity is File) entity.deleteSync();
      }
    } catch (_) {}
  }
}
