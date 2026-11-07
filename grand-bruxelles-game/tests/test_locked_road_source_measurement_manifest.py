from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json"
LOCK = ROOT / "data/source_plans/brussels_locked_road_source_measurements.lock.json"
BUILDER = ROOT / "tools/city_machine/build_locked_road_source_measurement_manifest.py"


def _load_builder():
    spec = importlib.util.spec_from_file_location("locked_road_source_measurements_builder", BUILDER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _git_blob_sha1(raw: bytes) -> str:
    return hashlib.sha1(f"blob {len(raw)}\0".encode("ascii") + raw).hexdigest()


def _mutated_evidence(tmp_path: Path, evidence: dict) -> tuple[Path, str]:
    raw = (json.dumps(evidence, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    mutated = tmp_path / "mutated-evidence.json"
    mutated.write_bytes(raw)
    return mutated, _git_blob_sha1(raw)


def test_locked_source_measurement_manifest_is_deterministic_and_fail_closed() -> None:
    assert BUILDER.is_file(), "locked road-source measurement builder is required"
    assert LOCK.is_file(), "locked road-source measurement manifest is required"
    with tempfile.TemporaryDirectory() as tmp:
        output = Path(tmp) / "measurements.json"
        result = subprocess.run(
            [sys.executable, str(BUILDER), "--evidence", str(EVIDENCE), "--output", str(output)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        assert result.returncode == 0, result.stderr or result.stdout
        assert output.read_bytes() == LOCK.read_bytes()

    payload = json.loads(LOCK.read_text(encoding="utf-8"))
    assert payload["schema"] == "grand-bruxelles-locked-road-source-measurements-v1"
    assert payload["accounting"] == {
        "expected_municipalities": 16,
        "locked_municipalities": 7,
        "unresolved_municipalities": 9,
        "road_identity_materialized": 0,
        "cell_assignment_materialized": 0,
    }
    assert len(payload["municipalities"]) == 7
    for row in payload["municipalities"]:
        assert row["source_file"] is None
        assert row["spatial_cell"] is None
        assert row["road_identity_status"] == "NOT_MATERIALIZED_FROM_SOURCE_ARTIFACT"
        assert row["cell_status"] == "NOT_ASSIGNED"
        assert row["registration_authorized"] is False
        assert row["render_authorized"] is False
        assert row["collision_authorized"] is False
        assert row["runtime_ready"] is False
        assert row["jouable"] is False


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("bounds_m", [10.0, 0.0, 0.0, 5.0]),
        ("bounds_m", [0.0, 0.0, 1.0]),
        ("bounds_m", [0.0, 0.0, "1", 1.0]),
        ("road_count", True),
        ("road_count", 0),
        ("point_count", -1),
    ],
)
def test_locked_source_measurement_builder_rejects_invalid_measurement_geometry(
    field: str, value: object, tmp_path: Path
) -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    evidence["successful_acquisitions"][0][field] = value
    mutated, digest = _mutated_evidence(tmp_path, evidence)

    builder = _load_builder()
    builder.EXPECTED_EVIDENCE_GIT_BLOB_SHA1 = digest
    with pytest.raises(SystemExit, match="measurement geometry drift"):
        builder.build(mutated)


@pytest.mark.parametrize(
    ("path", "value"),
    [
        (("id",), 123),
        (("name",), ""),
        (("osm_relation_id",), True),
        (("artifact", "name"), ""),
        (("artifact", "archive_sha256"), "xyz"),
    ],
)
def test_locked_source_measurement_builder_rejects_invalid_locked_metadata(
    path: tuple[str, ...], value: object, tmp_path: Path
) -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    target = evidence["successful_acquisitions"][0]
    if len(path) == 1:
        target[path[0]] = value
    else:
        target[path[0]][path[1]] = value
    mutated, digest = _mutated_evidence(tmp_path, evidence)

    builder = _load_builder()
    builder.EXPECTED_EVIDENCE_GIT_BLOB_SHA1 = digest
    with pytest.raises(SystemExit, match="locked metadata drift"):
        builder.build(mutated)


@pytest.mark.parametrize("niscode", ["", "2100X", "021002", "2102"])
def test_locked_source_measurement_builder_rejects_invalid_locked_niscode(
    niscode: str, tmp_path: Path
) -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    evidence["successful_acquisitions"][0]["niscode"] = niscode
    mutated, digest = _mutated_evidence(tmp_path, evidence)

    builder = _load_builder()
    builder.EXPECTED_EVIDENCE_GIT_BLOB_SHA1 = digest
    with pytest.raises(SystemExit, match="locked identity drift"):
        builder.build(mutated)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("niscode", ""),
        ("niscode", "2100X"),
        ("id", ""),
        ("name", ""),
        ("osm_relation_id", True),
        ("osm_relation_id", 0),
    ],
)
def test_locked_source_measurement_builder_rejects_invalid_unresolved_identity(
    field: str, value: object, tmp_path: Path
) -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    evidence["unresolved_acquisitions"][0][field] = value
    mutated, digest = _mutated_evidence(tmp_path, evidence)

    builder = _load_builder()
    builder.EXPECTED_EVIDENCE_GIT_BLOB_SHA1 = digest
    with pytest.raises(SystemExit, match="unresolved identity drift"):
        builder.build(mutated)


@pytest.mark.parametrize("field", ["id", "osm_relation_id"])
def test_locked_source_measurement_builder_rejects_duplicate_identity_within_locked_rows(
    field: str, tmp_path: Path
) -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    evidence["successful_acquisitions"][1][field] = evidence["successful_acquisitions"][0][field]
    mutated, digest = _mutated_evidence(tmp_path, evidence)

    builder = _load_builder()
    builder.EXPECTED_EVIDENCE_GIT_BLOB_SHA1 = digest
    with pytest.raises(SystemExit, match="identity collision"):
        builder.build(mutated)


@pytest.mark.parametrize("field", ["id", "osm_relation_id"])
def test_locked_source_measurement_builder_rejects_identity_alias_across_locked_and_unresolved_rows(
    field: str, tmp_path: Path
) -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    evidence["successful_acquisitions"][0][field] = evidence["unresolved_acquisitions"][0][field]
    mutated, digest = _mutated_evidence(tmp_path, evidence)

    builder = _load_builder()
    builder.EXPECTED_EVIDENCE_GIT_BLOB_SHA1 = digest
    with pytest.raises(SystemExit, match="identity collision"):
        builder.build(mutated)
