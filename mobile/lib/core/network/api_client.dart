import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late Dio _dio;
  late Dio _publicDio; // Cliente HTTP directo para fallbacks cuando el backend local no está encendido
  String _baseUrl = "https://servi.tail31979d.ts.net/olla";
  String _userName = "Músico Olla Gitana";

  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
    ));
    _publicDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
    ));
    _loadSettings();
  }

  String get baseUrl => _baseUrl;
  String get userName => _userName;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString("backend_url") ?? "https://servi.tail31979d.ts.net/olla";
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

  // --- Módulo 1: Letras (LRCLIB + Fallback directo) ---
  Future<List<dynamic>> searchLyrics(String query) async {
    try {
      final response = await _dio.get("/api/v1/lyrics/search", queryParameters: {"q": query});
      final results = response.data["results"] as List<dynamic>?;
      if (results != null && results.isNotEmpty) return results;
    } catch (_) {}

    // Fallback directo a LRCLIB desde el móvil si el backend local no está encendido
    try {
      final resp = await _publicDio.get(
        "https://lrclib.net/api/search",
        queryParameters: {"q": query},
        options: Options(headers: {"User-Agent": "OllaGitanaMusic/1.0"}),
      );
      if (resp.statusCode == 200) {
        return (resp.data as List<dynamic>).map((item) {
          return {
            "id": item["id"],
            "track_name": item["trackName"],
            "artist_name": item["artistName"],
            "album_name": item["albumName"],
            "duration": item["duration"],
            "plain_lyrics": item["plainLyrics"],
            "synced_lyrics": item["syncedLyrics"],
            "lines": _parseLrc(item["syncedLyrics"]),
          };
        }).toList();
      }
    } catch (_) {}

    return [];
  }

  List<Map<String, dynamic>> _parseLrc(String? lrc) {
    if (lrc == null) return [];
    final List<Map<String, dynamic>> parsed = [];
    final pattern = RegExp(r"\[(\d+):(\d+(?:\.\d+)?)\](.*)");
    for (final line in lrc.split('\n')) {
      final match = pattern.firstMatch(line.trim());
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = double.parse(match.group(2)!);
        final timeMs = ((minutes * 60 + seconds) * 1000).toInt();
        parsed.add({"time_ms": timeMs, "text": match.group(3)?.trim() ?? ""});
      }
    }
    return parsed;
  }

  // --- Módulo 2: Stems ---
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

  // --- Módulo 3: Acordes (Songsterr + Fallback directo) ---
  Future<List<dynamic>> searchChords(String query) async {
    try {
      final response = await _dio.get("/api/v1/chords/search", queryParameters: {"query": query});
      final results = response.data["results"] as List<dynamic>?;
      if (results != null && results.isNotEmpty) return results;
    } catch (_) {}

    // Fallback directo a Songsterr API
    try {
      final resp = await _publicDio.get(
        "https://www.songsterr.com/api/songs",
        queryParameters: {"pattern": query},
        options: Options(headers: {"User-Agent": "OllaGitanaMusic/1.0"}),
      );
      if (resp.statusCode == 200) {
        return (resp.data as List<dynamic>).take(15).map((item) {
          final songId = item["songId"];
          return {
            "source": "Songsterr",
            "id": songId,
            "title": item["title"] ?? "Sin título",
            "artist": item["artist"] ?? "Desconocido",
            "url": "https://www.songsterr.com/a/wa/song?id=$songId",
            "has_chords": item["hasChords"] ?? true,
          };
        }).toList();
      }
    } catch (_) {}

    return [];
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
      return null;
    }
  }

  // --- Módulo 4: Repertorio & Previews (Deezer / iTunes / Spotify Fallback Directo) ---
  Future<List<dynamic>> searchSpotify(String query) async {
    // 1. Intentar a través del backend
    try {
      final response = await _dio.get(
        "/api/v1/repertoire/spotify/search",
        queryParameters: {"query": query},
      );
      final results = response.data["results"] as List<dynamic>?;
      if (results != null && results.isNotEmpty) return results;
    } catch (_) {}

    // 2. Fallback directo a Deezer API (Previsualizaciones MP3 reales de 30s y carátulas HD)
    try {
      final resp = await _publicDio.get(
        "https://api.deezer.com/search",
        queryParameters: {"q": query, "limit": 15},
      );
      if (resp.statusCode == 200) {
        final data = resp.data["data"] as List<dynamic>? ?? [];
        if (data.isNotEmpty) {
          return data.map((item) {
            final album = item["album"] ?? {};
            final artist = item["artist"] ?? {};
            return {
              "spotify_id": "deezer_${item["id"]}",
              "title": item["title"],
              "artist": artist["name"] ?? "Desconocido",
              "album": album["title"],
              "cover_url": album["cover_xl"] ?? album["cover_big"] ?? album["cover_medium"],
              "preview_url": item["preview"], // URL MP3 de 30 segundos
              "duration_ms": (item["duration"] ?? 0) * 1000,
              "source": "Deezer",
            };
          }).toList();
        }
      }
    } catch (_) {}

    // 3. Fallback directo a iTunes Search API
    try {
      final resp = await _publicDio.get(
        "https://itunes.apple.com/search",
        queryParameters: {"term": query, "entity": "song", "limit": 15},
      );
      if (resp.statusCode == 200) {
        final results = resp.data["results"] as List<dynamic>? ?? [];
        return results.map((item) {
          String? cover = item["artworkUrl100"];
          if (cover != null) {
            cover = cover.replaceAll("100x100bb.jpg", "600x600bb.jpg");
          }
          return {
            "spotify_id": "itunes_${item["trackId"]}",
            "title": item["trackName"],
            "artist": item["artistName"],
            "album": item["collectionName"],
            "cover_url": cover,
            "preview_url": item["previewUrl"],
            "duration_ms": item["trackTimeMillis"] ?? 0,
            "source": "iTunes",
          };
        }).toList();
      }
    } catch (_) {}

    return [];
  }

  Future<List<dynamic>> getRepertoireSongs({String? status}) async {
    try {
      final response = await _dio.get(
        "/api/v1/repertoire/songs",
        queryParameters: status != null ? {"status": status} : null,
      );
      return response.data ?? [];
    } catch (_) {
      // Si el backend local no está encendido, devolver canciones demo de la banda
      return [
        {
          "id": 1,
          "title": "Entre Dos Aguas",
          "artist": "Paco de Lucía",
          "album": "Fuente y Caudal",
          "cover_url": "https://e-cdns-images.dzcdn.net/images/cover/b41d0179b02a2455b85a3c94fca240f9/500x500-000000-80-0-0.jpg",
          "preview_url": "https://cdnt-preview.dzcdn.net/api/1/1/a/7/f/0/a7f62f171996bd5b8eaf03689ceed583.mp3",
          "status": "en_repertorio",
          "proposed_by": "Carlos (Guitarra)",
          "average_rating": 5.0,
          "total_votes": 4,
        },
        {
          "id": 2,
          "title": "Volando Voy",
          "artist": "Camarón de la Isla",
          "album": "La Leyenda del Tiempo",
          "cover_url": "https://e-cdns-images.dzcdn.net/images/cover/6c669e46a7ce04535870a463a56ad4a2/500x500-000000-80-0-0.jpg",
          "preview_url": "https://cdnt-preview.dzcdn.net/api/1/1/1/6/7/0/167b5e679b392b95a8286a07997864aa.mp3",
          "status": "para_ensayar",
          "proposed_by": "Manuel (Cajón)",
          "average_rating": 4.8,
          "total_votes": 3,
        }
      ];
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
    } catch (_) {
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
    } catch (_) {
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
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteSong(int songId) async {
    try {
      await _dio.delete("/api/v1/repertoire/songs/$songId");
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- Módulo 5: Eventos, Bolos & Setlists ---
  Future<List<dynamic>> getEvents() async {
    try {
      final response = await _dio.get("/api/v1/events");
      final data = response.data as List<dynamic>?;
      if (data != null) {
        // Guardar en cache local
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("cached_events", jsonEncode(data));
        return data;
      }
    } catch (_) {}

    // Fallback a cache local
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString("cached_events");
      if (cached != null) {
        return jsonDecode(cached) as List<dynamic>;
      }
    } catch (_) {}

    return [];
  }

  Future<Map<String, dynamic>?> createEvent({
    required String name,
    required String eventDate,
    String? location,
    String? notes,
    List<Map<String, dynamic>> setlist = const [],
  }) async {
    try {
      final response = await _dio.post(
        "/api/v1/events",
        data: {
          "name": name,
          "event_date": eventDate,
          "location": location,
          "notes": notes,
          "setlist": setlist,
        },
      );
      return response.data;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateEvent(
    String eventId, {
    String? name,
    String? eventDate,
    String? location,
    String? notes,
    List<Map<String, dynamic>>? setlist,
  }) async {
    try {
      final Map<String, dynamic> payload = {};
      if (name != null) payload["name"] = name;
      if (eventDate != null) payload["event_date"] = eventDate;
      if (location != null) payload["location"] = location;
      if (notes != null) payload["notes"] = notes;
      if (setlist != null) payload["setlist"] = setlist;

      final response = await _dio.put("/api/v1/events/$eventId", data: payload);
      return response.data;
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteEvent(String eventId) async {
    try {
      await _dio.delete("/api/v1/events/$eventId");
      return true;
    } catch (_) {
      return false;
    }
  }
}
