#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / "data/provenance/brussels_mobility_sidewalk_source.json"

assert P.exists(), "official Brussels Mobility sidewalk source contract missing"
D = json.loads(P.read_text(encoding="utf-8"))

assert D["schema"] == "grand-bruxelles-official-sidewalk-source-v1"
assert D["production_base_sha"] == "f7b355421098e9de1cecddeaf999df622fd04aec"
source = D["source"]
assert source["publisher"] == "Paradigm"
assert source["dataset"] == "Trottoir"
assert source["layer"] == "bm_urbis:urbadm_ssw"
assert source["license"] == "CC0-1.0"
assert source["crs"] == "EPSG:31370"
assert source["feature_type_field"] == "ssft"
assert source["sidewalk_semantics_basis"] == "official_dataset_and_layer_identity"
assert source["published_domain_sidewalk_code"] == "SW"
assert source["corridor_requires_ssft_sw"] is False
assert source["volatile_wfs_metadata_fields"] == ["timeStamp"]
assert "sidewalk_feature_code" not in source
assert source["metadata_last_updated"] == "2024-06-21"
assert source["accessed_on"] == "2026-08-22"

metadata = source["metadata_evidence"]
assert "common part" in metadata["description"]
assert metadata["published_attribute_fields"] == ["ssft"]
assert metadata["ssft_sw_label_fr"] == "Trottoir"
assert metadata["ssft_sw_label_nl"] == "Voetpad"
assert "not a local SW filter" in metadata["selection_rule"]

claims = D["claims"]
assert claims["horizontal_sidewalk_geometry_source_backed"] is True
assert claims["sidewalk_semantic_class_source_backed"] is True
assert claims["sidewalk_semantics_derived_from_layer_identity"] is True
assert claims["ssft_values_source_backed"] is True
assert claims["ssft_sw_filter_source_backed"] is False
for unsupported in (
    "curb_height_source_backed",
    "surface_elevation_source_backed",
    "sidewalk_profile_source_backed",
    "paving_unit_dimensions_source_backed",
    "material_identity_source_backed",
):
    assert claims[unsupported] is False, unsupported

extract = D["required_corridor_extract"]
assert extract["schema"] == "grand-bruxelles-official-sidewalk-corridor-extract-v1"
assert extract["target_path"] == "data/provenance/brussels_mobility_sidewalk_corridor_extract.json"
assert extract["crs"] == "EPSG:31370"
assert extract["required_layer"] == "bm_urbis:urbadm_ssw"
assert extract["required_feature_class"] is None
assert extract["ssft_filter_required"] is False
assert extract["required_identity_fields"] == ["feature_id", "source_gid", "source_id", "ssft"]
assert extract["digest_algorithm"] == "sha256"
assert extract["bounded_to_vertical_slice"] is True
assert extract["must_record_query_bbox"] is True
assert extract["must_record_raw_source_digest"] is True
assert extract["must_record_canonical_source_content_digest"] is True
assert extract["canonical_source_digest_ignores_only"] == ["timeStamp"]
assert extract["must_record_feature_count"] is True
assert extract["must_record_feature_id_digest"] is True
assert extract["must_record_ssft_counts"] is True
assert extract["must_validate_ssft_against_published_domain"] is True
assert extract["runtime_use_before_validated_extract"] is False

policy = D["policy"]
assert policy["horizontal_runtime_candidate_allowed"] is True
assert policy["vertical_extrusion_allowed"] is False
assert policy["curb_height_inference_allowed"] is False
assert policy["runtime_geometry_authorized"] is False
assert policy["jouable_promotion_authorized"] is False
assert policy["requires_bounded_corridor_extract_before_runtime"] is True
assert policy["requires_exact_feature_identity_and_digest_before_runtime"] is True
assert policy["requires_independent_vertical_source_for_curb_height"] is True

urls = source["urls"]
assert urls["metadata"] == "https://data.mobility.brussels/en/info/urbadm_ssw/"
assert "typeName=bm_urbis%3Aurbadm_ssw" in urls["lambert72_json"]
assert "srsName=EPSG%3A31370" in urls["lambert72_json"]
assert urls["wfs_layer"] == "bm_urbis:urbadm_ssw"
assert urls["attribute_domain"].endswith("?tid=ssft")

print("BRUSSELS_MOBILITY_SIDEWALK_SOURCE_OK")
