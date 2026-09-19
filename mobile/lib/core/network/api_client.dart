import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late Dio _dio;
  String _baseUrl = "http://10.0.2.2:8000"; // Default para Android Emulator
  String _userName = "Músico Olla Gitana";

  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _loadSettings();
  }

  String get baseUrl => _baseUrl;
  String get userName => _userName;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString("backend_url") ?? "http://10.0.2.2:8000";
    _userName = prefs.getString("user_name") ?? "Músico Olla Gitana";
    _dio.options.baseUrl = _baseUrl;
  }

  Future<void> updateSettings(String newUrl, String newUserName) async {
    _baseUrl = newUrl.endsWith('/') ? newUrl.substring(0, newUrl.length - 1) : newUrl;
    _userName = newUserName;
    _dio.options.baseUrl = _baseUrl;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("backend_url", _baseUrl);
    await prefs.setString("user_name", _userName);
  }

  String getFullUrl(String path) {
    if (path.startsWith("http://") || path.startsWith("https://")) {
      return path;
    }
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return "$_baseUrl$cleanPath";
  }

  String getWebSocketUrl(String path) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final wsBase = _baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    return "$wsBase$cleanPath";
  }

  // --- Módulo 1: Letras (LRCLIB) ---
  Future<List<dynamic>> searchLyrics(String query) async {
    try {
      final response = await _dio.get("/api/v1/lyrics/search", queryParameters: {"q": query});
      return response.data["results"] ?? [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getLyrics(String track, String artist) async {
    try {
      final response = await _dio.get(
        "/api/v1/lyrics/get",
        queryParameters: {"track_name": track, "artist_name": artist},
      );
      return response.data;
    } catch (e) {
      return null;
    }
  }

  // --- Módulo 2: Separador de Stems (Demucs) ---
  Future<Map<String, dynamic>?> uploadAudioForStems(
    String filePath, {
    String model = "htdemucs",
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      final fileName = filePath.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(filePath, filename: fileName),
        "model": model,
      });

      final response = await _dio.post(
        "/api/v1/stems/upload",
        data: formData,
        onSendProgress: onProgress,
      );
      return response.data;
    } catch (e) {
      print("[ApiClient] Error subiendo audio para stems: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>?> getStemTask(String taskId) async {
    try {
      final response = await _dio.get("/api/v1/stems/tasks/$taskId");
      return response.data;
    } catch (e) {
      return null;
    }
  }

  Future<List<dynamic>> getRecentStemTasks() async {
    try {
      final response = await _dio.get("/api/v1/stems/tasks");
      return response.data ?? [];
    } catch (e) {
      return [];
    }
  }

  // --- Módulo 3: Acordes (Songsterr / Audio) ---
  Future<List<dynamic>> searchChords(String query) async {
    try {
      final response = await _dio.get("/api/v1/chords/search", queryParameters: {"query": query});
      return response.data["results"] ?? [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> extractChords({String? taskId, String? filePath}) async {
    try {
      FormData formData;
      if (taskId != null) {
        formData = FormData.fromMap({"task_id": taskId});
      } else if (filePath != null) {
        final fileName = filePath.split(Platform.pathSeparator).last;
        formData = FormData.fromMap({
          "file": await MultipartFile.fromFile(filePath, filename: fileName),
        });
      } else {
        return null;
      }

      final response = await _dio.post("/api/v1/chords/extract", data: formData);
      return response.data;
    } catch (e) {
      print("[ApiClient] Error extrayendo acordes: $e");
      return null;
    }
  }

  // --- Módulo 4: Repertorio Colaborativo (Spotify / Votación) ---
  Future<List<dynamic>> searchSpotify(String query) async {
    try {
      final response = await _dio.get(
        "/api/v1/repertoire/spotify/search",
        queryParameters: {"query": query},
      );
      return response.data["results"] ?? [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getRepertoireSongs({String? status}) async {
    try {
      final response = await _dio.get(
        "/api/v1/repertoire/songs",
        queryParameters: status != null ? {"status": status} : null,
      );
      return response.data ?? [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> createSongProposal({
    required String title,
    required String artist,
    String? album,
    String? coverUrl,
    String? previewUrl,
    String? spotifyId,
    String? notes,
  }) async {
    try {
      final response = await _dio.post(
        "/api/v1/repertoire/songs",
        data: {
          "title": title,
          "artist": artist,
          "album": album,
          "cover_url": coverUrl,
          "preview_url": previewUrl,
          "spotify_id": spotifyId,
          "proposed_by": _userName,
          "notes": notes,
        },
      );
      return response.data;
    } catch (e) {
      return null;
    }
  }

  Future<bool> updateSongStatus(int songId, String status) async {
    try {
      await _dio.patch(
        "/api/v1/repertoire/songs/$songId/status",
        data: {"status": status},
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> voteSong(int songId, int rating) async {
    try {
      await _dio.post(
        "/api/v1/repertoire/songs/$songId/vote",
        data: {
          "user_name": _userName,
          "rating": rating,
        },
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteSong(int songId) async {
    try {
      await _dio.delete("/api/v1/repertoire/songs/$songId");
      return true;
    } catch (e) {
      return false;
    }
  }
}
