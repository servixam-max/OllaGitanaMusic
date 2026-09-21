#!/usr/bin/env python3
"""
Sincroniza el número de versión en todos los puntos del proyecto:

- mobile/pubspec.yaml          (version: X.Y.Z+build)
- backend/app/core/config.py   (VERSION)
- backend/web/version.txt      (se regenera en cada release)

Uso:
    python3 scripts/sync_version.py 1.2.0
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def sync(version: str) -> None:
    parts = version.lstrip("v").split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        raise SystemExit(f"Versión inválida '{version}'. Formato esperado: X.Y.Z")

    # 1. pubspec.yaml (incrementa el build number automáticamente)
    pubspec = ROOT / "mobile" / "pubspec.yaml"
    content = pubspec.read_text()
    match = re.search(r"^version:\s*([\d.]+)\+(\d+)\s*$", content, re.MULTILINE)
    if not match:
        raise SystemExit("No se encontró 'version:' en mobile/pubspec.yaml")
    new_build = int(match.group(2)) + 1
    content = re.sub(
        r"^version:\s*[\d.]+\+\d+\s*$",
        f"version: {version}+{new_build}",
        content,
        flags=re.MULTILINE,
    )
    pubspec.write_text(content)
    print(f"mobile/pubspec.yaml -> {version}+{new_build}")

    # 2. backend config
    config = ROOT / "backend" / "app" / "core" / "config.py"
    content = config.read_text()
    content = re.sub(r'VERSION:\s*str\s*=\s*"[^"]*"', f'VERSION: str = "{version}"', content)
    config.write_text(content)
    print(f"backend/app/core/config.py -> {version}")

    # 3. version.txt de la PWA
    version_file = ROOT / "backend" / "web" / "version.txt"
    version_file.write_text(f"v{version}\n")
    print(f"backend/web/version.txt -> v{version}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    sync(sys.argv[1])
