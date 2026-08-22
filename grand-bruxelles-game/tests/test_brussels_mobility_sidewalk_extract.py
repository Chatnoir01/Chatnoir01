import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXTRACTOR = ROOT / "tools/brussels_mobility_sidewalk_extract.py"
CONTRACT = ROOT / "data/provenance/brussels_mobility_sidewalk_source.json"
BBOX = [147650.0, 169300.0, 149100.0, 171050.0]
DOMAIN = json.dumps([
    {"value":"SW","label_fr":"Trottoir","label_nl":"Voetpad"},
    {"value":"S","label_fr":"Tronçon de rue","label_nl":"Straatsectie"},
    {"value":"I","label_fr":"Carrefour","label_nl":"Kruispunt"},
], separators=(",", ":")).encode()


def module():
    assert EXTRACTOR.exists(), "official sidewalk corridor extractor missing"
    spec = importlib.util.spec_from_file_location("sidewalk_extract", EXTRACTOR)
    m = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(m)
    return m


def feature(gid=1, source_id=1001, ssft="S"):
    return {
        "type":"Feature", "id":f"urbadm_ssw.{gid}",
        "properties":{"gid":gid,"id":source_id,"ssft":ssft,"sslv":"0"},
        "geometry":{"type":"Polygon","coordinates":[[[147700.0,169350.0],[147710.0,169350.0],[147710.0,169360.0],[147700.0,169350.0]]]},
    }


def raw(features, timestamp="2026-08-22T14:00:00Z"):
    return json.dumps({
        "type":"FeatureCollection", "features":features,
        "totalFeatures":len(features), "numberMatched":len(features), "numberReturned":len(features),
        "timeStamp":timestamp,
        "crs":{"type":"name","properties":{"name":"urn:ogc:def:crs:EPSG::31370"}},
        "bbox":BBOX,
    }, separators=(",", ":"), ensure_ascii=False).encode()


def test_contract_scope_and_digest_policy():
    d = json.loads(CONTRACT.read_text())
    s = d["source"]
    e = d["required_corridor_extract"]
    assert s["layer"] == "bm_urbis:urbadm_ssw"
    assert s["published_domain_sidewalk_code"] == "SW"
    assert s["corridor_requires_ssft_sw"] is False
    assert s["volatile_wfs_metadata_fields"] == ["timeStamp"]
    assert "sidewalk_feature_code" not in s
    assert e["required_feature_class"] is None
    assert e["ssft_filter_required"] is False
    assert e["required_identity_fields"] == ["feature_id","source_gid","source_id","ssft"]
    assert e["must_record_raw_source_digest"] is True
    assert e["must_record_canonical_source_content_digest"] is True
    assert e["canonical_source_digest_ignores_only"] == ["timeStamp"]
    assert e["runtime_use_before_validated_extract"] is False


def test_query_is_bounded_without_semantic_filter():
    url = module().build_wfs_url(BBOX)
    assert "bbox=" in url and "CQL_FILTER" not in url
    assert "typeName=bm_urbis%3Aurbadm_ssw" in url
    assert "srsName=EPSG%3A31370" in url


def test_layer_rows_identity_and_digests_are_preserved():
    m = module()
    payload = raw([feature(2,2002,"I"), feature(1,2001,"S")])
    result = m.canonicalize_feature_collection(payload, attribute_domain_raw=DOMAIN, query_bbox=BBOX)
    assert result["feature_count"] == result["input_feature_count"] == 2
    assert result["source"]["ssft_filter_applied"] is False
    assert result["source"]["observed_ssft_values"] == ["I","S"]
    assert result["ssft_counts"] == {"I":1,"S":1}
    assert [f["feature_id"] for f in result["features"]] == ["urbadm_ssw.1","urbadm_ssw.2"]
    assert result["source_sha256"] == hashlib.sha256(payload).hexdigest()
    assert len(result["canonical_source_content_sha256"]) == 64
    assert result["feature_id_sha256"] == hashlib.sha256(b"urbadm_ssw.1\nurbadm_ssw.2\n").hexdigest()
    assert result["claims"]["ssft_sw_filter_source_backed"] is False
    assert result["claims"]["curb_height_source_backed"] is False
    assert result["policy"]["runtime_geometry_authorized"] is False


def test_timestamp_and_feature_order_do_not_change_canonical_content_digest():
    m = module()
    fs = [feature(2,2002,"I"), feature(1,2001,"S")]
    a_raw = raw(fs, "2026-08-22T14:00:00Z")
    b_raw = raw(list(reversed(fs)), "2026-08-22T15:00:00Z")
    a = m.canonicalize_feature_collection(a_raw, attribute_domain_raw=DOMAIN, query_bbox=BBOX)
    b = m.canonicalize_feature_collection(b_raw, attribute_domain_raw=DOMAIN, query_bbox=BBOX)
    assert a["source_sha256"] != b["source_sha256"]
    assert a["canonical_source_content_sha256"] == b["canonical_source_content_sha256"]
    changed = [feature(2,2002,"I"), feature(1,2001,"S")]
    changed[0]["geometry"]["coordinates"][0][0][0] += 0.25
    c = m.canonicalize_feature_collection(raw(changed), attribute_domain_raw=DOMAIN, query_bbox=BBOX)
    assert c["canonical_source_content_sha256"] != a["canonical_source_content_sha256"]


def test_unpublished_ssft_identity_drift_duplicate_and_domain_drift_are_rejected():
    m = module()
    cases = []
    cases.append((raw([feature(ssft="ZZ")]), DOMAIN, "unpublished ssft"))
    drift = feature(); drift["id"] = "urbadm_ssw.999"
    cases.append((raw([drift]), DOMAIN, "does not match gid"))
    cases.append((raw([feature(), feature()]), DOMAIN, "duplicate"))
    bad_domain = json.dumps([{"value":"SW","label_fr":"Wrong","label_nl":"Voetpad"}]).encode()
    cases.append((raw([feature()]), bad_domain, "SW to Trottoir/Voetpad"))
    for payload, domain, expected in cases:
        try:
            m.canonicalize_feature_collection(payload, attribute_domain_raw=domain, query_bbox=BBOX)
            assert False, expected
        except ValueError as exc:
            assert expected in str(exc)
