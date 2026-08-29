#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "data/qa/nord_source_target.json"
FETCHER = ROOT / "tools/fetch_urbis_nord.py"
VALIDATOR = ROOT / "tools/validate_nord_city_machine_data.py"
EXPECTED_BBOX = [149000.0, 172000.0, 150000.0, 172500.0]
EXPECTED_LAYERS = {
    "buildings": "urbisvector:Buildings",
    "street_surfaces": "urbisvector:StreetSurfaces",
    "street_axes": "urbisvector:StreetAxes",
    "tram_network": "urbisvector:TramNetwork",
    "train_network": "urbisvector:TrainNetwork",
}


def main() -> int:
    target = json.loads(TARGET.read_text(encoding="utf-8"))
    assert target["schema"] == "grand-bruxelles-nord-source-target-v1"
    assert target["zone_id"] == "nord"
    assert target["source_crs"] == "EPSG:31370"
    assert target["acquisition_bbox"] == EXPECTED_BBOX
    assert target["required_layers"] == EXPECTED_LAYERS
    assert target["output_root"] == "data/urbis/nord"
    assert target["promotion"] == "source_only_no_runtime_mutation"
    guards = target["guards"]
    assert guards["synthetic_station_geometry_forbidden"] is True
    assert guards["runtime_registration_before_source_validation_forbidden"] is True
    assert guards["jouable_promotion_before_visual_proof_forbidden"] is True
    assert guards["official_raw_and_game_pair_required"] is True

    fetch_text = FETCHER.read_text(encoding="utf-8")
    validator_text = VALIDATOR.read_text(encoding="utf-8")
    for layer in EXPECTED_LAYERS.values():
        assert layer in fetch_text
    assert "source_only_no_runtime_mutation" in fetch_text
    assert "No synthetic station geometry" in fetch_text
    assert "NORD_CITY_MACHINE_DATA_OK" in validator_text
    assert "REQUIRED_SLUGS" in validator_text
    print("NORD_SOURCE_CONTRACT_OK bbox=1000x500m layers=5 synthetic_geometry=false promotion=source_only")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
