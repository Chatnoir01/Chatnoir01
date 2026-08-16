#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "grand-bruxelles-autonomous-citygen.yml"
EXPECTED_REGION_GATES = (
    "source_requirements",
    "crs",
    "runtime_geometry",
    "collisions",
    "streaming",
    "terrain",
    "heights",
    "materials",
    "facade",
    "clutter",
    "mobility",
    "verification",
    "license",
    "region_scalable",
    "photo_match",
    "performance",
)

SPEC = importlib.util.spec_from_file_location("bootstrap_cell_maturity", HERE / "bootstrap_cell_maturity.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    cell = root / "bxl-e149000-n169000-s500"
    feature = {
        "type": "Feature",
        "properties": {"INSPIRE_ID": "BE.TEST.1"},
        "geometry": {"type": "Polygon", "coordinates": [[[149050,169050],[149100,169050],[149100,169100],[149050,169100],[149050,169050]]]},
    }
    source = {
        "format": "grand-bruxelles-urbis-source-cell-v1",
        "cell_id": cell.name,
        "crs": "EPSG:31370",
        "bbox": [149000,169000,149500,169500],
        "layers": {
            "buildings": {
                "features": 1,
                "invalid_ownership_features": 0,
                "file": "raw/buildings.geojson",
            }
        },
    }
    buildings = {"type": "FeatureCollection", "features": [feature]}
    write(cell / "manifest.json", source)
    write(cell / "raw" / "buildings.geojson", buildings)

    result = mod.build(cell)
    assert result["format"] == "grand-bruxelles-cell-maturity-v1"
    assert result["cell_id"] == cell.name
    assert result["crs"] == "EPSG:31370"
    assert result["maturity"]["state"] == "data_ready"
    assert result["geometry"]["authoritative_geometry_ready"] is True
    assert result["geometry"]["building_feature_count"] == 1
    assert tuple(mod.GATES) == EXPECTED_REGION_GATES, mod.GATES
    assert tuple(result["maturity"]["gates"]) == EXPECTED_REGION_GATES
    assert result["maturity"]["gates"]["source_requirements"] is True
    assert result["maturity"]["gates"]["crs"] is True
    assert all(
        value is False
        for gate, value in result["maturity"]["gates"].items()
        if gate not in {"source_requirements", "crs"}
    )
    assert result["crs_evidence"]["status"] == "validated"
    assert result["crs_evidence"]["source_crs"] == "EPSG:31370"
    assert result["crs_evidence"]["bbox"] == [149000,169000,149500,169500]
    assert result["crs_evidence"]["gate_ready"] is True
    assert result["source_requirements"]["status"] == "validated"
    assert result["source_requirements"]["complete"] is True
    assert result["source_requirements"]["required_file_count"] == 1
    assert result["source_requirements"]["blockers"] == []
    requirement = result["source_requirements"]["requirements"][0]
    assert requirement["layer"] == "buildings"
    assert requirement["file"] == "raw/buildings.geojson"
    assert requirement["status"] == "validated"
    assert requirement["declared_features"] == 1
    assert requirement["actual_features"] == 1
    assert requirement["content_digest"] == mod._digest(buildings)
    assert result["terrain"]["status"] == "evidence_pending"
    assert result["heights"]["status"] == "evidence_pending"
    assert result["photo_match"]["status"] == "not_evaluated"
    assert result["performance"]["budget_pass"] is False
    assert result["maturity_digest"] == mod._digest({k: v for k, v in result.items() if k != "maturity_digest"})

    # Every explicitly declared source file participates in the same contract.
    # A missing secondary source keeps only the source gate fail-closed; CRS proof
    # remains independently validated from the source manifest contract.
    source["layers"]["street_axes"] = {"features": 0, "file": "raw/street_axes.geojson"}
    write(cell / "manifest.json", source)
    pending = mod.build(cell)
    assert pending["maturity"]["state"] == "data_ready"
    assert pending["maturity"]["gates"]["source_requirements"] is False
    assert pending["maturity"]["gates"]["crs"] is True
    assert pending["source_requirements"]["status"] == "evidence_pending"
    assert pending["source_requirements"]["complete"] is False
    assert "missing_declared_source_file:street_axes:raw/street_axes.geojson" in pending["source_requirements"]["blockers"]
    del source["layers"]["street_axes"]

    # Invalid canonical ownership must never be promoted as authoritative geometry.
    # CRS evidence is still true because it describes coordinates, not geometry quality.
    source["layers"]["buildings"]["invalid_ownership_features"] = 1
    write(cell / "manifest.json", source)
    quarantined = mod.build(cell)
    assert quarantined["maturity"]["state"] == "quarantine"
    assert quarantined["geometry"]["authoritative_geometry_ready"] is False
    assert quarantined["maturity"]["gates"]["source_requirements"] is False
    assert quarantined["maturity"]["gates"]["crs"] is True
    assert all(
        value is False
        for gate, value in quarantined["maturity"]["gates"].items()
        if gate not in {"crs"}
    )

    # Manifest/source disagreement fails closed instead of silently changing counts.
    source["layers"]["buildings"]["invalid_ownership_features"] = 0
    source["layers"]["buildings"]["features"] = 2
    write(cell / "manifest.json", source)
    try:
        mod.build(cell)
    except ValueError as exc:
        assert "feature count mismatch" in str(exc)
    else:
        raise AssertionError("source count mismatch must fail closed")

workflow_text = WORKFLOW.read_text(encoding="utf-8")
assert "python3 grand-bruxelles-game/tools/citygen/test_bootstrap_cell_maturity.py" in workflow_text, (
    "Autonomous CityGen CI must execute the canonical maturity-contract regression"
)

print("BOOTSTRAP_CELL_MATURITY_GUARDRAILS_OK deterministic=true source_requirements=true crs=true quarantine=true regional_contract_locked=true ci_covered=true")
