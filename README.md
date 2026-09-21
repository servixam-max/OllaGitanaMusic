# 🎸 Olla Gitana Music

Repositorio oficial en GitHub: **[github.com/servixam-max/OllaGitanaMusic](https://github.com/servixam-max/OllaGitanaMusic)**

Aplicación móvil integral para Android (APK) y Backend autoalojado en Docker para el grupo musical **Olla Gitana**. Diseñada específicamente para ensayos en directo, gestión de repertorio democrático, separación de instrumentos y consulta de letras y acordes en escenarios.

---

## 🆕 Novedades v1.1.0

- **Presets de separación de calidad**: Rápida, Equilibrada, Máxima (WAV 24-bit), 6 pistas, Híbrida (recomendada) y **Karaoke**.
- **Modo Híbrido**: voz/batería/bajo/otros con `htdemucs_ft` (máxima definición) + guitarra/piano de `htdemucs_6s`.
- **Cola de separación con worker único**: una tarea a la vez, posición en cola visible, reintento reutilizando lo ya procesado.
- **Recuperación tras reinicio**: las tareas interrumpidas se marcan y se pueden reintentar desde la app.
- **Sincronía de precisión**: salida WAV 24-bit opcional, ajuste fino por pista (nudge ±500 ms) y bucle A-B gapless.
- **Caché local de pistas**: ensayo sin cortes y sin conexión tras la primera carga.
- **Letras en modo Karaoke**: resaltado de la línea actual por timestamps LRC + caché offline.
- **Detector de acordes real**: detección de beats, plantillas con 7ª/sus/dim, suavizado Viterbi y tonalidad Krumhansl-Kessler.
- **Seguridad**: token de API para escrituras, límite de subida (600 MB), comprobación de espacio en disco, keystore fuera de git.
- **Wakelock**: la pantalla no se apaga durante la reproducción en ensayo.
- **WebSockets con reconexión automática** y backoff exponencial (repertorio y progreso de stems).

---

## 🏗️ Arquitectura General

```
OllaGitanaMusic/
├── docker-compose.yml          # Orquestación de servicios y volúmenes Docker
├── scripts/sync_version.py     # Sincroniza la versión en pubspec/config/version.txt
├── backend/                    # Servidor FastAPI (Python 3.11)
│   ├── app/
│   │   ├── api/v1/             # Endpoints REST (lyrics, stems, chords, repertoire, events, members) y WebSockets
│   │   ├── core/               # Configuración, DB SQLite asíncrona (SQLAlchemy), seguridad por token
│   │   ├── models/             # Modelos ORM (SongProposal, SongVote, StemTask, BandEvent...)
│   │   ├── services/           # Demucs, cola de stems, Librosa, LRCLIB, Deezer/iTunes, WebSocketManager
│   │   └── main.py             # App FastAPI y streaming estático HTTP 206
│   ├── data/                   # Volumen persistente de audios, stems, previews y DB SQLite
│   ├── tests/                  # Tests de API (pytest)
│   ├── Dockerfile              # Imagen Docker con PyTorch, Demucs y FFmpeg
│   └── requirements.txt        # Dependencias de Python
└── mobile/                     # Frontend Móvil en Flutter (Android + Web PWA para iOS)
    ├── android/                # Configuración nativa, permisos de audio y almacenamiento
    ├── lib/
    │   ├── core/
    │   │   ├── audio/          # MultitrackPlayer (just_audio, nudge, loop A-B) y StemCache offline
    │   │   ├── network/        # Cliente HTTP (Dio), token y WebSocket con reconexión
    │   │   ├── theme/          # Tema Stage Dark de alto contraste
    │   │   ├── updater/        # Comprobación de actualizaciones desde GitHub Releases
    │   │   └── widgets/        # Selector de músico y menú de perfil
    │   ├── features/
    │   │   ├── lyrics/         # Módulo 1: Letras (LRCLIB) con modo Karaoke y caché offline
    │   │   ├── stems_mixer/    # Módulo 2: Mezclador multipista (presets, karaoke, nudge)
    │   │   ├── chords/         # Módulo 3: Acordes (Songsterr y detector armónico real)
    │   │   ├── repertoire/     # Módulo 4: Sala colaborativa (búsqueda, votación 1-5★)
    │   │   ├── events/         # Módulo 5: Eventos, bolos y setlists
    │   │   └── settings/       # Configuración de servidor, token, caché y actualizaciones
    │   └── main.dart           # Navegación principal por pestañas
    ├── Dockerfile              # Dockerfile para compilar el APK sin instalar Flutter en el host
    └── pubspec.yaml            # Dependencias de Flutter
```

---

## 🚀 1. Puesta en Marcha del Backend

### Opción A: Con Docker & Docker Compose (Recomendado para servidor)

1. Abre una terminal en la raíz del proyecto `OllaGitanaMusic/`:
   ```bash
   docker compose up --build
   ```
2. El servidor FastAPI se iniciará en `http://localhost:8005` (mapeado al 8000 interno).
   - **Documentación Swagger interactiva:** `http://localhost:8005/docs`
   - **Salud del servidor:** `http://localhost:8005/`

> ⚠️ **Docker usa CPU**: la separación con Demucs es mucho más rápida ejecutándola de forma nativa en un Mac con Apple Silicon (aprovecha la GPU Metal/MPS).

### Opción B: Ejecución Local en Mac (Recomendado para máxima calidad/velocidad)

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

En Apple Silicon se detecta y usa **MPS** automáticamente.

### Variables de entorno (`backend/.env`)

| Variable | Descripción |
|---|---|
| `API_TOKEN` | Token compartido para escrituras. Vacío en red local; **obligatorio si expones por túnel**. |
| `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET` | Opcionales. Sin ellos se usan Deezer/iTunes automáticamente. |
| `DATA_DIR` | Carpeta de datos (por defecto `./data`). |

---

## 📱 2. Compilación del APK para Android

### Opción A: Con Flutter instalado (requiere JDK 17)

```bash
cd mobile
flutter pub get
VERSION=$(grep -E '^version:' pubspec.yaml | sed -E 's/version: ([0-9.]+).*/\1/')
flutter build apk --release --dart-define=APP_VERSION=v$VERSION
```

El APK se genera en `mobile/build/app/outputs/flutter-apk/app-release.apk`.

### Opción B: Compilación mediante Docker (sin instalar Flutter)

```bash
mkdir -p output
docker build -t olla-gitana-apk mobile/
docker run --rm -v "$(pwd)/output:/output" olla-gitana-apk
```

### Firma de release

El APK de release se firma con `mobile/android/app/olla-gitana-key.jks` + `mobile/android/key.properties` (ambos **fuera de git**). En GitHub Actions se inyectan desde los secrets:

| Secret | Contenido |
|---|---|
| `KEYSTORE_BASE64` | `base64 -i olla-gitana-key.jks \| pbcopy` |
| `KEYSTORE_PASSWORD` | Contraseña del store |
| `KEY_PASSWORD` | Contraseña de la clave |
| `KEY_ALIAS` | Alias (`ollagitana`) |

Si no hay secrets configurados, el CI firma con la clave de debug (funcional pero no actualizable sobre una instalación previa).

### Publicar una versión nueva

```bash
python3 scripts/sync_version.py 1.2.0   # actualiza pubspec, config.py y version.txt
git commit -am "v1.2.0: ..."
git tag v1.2.0
git push origin main --tags              # dispara CI: tests + APK + PWA + Release
```

---

## 🎛️ 3. Conexión de la App al Servidor en Ensayo

1. **En la misma red Wi-Fi del local de ensayo:**
   - Averigua la IP local de tu Mac (`ipconfig getifaddr en0`, p. ej. `192.168.1.45`).
   - En la App: **avatar (arriba a la derecha) → Ajustes y servidor**, introduce `http://192.168.1.45:8000`.
   - Pulsa **"Probar Conexión"** y luego **"Guardar"**.
   - Si el servidor tiene `API_TOKEN`, escríbelo en el campo **Token de seguridad**.
2. **Fuera del local (Remoto / Internet):**
   - Usa **Tailscale Funnel** o **Cloudflare Tunnel**. Con túnel, configura siempre `API_TOKEN`.

> La app **cachea las pistas en el teléfono**: tras la primera carga puedes ensayar sin conexión y sin cortes.

---

## 📋 4. Guía de Uso de los Módulos

### 🎚️ Módulo 1: Mezclador Multipista (Demucs)

Al subir una canción eliges la **calidad de separación**:

| Preset | Pistas | Velocidad | Uso recomendado |
|---|---|---|---|
| **Rápida** | 4 | ⚡⚡⚡ | Ensayar ya mismo |
| **Equilibrada** | 4 | ⚡⚡ | Voz/batería/bajo/otros de alta calidad |
| **Máxima** | 4 (WAV 24-bit) | ⚡ | Loops y búsquedas con precisión de muestra |
| **6 pistas** | 6 | ⚡⚡ | Incluye guitarra y piano |
| **Híbrida** ⭐ | 6 | ⚡ | Máxima calidad global (ft + 6s) |
| **Karaoke** | 2 | ⚡⚡ | Solo voz e instrumental |

- **Cola**: las separaciones se ejecutan de una en una para no degradar la calidad; verás tu posición en cola.
- **M / S**: silencia o aísla un instrumento al instante.
- **Nudge (Sincronía)**: corrige desfases de milisegundos por pista con el slider inferior.
- **Bucle A-B**: fija [A] y [B] para repetir un pasaje sin cortes (con caché local es gapless).
- **Velocidad**: 0.75x a 1.25x preservando el tono.
- **Wakelock**: durante la reproducción, la pantalla permanece encendida.

### 🎤 Módulo 2: Letras en Directo (LRCLIB + Karaoke)

- Búsqueda por título o artista con resultados que indican si tienen letra sincronizada (icono 🎤).
- **Modo Karaoke**: resalta automáticamente la línea que toca y hace scroll sola.
- **A- / A+**: ajusta el tamaño de letra al instante.
- **Auto-scroll manual**: para letras sin sincronizar, con velocidad regulable de 0.5x a 4.0x.
- **Letras guardadas**: las canciones que usas quedan disponibles sin conexión.

### 🎸 Módulo 3: Acordes & Tonalidad

- **Buscador de Cifrados**: tablaturas y acordes de Songsterr, con transporte (cejilla) y acordes de referencia.
- **Detector Armónico de Audio**: análisis real con `librosa`:
  - Detección de **beats** para segmentar acordes con precisión rítmica.
  - Plantillas de acordes con **7ª dominante, 7ª mayor, 7ª menor, sus4 y disminuidos**.
  - Suavizado **Viterbi** para una progresión estable y legible.
  - **Tonalidad** por perfiles Krumhansl-Kessler y **tempo (BPM)**.
  - Reproductor sincronizado: toca cualquier segmento para saltar a ese punto.
  - Si el análisis falla, la app muestra el **error real** (nunca resultados simulados).

### 🗳️ Módulo 4: Sala de Ensayo Colaborativa & Votación

- Busca canciones (Deezer/iTunes/Spotify) con carátula HD y preview de 30 s.
- Cualquier miembro propone temas y puntúa de 1 a 5 estrellas; el orden refleja el consenso.
- Se muestran **los votos de cada músico** (el tuyo resaltado en dorado).
- Estados: 🟡 Propuesta · 🔵 Para Ensayar · 🟢 En Repertorio · ⚪ Descartada.
- **Sincronización en vivo** por WebSocket con reconexión automática y aviso si se pierde.
- Comparte el repertorio completo por WhatsApp con un toque.

### 🎉 Módulo 5: Eventos, Bolos & Setlists

- Crea eventos con fecha, lugar, notas y **setlist** elegido del repertorio.
- Ordenados por **fecha de celebración** (próximos primero).
- Exporta a **Google Calendar** o comparte por **WhatsApp** con formato elegante en español.

### ⚙️ Ajustes (menú del avatar)

- URL del backend, **token de seguridad** y músico activo.
- Comprobación de actualizaciones desde GitHub Releases.
- **Almacenamiento de ensayo**: consulta y libera el espacio de las pistas cacheadas.

---

## 🧪 Tests

```bash
cd backend
.venv/bin/python -m pytest tests/ -q
```

El CI ejecuta los tests del backend y `flutter analyze` antes de compilar el APK y la PWA.
