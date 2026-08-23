import base64
import hashlib
import json
import lzma
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "data/provenance/brussels_mobility_sidewalk_corridor_snapshot_manifest.json"
GEOMETRY_MANIFEST = ROOT / "data/provenance/brussels_mobility_sidewalk_corridor_geometry_manifest.json"
CHUNK_DIR = ROOT / "data/provenance/brussels_mobility_sidewalk_corridor_geometry"
EXPECTED_FEATURES = 3158
EXPECTED_IDS = "779f6fdac205ebf3ebfa99dd360f992e5b13682a99f05a27858405bb34fe5fb8"
EXPECTED_SOURCE_CONTENT = "fff46be67855b1d2e651e735397e970550513e4e657bda3b3f09cc285b30b3dc"
EXPECTED_RECORDS = "477909006506e48d9ac8dac24f2fefe66a3421ea3d9b19a49b46452992b6cc7b"
EXPECTED_COUNTS = (3158, 3163, 88303)
EXPECTED_SSFT = {"A":12,"AC":2,"C":26,"G":12,"I":1337,"IC":55,"K":22,"M":96,"O":1,"S":1554,"SC":7,"W":34}

def load(path):
    assert path.exists(), f"required persisted official sidewalk file missing: {path}"
    return json.loads(path.read_text(encoding="utf-8"))

def sha(value):
    return hashlib.sha256(value).hexdigest()

def test_persisted_official_sidewalk_geometry_is_exact_and_fail_closed():
    snapshot = load(SNAPSHOT)
    manifest = load(GEOMETRY_MANIFEST)
    assert manifest["schema"] == "grand-bruxelles-official-sidewalk-corridor-geometry-manifest-v1"
    assert manifest["production_base_sha"] == "055197bec091cc78334667e979f90800498adf09"
    source = manifest["source_snapshot"]
    assert source["feature_count"] == EXPECTED_FEATURES
    assert source["feature_id_sha256"] == EXPECTED_IDS
    assert source["canonical_source_content_sha256"] == EXPECTED_SOURCE_CONTENT
    assert source["feature_record_sha256"] == EXPECTED_RECORDS
    assert source["ssft_counts"] == EXPECTED_SSFT
    assert source["query_bbox"] == snapshot["source"]["query_bbox"]
    assert manifest["source"] == {"publisher":"Paradigm","dataset":"Trottoir","layer":"bm_urbis:urbadm_ssw","license":"CC0-1.0","crs":"EPSG:31370"}
    for key in ("runtime_geometry_authorized","jouable_promotion_authorized","vertical_extrusion_allowed","curb_height_inference_allowed","game_world_transform_applied"):
        assert manifest["policy"][key] is False
    assert manifest["next_gate"]["generic_sidewalk_count_reference"] == 430
    assert manifest["next_gate"]["runtime_replacement_forbidden_until_gate_green"] is True

    features = []
    for chunk in manifest["chunks"]:
        path = CHUNK_DIR / chunk["file"]
        assert path.exists(), f"required persisted geometry chunk missing: {path}"
        encoded = path.read_bytes()
        assert sha(encoded) == chunk["file_sha256"]
        compressed = base64.b64decode(encoded, validate=False)
        assert len(compressed) == chunk["compressed_bytes"] and sha(compressed) == chunk["compressed_sha256"]
        canonical = lzma.decompress(compressed, format=lzma.FORMAT_XZ)
        assert len(canonical) == chunk["canonical_bytes"] and sha(canonical) == chunk["canonical_sha256"]
        payload = json.loads(canonical)
        assert payload["chunk_index"] == chunk["chunk_index"]
        assert payload["feature_start"] == len(features)
        assert len(payload["features"]) == chunk["feature_count"]
        features.extend(payload["features"])

    assert len(features) == EXPECTED_FEATURES
    assert [f["feature_id"] for f in features] == sorted(f["feature_id"] for f in features)
    assert len({f["feature_id"] for f in features}) == EXPECTED_FEATURES
    assert sha(("\n".join(f["feature_id"] for f in features)+"\n").encode()) == EXPECTED_IDS
    assert sha(json.dumps(features, ensure_ascii=False, separators=(",",":"), sort_keys=True).encode()) == EXPECTED_RECORDS
    assert Counter(f["ssft"] for f in features) == Counter(EXPECTED_SSFT)

    polygons = rings = vertices = 0
    for feature in features:
        assert feature["feature_id"] == f"urbadm_ssw.{feature['source_gid']}"
        geometry = feature["geometry"]
        assert geometry["type"] == "MultiPolygon"
        for polygon in geometry["coordinates"]:
            polygons += 1
            for ring in polygon:
                rings += 1
                vertices += len(ring)
                assert all(len(point) == 2 for point in ring)
    assert (polygons, rings, vertices) == EXPECTED_COUNTS

if __name__ == "__main__":
    test_persisted_official_sidewalk_geometry_is_exact_and_fail_closed()
    print("OFFICIAL_SIDEWALK_CANONICAL_GEOMETRY_OK")
