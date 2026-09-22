import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late Dio _dio;
  late Dio _publicDio; // Cliente HTTP directo para fallbacks cuando el backend local no está encendido
  String _baseUrl = "https://servi.tail31979d.ts.net/olla";
  String _userName = "Músico Olla Gitana";
  String _apiToken = "";

  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
    ));
    _publicDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
    ));
    _loadSettings();
  }

  static const List<String> defaultMembers = ["Champi", "Rubén", "Mario", "Miguel"];

  /// Notificador reactivo para que cualquier widget (barra superior, ajustes, diálogos)
  /// se actualice inmediatamente en toda la app cuando cambie el músico activo.
  final ValueNotifier<String> userNameNotifier = ValueNotifier<String>("Músico Olla Gitana");

  /// Estado de conexión con el backend (para mostrar avisos si está caído).
  final ValueNotifier<bool> isServerOnlineNotifier = ValueNotifier<bool>(true);

  String get baseUrl => _baseUrl;
  String get userName => _userName;
  String get apiToken => _apiToken;
  bool get isUserIdentified => _userName != "Músico Olla Gitana" && _userName.trim().isNotEmpty;

  Future<void> setUserName(String name) async {
    _userName = name.trim();
    userNameNotifier.value = _userName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("user_name", _userName);
  }

  Future<void> ensureInitialized() async {
    await _loadSettings();
  }

  Future<bool> checkConnection() async {
    try {
      final response = await _dio.get("/");
      final online = response.statusCode == 200;
      isServerOnlineNotifier.value = online;
      return online;
    } catch (_) {
      isServerOnlineNotifier.value = false;
      return false;
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (kIsWeb) {
      final origin = Uri.base.origin;
      final isOllaPath = Uri.base.path.contains('/olla');
      final defaultWebUrl = isOllaPath ? '$origin/olla' : origin;
      _baseUrl = prefs.getString("backend_url") ?? defaultWebUrl;
    } else {
      _baseUrl = prefs.getString("backend_url") ?? "https://servi.tail31979d.ts.net/olla";
    }
    _userName = prefs.getString("user_name") ?? "Músico Olla Gitana";
    _apiToken = prefs.getString("api_token") ?? "";
    userNameNotifier.value = _userName;
    _dio.options.baseUrl = _baseUrl;
    _applyTokenHeader();
  }

  void _applyTokenHeader() {
    if (_apiToken.isNotEmpty) {
      _dio.options.headers["X-API-Token"] = _apiToken;
    } else {
      _dio.options.headers.remove("X-API-Token");
    }
  }

  Future<void> updateSettings(String newUrl, String newUserName, {String? apiToken}) async {
    _baseUrl = newUrl.endsWith('/') ? newUrl.substring(0, newUrl.length - 1) : newUrl;
    _userName = newUserName.trim();
    userNameNotifier.value = _userName;
    _dio.options.baseUrl = _baseUrl;
    if (apiToken != null) {
      _apiToken = apiToken.trim();
      _applyTokenHeader();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("backend_url", _baseUrl);
    await prefs.setString("user_name", _userName);
    await prefs.setString("api_token", _apiToken);
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

  /// Crea un canal WebSocket con reconexión automática y backoff exponencial.
  /// El callback [onMessage] recibe el texto de cada mensaje.
  /// Devuelve un objeto con `dispose()` para cerrar el canal definitivamente.
  WebSocketReconnect createReconnectingSocket(
    String path, {
    required void Function(String message) onMessage,
    void Function(bool connected)? onStatusChange,
    Duration maxBackoff = const Duration(seconds: 20),
  }) {
    return WebSocketReconnect(
      url: getWebSocketUrl(path),
      onMessage: onMessage,
      onStatusChange: onStatusChange,
      maxBackoff: maxBackoff,
    );
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
    parsed.sort((a, b) => (a["time_ms"] as int).compareTo(b["time_ms"] as int));
    return parsed;
  }

  // --- Caché offline de letras ---
  Future<void> cacheLyrics(Map<String, dynamic> song) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList("cached_lyrics") ?? [];
      final entry = jsonEncode(song);
      cached.removeWhere((c) {
        try {
          return jsonDecode(c)["id"] == song["id"];
        } catch (_) {
          return false;
        }
      });
      cached.insert(0, entry);
      if (cached.length > 30) cached.removeRange(30, cached.length);
      await prefs.setStringList("cached_lyrics", cached);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getCachedLyrics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList("cached_lyrics") ?? [];
      return cached
          .map((c) => Map<String, dynamic>.from(jsonDecode(c)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> removeCachedLyrics(dynamic id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList("cached_lyrics") ?? [];
      cached.removeWhere((c) {
        try {
          return jsonDecode(c)["id"] == id;
        } catch (_) {
          return false;
        }
      });
      await prefs.setStringList("cached_lyrics", cached);
    } catch (_) {}
  }

  // --- Módulo 2: Stems ---
  Future<List<dynamic>> getStemPresets() async {
    try {
      final response = await _dio.get("/api/v1/stems/presets");
      return response.data["presets"] as List<dynamic>? ?? [];
    } catch (_) {
      return const [
        {
          "key": "fast",
          "label": "Rápida",
          "description": "4 pistas, la más rápida.",
          "format": "mp3",
        },
        {
          "key": "balanced",
          "label": "Equilibrada",
          "description": "4 pistas de alta calidad.",
          "format": "mp3",
        },
        {
          "key": "max",
          "label": "Máxima",
          "description": "4 pistas en WAV 24-bit.",
          "format": "wav",
        },
        {
          "key": "six",
          "label": "6 pistas",
          "description": "Incluye guitarra y piano.",
          "format": "mp3",
        },
        {
          "key": "hybrid",
          "label": "Híbrida (recomendada)",
          "description": "Máxima calidad en las 6 pistas.",
          "format": "mp3",
        },
        {
          "key": "karaoke",
          "label": "Karaoke",
          "description": "Solo voz e instrumental.",
          "format": "mp3",
        },
      ];
    }
  }

  Future<Map<String, dynamic>?> uploadAudioForStems({
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
    String? collectionName,
    String preset = "hybrid",
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      MultipartFile multipartFile;
      if (fileBytes != null) {
        multipartFile = MultipartFile.fromBytes(fileBytes, filename: fileName ?? "audio.mp3");
      } else if (filePath != null) {
        final cleanName = filePath.split(RegExp(r'[/\\]')).last;
        multipartFile = await MultipartFile.fromFile(filePath, filename: cleanName);
      } else {
        return null;
      }

      final formData = FormData.fromMap({
        "file": multipartFile,
        "collection_name": collectionName ?? "",
        "preset": preset,
      });

      final response = await _dio.post(
        "/api/v1/stems/upload",
        data: formData,
        onSendProgress: onProgress,
        options: Options(receiveTimeout: const Duration(minutes: 10), sendTimeout: const Duration(minutes: 10)),
      );
      return response.data;
    } catch (e) {
      print("[ApiClient] Error subiendo audio: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>?> retryStemTask(String taskId) async {
    try {
      final response = await _dio.post("/api/v1/stems/tasks/$taskId/retry");
      return response.data;
    } catch (_) {
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

  Future<bool> deleteStemTask(String taskId) async {
    try {
      await _dio.delete("/api/v1/stems/tasks/$taskId");
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setTaskCollection(String taskId, String? collectionName) async {
    try {
      await _dio.patch(
        "/api/v1/stems/tasks/$taskId/collection",
        data: {"collection_name": collectionName},
      );
      return true;
    } catch (_) {
      return false;
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

  Future<Map<String, dynamic>?> extractChords({
    String? taskId,
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    try {
      FormData formData;
      if (taskId != null) {
        formData = FormData.fromMap({"task_id": taskId});
      } else if (fileBytes != null) {
        formData = FormData.fromMap({
          "file": MultipartFile.fromBytes(fileBytes, filename: fileName ?? "audio.mp3"),
        });
      } else if (filePath != null) {
        final cleanName = filePath.split(RegExp(r'[/\\]')).last;
        formData = FormData.fromMap({
          "file": await MultipartFile.fromFile(filePath, filename: cleanName),
        });
      } else {
        return null;
      }

      final response = await _dio.post(
        "/api/v1/chords/extract",
        data: formData,
        options: Options(receiveTimeout: const Duration(minutes: 5), sendTimeout: const Duration(minutes: 5)),
      );
      return response.data;
    } catch (e) {
      print("[ApiClient] Error analizando acordes: $e");
      return null;
    }
  }

  Future<List<dynamic>> getChordHistory() async {
    try {
      final response = await _dio.get("/api/v1/chords/history");
      return response.data as List<dynamic>? ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> deleteChordAnalysis(String id) async {
    try {
      await _dio.delete("/api/v1/chords/history/$id");
      return true;
    } catch (_) {
      return false;
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
      return response.data as List<dynamic>? ?? [];
    } catch (e) {
      print("[ApiClient] Error obteniendo canciones del repertorio: $e");
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

  Future<bool> voteSongLike(int songId, bool liked) async {
    try {
      await _dio.post(
        "/api/v1/repertoire/songs/$songId/vote",
        data: {
          "user_name": _userName,
          "liked": liked,
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

  // --- Módulo 6: Miembros de la Banda & Identidad ---
  Future<List<Map<String, dynamic>>> getBandMembers() async {
    try {
      final response = await _dio.get("/api/v1/members");
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List).map((m) => Map<String, dynamic>.from(m)).toList();
      }
    } catch (_) {}

    return defaultMembers.map((n) => {"name": n, "role": "Músico", "avatar_color": "#E5A93C"}).toList();
  }

  Future<bool> addBandMember(String name, {String? role}) async {
    try {
      final response = await _dio.post(
        "/api/v1/members",
        data: {"name": name.trim(), "role": role ?? "Músico"},
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

/// Canal WebSocket con reconexión automática y backoff exponencial.
class WebSocketReconnect {
  WebSocketReconnect({
    required this.url,
    required this.onMessage,
    this.onStatusChange,
    this.maxBackoff = const Duration(seconds: 20),
  }) {
    _connect();
  }

  final String url;
  final void Function(String message) onMessage;
  final void Function(bool connected)? onStatusChange;
  final Duration maxBackoff;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _retryTimer;
  Duration _backoff = const Duration(seconds: 1);
  bool _disposed = false;
  bool _connected = false;

  bool get isConnected => _connected;

  void _connect() {
    if (_disposed) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _subscription = _channel!.stream.listen(
        (data) {
          _backoff = const Duration(seconds: 1);
          if (!_connected) {
            _connected = true;
            onStatusChange?.call(true);
          }
          onMessage(data.toString());
        },
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_connected) {
      _connected = false;
      onStatusChange?.call(false);
    }
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    _retryTimer?.cancel();
    _retryTimer = Timer(_backoff, () {
      if (_disposed) return;
      _connect();
      final next = _backoff * 2;
      _backoff = next > maxBackoff ? maxBackoff : next;
    });
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
  }
}
