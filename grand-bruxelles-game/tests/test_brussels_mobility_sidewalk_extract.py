import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXTRACTOR = ROOT / "tools" / "brussels_mobility_sidewalk_extract.py"
CONTRACT = ROOT / "data" / "provenance" / "brussels_mobility_sidewalk_source.json"

EXPECTED_BBOX = [147650.0, 169300.0, 149100.0, 171050.0]
EXPECTED_CRS = "EPSG:31370"
EXPECTED_LAYER = "bm_urbis:urbadm_ssw"
DOMAIN = json.dumps(
    [
        {"value": "SW", "label_fr": "Trottoir", "label_nl": "Voetpad"},
        {"value": "S", "label_fr": "Tronçon de rue", "label_nl": "Straatsectie"},
        {"value": "I", "label_fr": "Carrefour", "label_nl": "Kruispunt"},
    ],
    separators=(",", ":"),
).encode()


def load_extractor():
    assert EXTRACTOR.exists(), "official sidewalk corridor extractor missing"
    spec = importlib.util.spec_from_file_location("sidewalk_extract", EXTRACTOR)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def sample_feature(gid=1, source_id=1001, ssft="S"):
    return {
        "type": "Feature",
        "id": f"urbadm_ssw.{gid}",
        "properties": {"gid": gid, "id": source_id, "ssft": ssft, "sslv": "0"},
        "geometry": {
            "type": "Polygon",
            "coordinates": [[[147700.0, 169350.0], [147710.0, 169350.0], [147710.0, 169360.0], [147700.0, 169350.0]]],
        },
    }


def test_contract_declares_layer_identity_extract_scope():
    contract = json.loads(CONTRACT.read_text())
    source = contract["source"]
    required = contract["required_corridor_extract"]
    assert source["layer"] == EXPECTED_LAYER
    assert source["published_domain_sidewalk_code"] == "SW"
    assert source["corridor_requires_ssft_sw"] is False
    assert "sidewalk_feature_code" not in source
    assert required["schema"] == "grand-bruxelles-official-sidewalk-corridor-extract-v1"
    assert required["crs"] == EXPECTED_CRS
    assert required["required_layer"] == EXPECTED_LAYER
    assert required["required_feature_class"] is None
    assert required["ssft_filter_required"] is False
    assert required["required_identity_fields"] == ["feature_id", "source_gid", "source_id", "ssft"]
    assert required["must_validate_ssft_against_published_domain"] is True
    assert required["runtime_use_before_validated_extract"] is False


def test_wfs_query_is_spatially_bounded_and_does_not_mix_semantic_filters():
    module = load_extractor()
    url = module.build_wfs_url(EXPECTED_BBOX)
    assert "bbox=" in url
    assert "CQL_FILTER" not in url
    assert "outputFormat=json" in url
    assert "srsName=EPSG%3A31370" in url
    assert "typeName=bm_urbis%3Aurbadm_ssw" in url


def test_canonicalize_preserves_all_layer_features_and_identity_digests():
    module = load_extractor()
    raw = json.dumps(
        {"type": "FeatureCollection", "features": [sample_feature(2, 2002, "I"), sample_feature(1, 2001, "S")]},
        separators=(",", ":"),
    ).encode()
    result = module.canonicalize_feature_collection(raw, attribute_domain_raw=DOMAIN, query_bbox=EXPECTED_BBOX)
    assert result["schema"] == "grand-bruxelles-official-sidewalk-corridor-extract-v1"
    assert result["crs"] == EXPECTED_CRS
    assert result["query_bbox"] == EXPECTED_BBOX
    assert result["input_feature_count"] == 2
    assert result["feature_count"] == 2
    assert result["source"]["ssft_filter_applied"] is False
    assert result["source"]["observed_ssft_values"] == ["I", "S"]
    assert result["ssft_counts"] == {"I": 1, "S": 1}
    assert [feature["feature_id"] for feature in result["features"]] == ["urbadm_ssw.1", "urbadm_ssw.2"]
    assert result["features"][0]["source_gid"] == 1
    assert result["features"][0]["source_id"] == 2001
    assert result["source_sha256"] == hashlib.sha256(raw).hexdigest()
    assert result["feature_id_sha256"] == hashlib.sha256(b"urbadm_ssw.1\nurbadm_ssw.2\n").hexdigest()
    assert result["claims"]["horizontal_sidewalk_geometry_source_backed"] is True
    assert result["claims"]["sidewalk_semantics_derived_from_layer_identity"] is True
    assert result["claims"]["ssft_sw_filter_source_backed"] is False
    assert result["claims"]["curb_height_source_backed"] is False
    assert result["policy"]["runtime_geometry_authorized"] is False


def test_canonicalize_rejects_unpublished_ssft_and_identity_drift():
    module = load_extractor()
    unpublished = json.dumps({"type": "FeatureCollection", "features": [sample_feature(ssft="ZZ")]}, separators=(",", ":")).encode()
    try:
        module.canonicalize_feature_collection(unpublished, attribute_domain_raw=DOMAIN, query_bbox=EXPECTED_BBOX)
        assert False, "unpublished ssft should fail closed"
    except ValueError as exc:
        assert "unpublished ssft" in str(exc)

    feature = sample_feature()
    feature["id"] = "urbadm_ssw.999"
    drifted = json.dumps({"type": "FeatureCollection", "features": [feature]}, separators=(",", ":")).encode()
    try:
        module.canonicalize_feature_collection(drifted, attribute_domain_raw=DOMAIN, query_bbox=EXPECTED_BBOX)
        assert False, "feature id/gid drift should fail closed"
    except ValueError as exc:
        assert "does not match gid" in str(exc)


def test_canonicalize_rejects_duplicate_identity_and_invalid_domain():
    module = load_extractor()
    duplicate = json.dumps({"type": "FeatureCollection", "features": [sample_feature(), sample_feature()]}, separators=(",", ":")).encode()
    try:
        module.canonicalize_feature_collection(duplicate, attribute_domain_raw=DOMAIN, query_bbox=EXPECTED_BBOX)
        assert False, "duplicate feature identity should fail closed"
    except ValueError as exc:
        assert "duplicate" in str(exc)

    invalid_domain = json.dumps([{"value": "SW", "label_fr": "Wrong", "label_nl": "Voetpad"}]).encode()
    try:
        module.canonicalize_feature_collection(json.dumps({"type": "FeatureCollection", "features": [sample_feature()]}).encode(), attribute_domain_raw=invalid_domain, query_bbox=EXPECTED_BBOX)
        assert False, "changed official SW labels should fail closed"
    except ValueError as exc:
        assert "SW to Trottoir/Voetpad" in str(exc)
