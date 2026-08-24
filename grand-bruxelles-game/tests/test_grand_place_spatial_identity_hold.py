#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOLD = ROOT / "data/provenance/grand_place_spatial_identity.review.json"
UPSTREAM_REVIEW = ROOT / "data/provenance/grand_place_cell_registration.review.json"
REGISTRATION = ROOT / "data/provenance/grand_place_canonical_registration.review.json"
INDEX = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"
HISTORICAL_CELL = ROOT / "data/cell_manifests/bxl-e148000-n170000-s500.json"
FRAME_EVIDENCE = ROOT / "data/qa/city_machine/road_registered_cell_overlap_measurement_v2.json"

OFFICIAL_WGS84 = {"lon": 4.352461951836625, "lat": 50.8467468297299}
OFFICIAL_LAMBERT72 = [148852.74417614136, 170704.8857889818]
HISTORICAL_CELL_ID = "bxl-e148000-n170000-s500"
HISTORICAL_BBOX = [148000.0, 170000.0, 148500.0, 170500.0]
EXPECTED_GRAND_PLACE_CELL_ID = "bxl-e148500-n170500-s500"
EXPECTED_GRAND_PLACE_BBOX = [148500.0, 170500.0, 149000.0, 171000.0]
FRAME_SEMANTIC_SHA = "84802ee94bcbbb2d849e75fa0a11e49f7d19a448e3b0557617f75d5b35b9fa7b"
FRAME_ROAD_IDS = [13842686, 684214770]


def load(path: Path) -> dict:
    assert path.is_file(), f"required spatial-identity evidence missing: {path}"
    return json.loads(path.read_text(encoding="utf-8"))


def contains(bbox: list[float], point: list[float]) -> bool:
    return bbox[0] <= point[0] < bbox[2] and bbox[1] <= point[1] < bbox[3]


def main() -> None:
    hold = load(HOLD)
    upstream = load(UPSTREAM_REVIEW)
    registration = load(REGISTRATION)
    index = load(INDEX)
    historical = load(HISTORICAL_CELL)
    frame = load(FRAME_EVIDENCE)

    assert hold["schema"] == "grand-bruxelles-grand-place-spatial-identity-review-v1"
    assert hold["status"] == "SPATIAL_IDENTITY_MISMATCH_HOLD"
    assert hold["official_anchor"]["source_authority"] == "City of Brussels Open Data"
    assert hold["official_anchor"]["dataset"] == "points-acces-wifi-gratuit-wifibrussels-vbx"
    assert hold["official_anchor"]["record_name"] == "Grand-Place"
    assert hold["official_anchor"]["crs"] == "EPSG:4326"
    assert hold["official_anchor"]["coordinate"] == OFFICIAL_WGS84
    assert hold["transformed_anchor"]["crs"] == "EPSG:31370"
    assert hold["transformed_anchor"]["coordinate"] == OFFICIAL_LAMBERT72
    assert hold["transformed_anchor"]["method"] == "EPSG:4326_to_EPSG:31370_PROJ"

    observed = hold["observed_claim"]
    expected = hold["expected_target"]
    assert observed["cell_id"] == HISTORICAL_CELL_ID
    assert observed["bbox"] == HISTORICAL_BBOX
    assert expected["cell_id"] == EXPECTED_GRAND_PLACE_CELL_ID
    assert expected["bbox"] == EXPECTED_GRAND_PLACE_BBOX
    assert not contains(HISTORICAL_BBOX, OFFICIAL_LAMBERT72)
    assert contains(EXPECTED_GRAND_PLACE_BBOX, OFFICIAL_LAMBERT72)

    # A newly merged City Machine frame measurement places two Grand-Place-adjacent
    # named roads in the historical cell, while its own Lambert72 road footprint does
    # not contain the official Grand-Place anchor. Preserve it as evidence-only, but
    # never let that runtime-frame result establish authoritative spatial identity.
    assert frame["schema"] == "grand-bruxelles-road-registered-cell-overlap-measurement-v2"
    assert frame["semantic_sha256"] == FRAME_SEMANTIC_SHA
    assert [row["osm_id"] for row in frame["overlaps"]] == FRAME_ROAD_IDS
    for row in frame["overlaps"]:
        assert row["cells"] == [
            {
                "cell_id": HISTORICAL_CELL_ID,
                "point_hits": row["cells"][0]["point_hits"],
                "segment_hits": row["cells"][0]["segment_hits"],
            }
        ]
    assert not contains(frame["road_lambert72_bbox"], OFFICIAL_LAMBERT72)
    for key in [
        "road_cell_mapping_authorized",
        "runtime_mount_authorized",
        "rendered_geometry_authorized",
        "collision_authorized",
        "safe_spawn_authorized",
        "jouable_promotion_authorized",
    ]:
        assert frame[key] is False, key

    conflict = hold["conflicting_runtime_frame_evidence"]
    assert conflict["path"] == "data/qa/city_machine/road_registered_cell_overlap_measurement_v2.json"
    assert conflict["semantic_sha256"] == FRAME_SEMANTIC_SHA
    assert conflict["observed_cell_id"] == HISTORICAL_CELL_ID
    assert conflict["road_ids"] == FRAME_ROAD_IDS
    assert conflict["authoritative_spatial_identity"] is False
    assert conflict["use_for_grand_place_registration"] is False
    assert conflict["road_cell_mapping_authorized"] is False
    assert conflict["runtime_mount_authorized"] is False

    assert historical["cell_id"] == HISTORICAL_CELL_ID
    assert historical["bbox"] == HISTORICAL_BBOX
    rows = {row["cell_id"]: row for row in index["entries"]}
    assert HISTORICAL_CELL_ID in rows, "valid generic evidence cell must not be deleted"
    assert EXPECTED_GRAND_PLACE_CELL_ID not in rows, "correct Grand-Place source cell has not been acquired/registered yet"

    assert upstream["status"] == "SPATIAL_IDENTITY_MISMATCH_HOLD"
    assert upstream["target"]["cell_id"] == HISTORICAL_CELL_ID
    assert upstream["target"]["treat_as_grand_place"] is False
    assert upstream["expected_grand_place_target"]["cell_id"] == EXPECTED_GRAND_PLACE_CELL_ID
    assert upstream["expected_grand_place_target"]["authoritative_source_manifest_present"] is False
    assert upstream["expected_grand_place_target"]["canonical_manifest_present"] is False
    for key in [
        "registration_authorized",
        "road_cell_mapping_authorized",
        "runtime_mount_authorized",
        "rendered_geometry_authorized",
        "collision_authorized",
        "safe_spawn_authorized",
        "jouable_promotion_authorized",
    ]:
        assert upstream[key] is False, key

    assert registration["status"] == "SPATIAL_IDENTITY_MISMATCH_HOLD"
    assert registration["target_registered"] is False
    assert registration["destination_readiness"] == "HOLD_WRONG_CELL_IDENTITY"
    assert registration["spatial_identity_review"] == "data/provenance/grand_place_spatial_identity.review.json"
    assert registration["historical_registration"]["registered_as_generic_evidence"] is True
    assert registration["historical_registration"]["treat_as_grand_place"] is False
    assert registration["expected_grand_place_target"]["cell_id"] == EXPECTED_GRAND_PLACE_CELL_ID
    assert all(value is False for value in registration["runtime_authorization"].values())
    assert all(value is False for value in hold["authorization"].values())

    print(
        "GRAND_PLACE_SPATIAL_IDENTITY_HOLD_OK: "
        f"observed={HISTORICAL_CELL_ID} expected={EXPECTED_GRAND_PLACE_CELL_ID} "
        f"anchor={OFFICIAL_LAMBERT72} frame_conflict={FRAME_SEMANTIC_SHA}"
    )


if __name__ == "__main__":
    main()
