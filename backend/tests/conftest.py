"""
Configuración de tests: aísla las pruebas en una base de datos temporal.

IMPORTANTE: sin esto, los tests escriben en la base de datos real de la banda
(data/olla_gitana.db) y dejan eventos o canciones de ejemplo visibles en la app.
"""
import os
import tempfile
from pathlib import Path

# Debe configurarse ANTES de importar la app para que use la BD de test
_TEST_DB_DIR = Path(tempfile.mkdtemp(prefix="olla_gitana_tests_"))
_TEST_DB_PATH = _TEST_DB_DIR / "test_olla_gitana.db"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{_TEST_DB_PATH}"
os.environ["DATA_DIR"] = str(_TEST_DB_DIR / "data")
