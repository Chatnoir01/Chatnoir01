#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "urbis" / "bourse_street_surfaces.game.json"
EXPECTED_IDS = {
    "https://databrussels.be/id/streetsurface/22358",
    "https://databrussels.be/id/streetsurface/151495",
    "https://databrussels.be/id/streetsurface/152281",
}

payload = json.loads(DATA.read_text(encoding="utf-8"))
assert payload["schema"] == "grand-bruxelles-urbis-bourse-surfaces-v1"
assert payload["source"]["crs"] == "EPSG:31370"
assert payload["source"]["license"] == "CC0-1.0"
assert payload["source"]["request_bbox_epsg31370"] == [148440.23351135076, 170649.88213200308, 148800.23351135076, 171009.88213200308]
assert payload["world_coordinate_evidence"]["transform_source"] == "data/urbis/bourse_street_axes.game.json"
assert set(payload["target_inspire_ids"]) == EXPECTED_IDS
assert {surface["inspire_id"] for surface in payload["surfaces"]} == EXPECTED_IDS
assert [surface["type_uninterpreted"] for surface in payload["surfaces"]].count("SW") == 2
assert [surface["type_uninterpreted"] for surface in payload["surfaces"]].count("I") == 1
assert sum(float(surface["area_m2"]) for surface in payload["surfaces"]) == 459.0
assert all(len(surface["world_rings_xz"]) == 1 for surface in payload["surfaces"])
assert payload["runtime_approved"] is False
assert payload["realism_complete"] is False
assert payload["next_runtime_step"].startswith("acquire adjacent official street surfaces")
print("BOURSE_SURFACE_RUNTIME_DATA_OK")
