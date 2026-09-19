# Dockerfile para compilar el APK de Android de Olla Gitana
FROM --platform=linux/amd64 ghcr.io/cirruslabs/flutter:3.24.0

WORKDIR /app

# Pre-descargar artefactos de compilación para Android
RUN flutter precache --android

# Copiar configuración de dependencias
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

# Copiar el código fuente completo
COPY . .

# Compilar APK en modo release
RUN flutter build apk --release

# El APK resultante se copia a /output/olla_gitana_app.apk al ejecutar el contenedor
CMD ["cp", "/app/build/app/outputs/flutter-apk/app-release.apk", "/output/olla_gitana_app.apk"]
