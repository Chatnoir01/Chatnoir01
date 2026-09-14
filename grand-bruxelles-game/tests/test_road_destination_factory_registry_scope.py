from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools/city_machine"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from validate_road_destination_factory_registry import validate_registry_scope_baseline

REGISTRY = ROOT / "data/source_plans/brussels_missing_road_source_registry.json"
VALIDATOR = TOOLS / "validate_road_destination_factory_registry.py"


def load_registry():
    return json.loads(REGISTRY.read_text(encoding="utf-8"))


def test_live_registry_scope_baseline_is_green():
    validate_registry_scope_baseline(load_registry())


def test_schema_drift_fails_closed():
    registry = load_registry()
    registry["schema"] = "grand-bruxelles-missing-road-source-registry-v2"
    with pytest.raises(SystemExit, match="registry schema drift"):
        validate_registry_scope_baseline(registry)


def test_scope_drift_fails_closed():
    registry = load_registry()
    registry["scope"] = "Brussels playable corridor only"
    with pytest.raises(SystemExit, match="registry scope drift"):
        validate_registry_scope_baseline(registry)


def test_source_provenance_drift_fails_closed():
    registry = load_registry()
    registry["source"]["license"] = "UNKNOWN"
    with pytest.raises(SystemExit, match="registry source contract drift"):
        validate_registry_scope_baseline(registry)


def test_source_endpoint_drift_fails_closed():
    registry = load_registry()
    registry["source"]["endpoint"] = "https://example.invalid/overpass"
    with pytest.raises(SystemExit, match="registry source contract drift"):
        validate_registry_scope_baseline(registry)


def test_game_frame_drift_fails_closed():
    registry = load_registry()
    registry["game_frame"]["axes"] = "X=east, Y=up, Z=north"
    with pytest.raises(SystemExit, match="registry game frame drift"):
        validate_registry_scope_baseline(registry)


def test_baseline_schema_drift_fails_closed():
    registry = load_registry()
    registry["evidence_baseline"]["runtime_ready"] = True
    with pytest.raises(SystemExit, match="evidence baseline schema drift"):
        validate_registry_scope_baseline(registry)


def test_baseline_partition_drift_fails_closed():
    registry = load_registry()
    moved = registry["evidence_baseline"]["missing_niscodes"].pop()
    registry["evidence_baseline"]["registered_niscodes"].append(moved)
    with pytest.raises(SystemExit, match="evidence baseline partition drift"):
        validate_registry_scope_baseline(registry)


def test_missing_baseline_must_exactly_match_registry_municipalities():
    registry = load_registry()
    registry["evidence_baseline"]["missing_niscodes"].pop()
    with pytest.raises(SystemExit, match="evidence baseline partition drift"):
        validate_registry_scope_baseline(registry)


def test_registered_baseline_order_drift_fails_closed():
    registry = load_registry()
    registry["evidence_baseline"]["registered_niscodes"] = list(
        reversed(registry["evidence_baseline"]["registered_niscodes"])
    )
    with pytest.raises(SystemExit, match="evidence baseline order drift"):
        validate_registry_scope_baseline(registry)


def test_missing_baseline_order_must_match_registry_municipality_order():
    registry = load_registry()
    registry["evidence_baseline"]["missing_niscodes"] = list(
        reversed(registry["evidence_baseline"]["missing_niscodes"])
    )
    with pytest.raises(SystemExit, match="evidence baseline order drift"):
        validate_registry_scope_baseline(registry)


def test_registry_root_schema_drift_fails_closed():
    registry = load_registry()
    registry["runtime_ready"] = True
    with pytest.raises(SystemExit, match="registry root schema drift"):
        validate_registry_scope_baseline(registry)


def test_registry_opened_downstream_authorization_fails_closed():
    registry = load_registry()
    registry["authorization"]["render_authorized"] = True
    with pytest.raises(SystemExit, match="registry downstream authorization opened"):
        validate_registry_scope_baseline(registry)


def test_municipality_row_schema_drift_fails_closed():
    registry = load_registry()
    registry["municipalities"][0]["runtime_ready"] = True
    with pytest.raises(SystemExit, match="municipality identity drift"):
        validate_registry_scope_baseline(registry)


def test_municipality_osm_relation_identity_drift_fails_closed():
    registry = load_registry()
    registry["municipalities"][0]["osm_relation_id"] = 999999999
    with pytest.raises(SystemExit, match="municipality identity drift"):
        validate_registry_scope_baseline(registry)


def test_registry_validator_rejects_duplicate_json_object_keys(tmp_path: Path):
    text = REGISTRY.read_text(encoding="utf-8")
    needle = '"scope": "Brussels-Capital Region"'
    assert needle in text
    duplicate = text.replace(
        needle,
        '"scope": "invalid shadow scope",\n  "scope": "Brussels-Capital Region"',
        1,
    )
    candidate = tmp_path / "duplicate-key-registry.json"
    candidate.write_text(duplicate, encoding="utf-8")

    result = subprocess.run(
        [sys.executable, str(VALIDATOR), "--registry", str(candidate)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "duplicate JSON object key scope" in (result.stdout + result.stderr)
