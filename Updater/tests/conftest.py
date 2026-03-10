import json
from pathlib import Path
import sys

import pytest


FIXTURES_DIR = Path(__file__).parent / "fixtures" / "ingest"
PROJECT_ROOT = Path(__file__).resolve().parents[1]

if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


@pytest.fixture
def fixture_payload(request):
    fixture_name = request.param
    fixture_path = FIXTURES_DIR / fixture_name
    with fixture_path.open("r", encoding="utf-8") as fixture_file:
        return json.load(fixture_file)
