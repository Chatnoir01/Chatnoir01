#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / "data/provenance/brussels_mobility_sidewalk_source.json"

assert P.exists(), "official Brussels Mobility sidewalk source contract missing"
D = json.loads(P.read_text(encoding="utf-8"))

assert D["schema"] == "grand-bruxelles-official-sidewalk-source-v1"
assert D["production_base_sha"] == "407ab23fbf477dd430be67600d601dd41b7146ad"
source = D["source"]
assert source["publisher"] == "Paradigm"
assert source["dataset"] == "Trottoir"
assert source["layer"] == "bm_urbis:urbadm_ssw"
assert source["license"] == "CC0-1.0"
assert source["crs"] == "EPSG:31370"
assert source["feature_type_field"] == "ssft"
assert source["sidewalk_feature_code"] == "SW"
assert source["metadata_last_updated"] == "2024-06-21"
assert source["accessed_on"] == "2026-08-22"

claims = D["claims"]
assert claims["horizontal_sidewalk_geometry_source_backed"] is True
assert claims["sidewalk_semantic_class_source_backed"] is True
for unsupported in (
    "curb_height_source_backed",
    "surface_elevation_source_backed",
    "sidewalk_profile_source_backed",
    "paving_unit_dimensions_source_backed",
    "material_identity_source_backed",
):
    assert claims[unsupported] is False, unsupported

policy = D["policy"]
assert policy["horizontal_runtime_candidate_allowed"] is True
assert policy["vertical_extrusion_allowed"] is False
assert policy["curb_height_inference_allowed"] is False
assert policy["runtime_geometry_authorized"] is False
assert policy["jouable_promotion_authorized"] is False
assert policy["requires_bounded_corridor_extract_before_runtime"] is True

urls = source["urls"]
assert urls["metadata"] == "https://data.mobility.brussels/en/info/urbadm_ssw/"
assert "typeName=bm_urbis%3Aurbadm_ssw" in urls["lambert72_json"]
assert "srsName=EPSG%3A31370" in urls["lambert72_json"]
assert urls["wfs_layer"] == "bm_urbis:urbadm_ssw"

print("BRUSSELS_MOBILITY_SIDEWALK_SOURCE_OK")
