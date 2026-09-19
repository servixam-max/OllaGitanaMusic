# Dockerfile para compilar el APK de Android de Olla Gitana sin necesidad de instalar Flutter localmente
FROM ghcr.io/cirruslabs/flutter:3.24.0

WORKDIR /app

# Copiar configuración de dependencias
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

# Copiar el código fuente completo
COPY . .

# Compilar APK en modo release
RUN flutter build apk --release --split-per-abi=false

# El APK resultante se genera en /app/build/app/outputs/flutter-apk/app-release.apk
CMD ["cp", "/app/build/app/outputs/flutter-apk/app-release.apk", "/output/olla_gitana_app.apk"]
