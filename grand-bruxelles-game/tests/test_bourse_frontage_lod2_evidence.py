#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "qa" / "bourse_frontage_lod2_evidence.json"


def main() -> int:
    data = json.loads(DATA.read_text(encoding="utf-8"))
    assert data["schema"] == "grand-bruxelles-bourse-frontage-lod2-evidence-v1"
    assert data["source"]["crs"] == "EPSG:31370"
    assert data["source"]["license"] == "CC0-1.0"
    assert data["source"]["package_sha256"] == "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
    assert data["runtime_approved"] is False
    rows = data["candidates"]
    assert len(rows) == 7
    assert sum(row["faces"] for row in rows) == 181
    assert sum(row["triangles"] for row in rows) == 534
    assert all(20.0 < row["height_m"] < 30.0 for row in rows)
    assert sum(row["solid_count"] for row in rows) == 11
    assert sum(1 for row in rows if row["solid_count"] > 1) == 4
    assert data["wfs_buildings_without_matching_3d_solids"] == ["https://databrussels.be/id/building/1645724"]
    assert len({row["building_id"] for row in rows}) == 7
    print("BOURSE_FRONTAGE_LOD2_EVIDENCE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
