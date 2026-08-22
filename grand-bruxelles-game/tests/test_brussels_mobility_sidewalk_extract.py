import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXTRACTOR = ROOT / "tools" / "brussels_mobility_sidewalk_extract.py"
CONTRACT = ROOT / "data" / "provenance" / "brussels_mobility_sidewalk_source.json"

EXPECTED_BBOX = [147650.0, 169300.0, 149100.0, 171050.0]
EXPECTED_CRS = "EPSG:31370"
EXPECTED_CLASS = "SW"


def load_extractor():
    assert EXTRACTOR.exists(), "official sidewalk corridor extractor missing"
    spec = importlib.util.spec_from_file_location("sidewalk_extract", EXTRACTOR)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def sample_feature(fid="urbadm_ssw.1", ssft="SW"):
    return {
        "type": "Feature",
        "id": fid,
        "properties": {"ssft": ssft},
        "geometry": {
            "type": "Polygon",
            "coordinates": [[[147700.0, 169350.0], [147710.0, 169350.0], [147710.0, 169360.0], [147700.0, 169350.0]]],
        },
    }


def test_contract_declares_exact_extract_scope():
    contract = json.loads(CONTRACT.read_text())
    required = contract["required_corridor_extract"]
    assert required["schema"] == "grand-bruxelles-official-sidewalk-corridor-extract-v1"
    assert required["crs"] == EXPECTED_CRS
    assert required["required_feature_class"] == EXPECTED_CLASS
    assert required["runtime_use_before_validated_extract"] is False


def test_canonicalize_persists_identity_digests_and_scope():
    module = load_extractor()
    raw = json.dumps({"type": "FeatureCollection", "features": [sample_feature()]}, separators=(",", ":")).encode()
    result = module.canonicalize_feature_collection(raw, query_bbox=EXPECTED_BBOX)
    assert result["schema"] == "grand-bruxelles-official-sidewalk-corridor-extract-v1"
    assert result["crs"] == EXPECTED_CRS
    assert result["query_bbox"] == EXPECTED_BBOX
    assert result["feature_count"] == 1
    assert result["features"][0]["feature_id"] == "urbadm_ssw.1"
    assert result["features"][0]["ssft"] == EXPECTED_CLASS
    assert result["source_sha256"] == hashlib.sha256(raw).hexdigest()
    assert result["feature_id_sha256"] == hashlib.sha256(b"urbadm_ssw.1\n").hexdigest()
    assert result["claims"]["horizontal_sidewalk_geometry_source_backed"] is True
    assert result["claims"]["curb_height_source_backed"] is False
    assert result["policy"]["runtime_geometry_authorized"] is False


def test_canonicalize_fails_closed_on_non_sidewalk_or_duplicate_identity():
    module = load_extractor()
    bad_class = json.dumps({"type": "FeatureCollection", "features": [sample_feature(ssft="XX")]}, separators=(",", ":")).encode()
    try:
        module.canonicalize_feature_collection(bad_class, query_bbox=EXPECTED_BBOX)
        assert False, "non-SW feature should fail closed"
    except ValueError as exc:
        assert "non-SW" in str(exc)

    duplicate = json.dumps({"type": "FeatureCollection", "features": [sample_feature(), sample_feature()]}, separators=(",", ":")).encode()
    try:
        module.canonicalize_feature_collection(duplicate, query_bbox=EXPECTED_BBOX)
        assert False, "duplicate feature identity should fail closed"
    except ValueError as exc:
        assert "duplicate" in str(exc)
