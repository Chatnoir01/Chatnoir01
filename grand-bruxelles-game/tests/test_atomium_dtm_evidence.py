#!/usr/bin/env python3
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DTM = ROOT / "data" / "terrain" / "laeken_jette" / "atomium_dtm.game.json"
EVIDENCE = ROOT / "data" / "qa" / "photo_match" / "atomium_dtm_evidence.json"


def main() -> int:
    dtm = json.loads(DTM.read_text(encoding="utf-8"))
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))

    assert dtm["schema"] == 2
    assert dtm["format"] == "grand-bruxelles-dtm-grid-v2"
    assert dtm["source"] == "Paradigm UrbIS Digital Terrain Model 2021"
    assert dtm["source_crs"] == "EPSG:31370"
    assert dtm["source_sha256"] == "b689d20567223125aea2a8fb9c720a79c42be20ca5e5e7167080a39df2fd107f"
    assert dtm["width"] == 257 and dtm["height"] == 257
    assert len(dtm["relative_heights_m"]) == 257 * 257
    assert dtm["valid_sample_count"] + dtm["invalid_sample_count"] == 257 * 257

    atomium = dtm["atomium_reference"]
    assert math.isclose(atomium["absolute_elevation_m"], 52.57776641845703, abs_tol=1e-9)
    assert math.isclose(dtm["absolute_elevation_min_m"], 46.17759704589844, abs_tol=1e-9)
    assert math.isclose(dtm["absolute_elevation_max_m"], 76.80229187011719, abs_tol=1e-9)
    assert dtm["absolute_elevation_min_m"] < atomium["absolute_elevation_m"] < dtm["absolute_elevation_max_m"]
    assert math.isclose(dtm["relative_height_min_m"], -6.4002, abs_tol=1e-4)
    assert math.isclose(dtm["relative_height_max_m"], 24.2245, abs_tol=1e-4)

    assert evidence["source_git_blob_sha"] == "929df36d09a1e62a76fa6b3ca7071c39e348bca2"
    assert evidence["official_raster"]["source_sha256"] == dtm["source_sha256"]
    assert evidence["official_raster"]["crs"] == dtm["source_crs"]
    assert evidence["locked_grid"]["width"] == dtm["width"]
    assert evidence["locked_grid"]["height"] == dtm["height"]
    assert evidence["runtime_approved"] is False
    assert evidence["realism_complete"] is False

    print("ATOMIUM_DTM_EVIDENCE_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
