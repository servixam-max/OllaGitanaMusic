# 🎸 Olla Gitana Music

Aplicación móvil integral para Android (APK) y Backend autoalojado en Docker para el grupo musical **Olla Gitana**. Diseñada específicamente para ensayos en directo, gestión de repertorio democrático, separación de instrumentos y consulta de letras y acordes en escenarios.

---

## 🏗️ Arquitectura General

```
OllaGitanaMusic/
├── docker-compose.yml          # Orquestación de servicios y volúmenes Docker
├── backend/                    # Servidor FastAPI (Python 3.11)
│   ├── app/
│   │   ├── api/v1/             # Endpoints REST (lyrics, stems, chords, repertoire) y WebSockets
│   │   ├── core/               # Configuración, DB SQLite asíncrona (SQLAlchemy)
│   │   ├── models/             # Modelos ORM (SongProposal, SongVote, StemTask)
│   │   ├── services/           # Demucs, Librosa, LRCLIB, Spotify, WebSocketManager
│   │   └── main.py             # App FastAPI y streaming estático HTTP 206
│   ├── data/                   # Volumen persistente de audios, stems y DB SQLite
│   ├── Dockerfile              # Imagen Docker con PyTorch, Demucs y FFmpeg
│   └── requirements.txt        # Dependencias de Python
└── mobile/                     # Frontend Móvil en Flutter (Android)
    ├── android/                # Configuración nativa, permisos de audio y almacenamiento
    ├── lib/
    │   ├── core/
    │   │   ├── audio/          # MultitrackPlayer (sincronizador just_audio con Solo/Mute)
    │   │   ├── network/        # Cliente HTTP (Dio) y WebSocket
    │   │   └── theme/          # Tema Stage Dark de alto contraste
    │   ├── features/
    │   │   ├── lyrics/         # Módulo 1: Letras (LRCLIB) con auto-scroll y font-size
    │   │   ├── stems_mixer/    # Módulo 2: Mezclador de stems multipista con Demucs
    │   │   ├── chords/         # Módulo 3: Acordes (Songsterr y análisis de audio librosa)
    │   │   ├── repertoire/     # Módulo 4: Sala colaborativa (Spotify + Votación 1-5 estrellas)
    │   │   └── settings/       # Configuración de IP del servidor y nombre del músico
    │   └── main.dart           # Navegación principal por pestañas
    ├── Dockerfile              # Dockerfile para compilar el APK sin instalar Flutter en el host
    └── pubspec.yaml            # Dependencias de Flutter
```

---

## 🚀 1. Puesta en Marcha del Backend

### Opción A: Con Docker & Docker Compose (Recomendado para Producción/Servidor Mac)

1. Abre una terminal en la raíz del proyecto `OllaGitanaMusic/`:
   ```bash
   docker compose up --build
   ```
2. El servidor FastAPI se iniciará en `http://localhost:8000`.
   - **Documentación Swagger interactiva:** `http://localhost:8000/docs`
   - **Salud del servidor:** `http://localhost:8000/`

### Opción B: Ejecución Local en Mac (Desarrollo Rápido)

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

---

## 📱 2. Compilación del APK para Android

### Opción A: Con Flutter instalado en tu Mac/PC

1. Entra en la carpeta `mobile`:
   ```bash
   cd mobile
   flutter pub get
   ```
2. Compila el archivo APK listo para instalar en los teléfonos Android del grupo:
   ```bash
   flutter build apk --release
   ```
3. El archivo APK se generará en:
   `mobile/build/app/outputs/flutter-apk/app-release.apk`
4. Pasa este archivo por WhatsApp, Drive o cable USB a los teléfonos de los miembros de **Olla Gitana** e instálalo activando "Orígenes desconocidos".

### Opción B: Compilación mediante Docker (Sin necesidad de instalar Flutter)

Si no tienes Flutter o Android Studio configurado en tu máquina, puedes compilar el APK dentro de un contenedor Docker:
```bash
mkdir -p output
docker build -t olla-gitana-apk mobile/
docker run --rm -v "$(pwd)/output:/output" olla-gitana-apk
```
El archivo `olla_gitana_app.apk` se guardará directamente en la carpeta `output/`.

---

## 🎛️ 3. Conexión de la App al Servidor en Ensayo

Para que los integrantes se conecten al servidor de su Mac desde sus teléfonos:

1. **En la misma red Wi-Fi del local de ensayo:**
   - Averigua la IP local de tu Mac (ejecuta `ipconfig getifaddr en0` en la terminal de tu Mac, por ejemplo `192.168.1.45`).
   - En la App móvil, ve a la pestaña **Ajustes** e introduce:
     `http://192.168.1.45:8000`
   - Pulsa **"Probar Conexión"** y luego **"Guardar"**.
2. **Fuera del local (Remoto / Internet):**
   - Puedes usar **Cloudflare Tunnel** (`cloudflared tunnel --url http://localhost:8000`) o **Tailscale** para obtener una URL segura sin abrir puertos en el router.

---

## 📋 4. Guía de Uso de los Módulos

### 🎤 Módulo 1: Letras en Directo (LRCLIB)
- Busca cualquier tema por título o artista.
- La letra se muestra en tipografía nítida y limpia con fondo negro para no deslumbrar en el escenario.
- **Botones A- / A+:** Ajusta el tamaño de la letra al instante.
- **Auto-scroll:** Pulsa el botón de reproducción para que la letra se desplace sola mientras tocas tu instrumento, con velocidad regulable de 0.5x a 4.0x.

### 🎚️ Módulo 2: Mezclador Multipista de Stems (Demucs)
- Pulsa el botón superior para subir un tema (MP3 o WAV).
- El backend ejecuta **Demucs** en segundo plano, aislando:
  - **Voz** (Vocals)
  - **Batería / Percusión** (Drums)
  - **Bajo** (Bass)
  - **Guitarras / Otros** (Other)
- Sigue el progreso en tiempo real mediante WebSocket (0% a 100%).
- En la consola de mezcla:
  - Sliders de volumen independientes para cada stem.
  - Botón **M (Mute):** Silencia un instrumento específico (ideal para tocar tú esa parte).
  - Botón **S (Solo):** Escucha únicamente un instrumento aislado para aprenderte el punteo o la rítmica.

### 🎸 Módulo 3: Acordes & Tonalidad
- **Buscador de Cifrados:** Consulta tablaturas y acordes sincronizados con la API de Songsterr.
- **Detector Armónico de Audio:** Sube cualquier grabación o ensayo; la librería `librosa` analiza los cromagramas para predecir la tonalidad dominante (ej: *Am*, *G*, *Dm*) y una línea temporal de acordes con inicio, fin y nivel de confianza.

### 🗳️ Módulo 4: Sala de Ensayo Colaborativa & Votación
- Busca canciones en **Spotify**: importa automáticamente la carátula oficial en alta definición y el **snippet de audio de 30 segundos** para escucharla con un botón de Play directo.
- Cualquier miembro del grupo puede proponer un tema.
- **Votación democrática:** Cada integrante puntúa de 1 a 5 estrellas. La lista se ordena automáticamente por consenso.
- **Estados del tema:** Filtra y cambia el estado de cada canción entre:
  - 🟡 *Propuesta*
  - 🔵 *Para Ensayar*
  - 🟢 *En Repertorio*
  - ⚪ *Descartada*
