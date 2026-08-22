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
EXPECTED_POLYGONS = 3158
EXPECTED_RINGS = 3163
EXPECTED_VERTICES = 88303
EXPECTED_SSFT = {"A":12,"AC":2,"C":26,"G":12,"I":1337,"IC":55,"K":22,"M":96,"O":1,"S":1554,"SC":7,"W":34}


def _load(path: Path):
    assert path.exists(), f"required persisted official sidewalk file missing: {path}"
    return json.loads(path.read_text(encoding="utf-8"))


def _sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def test_persisted_official_sidewalk_geometry_is_exact_and_fail_closed():
    snapshot = _load(SNAPSHOT)
    manifest = _load(GEOMETRY_MANIFEST)
    assert manifest["schema"] == "grand-bruxelles-official-sidewalk-corridor-geometry-manifest-v1"
    assert manifest["source_snapshot"]["feature_count"] == EXPECTED_FEATURES
    assert manifest["source_snapshot"]["feature_id_sha256"] == EXPECTED_IDS
    assert manifest["source_snapshot"]["canonical_source_content_sha256"] == EXPECTED_SOURCE_CONTENT
    assert manifest["source_snapshot"]["feature_record_sha256"] == EXPECTED_RECORDS
    assert manifest["source_snapshot"]["ssft_counts"] == EXPECTED_SSFT
    assert manifest["source_snapshot"]["query_bbox"] == snapshot["source"]["query_bbox"]
    assert manifest["source"]["layer"] == "bm_urbis:urbadm_ssw"
    assert manifest["source"]["license"] == "CC0-1.0"
    assert manifest["source"]["crs"] == "EPSG:31370"
    policy = manifest["policy"]
    for key in ("runtime_geometry_authorized","jouable_promotion_authorized","vertical_extrusion_allowed","curb_height_inference_allowed","game_world_transform_applied"):
        assert policy[key] is False, f"unsafe authorization enabled: {key}"
    assert policy["source_geometry_modified"] is False
    assert policy["storage_compression_changes_canonical_records"] is False
    assert manifest["claims"]["horizontal_sidewalk_geometry_source_backed"] is True
    for key in ("curb_height_source_backed","surface_elevation_source_backed","sidewalk_profile_source_backed","paving_unit_dimensions_source_backed","material_identity_source_backed"):
        assert manifest["claims"][key] is False, f"unsupported source claim enabled: {key}"

    features = []
    for chunk in manifest["chunks"]:
        path = CHUNK_DIR / chunk["file"]
        assert path.exists(), f"required persisted geometry chunk missing: {path}"
        encoded = path.read_bytes()
        assert _sha256(encoded) == chunk["file_sha256"]
        assert chunk["encoding"] == "base64+xz"
        compressed = base64.b64decode(encoded, validate=False)
        assert len(compressed) == chunk["compressed_bytes"]
        assert _sha256(compressed) == chunk["compressed_sha256"]
        canonical = lzma.decompress(compressed, format=lzma.FORMAT_XZ)
        assert len(canonical) == chunk["canonical_bytes"]
        assert _sha256(canonical) == chunk["canonical_sha256"]
        payload = json.loads(canonical)
        assert payload["schema"] == "grand-bruxelles-official-sidewalk-corridor-geometry-chunk-v1"
        assert payload["chunk_index"] == chunk["chunk_index"]
        assert payload["feature_start"] == len(features)
        assert len(payload["features"]) == chunk["feature_count"]
        assert payload["features"][0]["feature_id"] == chunk["first_feature_id"]
        assert payload["features"][-1]["feature_id"] == chunk["last_feature_id"]
        features.extend(payload["features"])

    assert len(features) == EXPECTED_FEATURES
    assert [feature["feature_id"] for feature in features] == sorted(feature["feature_id"] for feature in features)
    assert len({feature["feature_id"] for feature in features}) == EXPECTED_FEATURES
    ids_blob = ("\n".join(feature["feature_id"] for feature in features) + "\n").encode("utf-8")
    assert _sha256(ids_blob) == EXPECTED_IDS
    records_blob = json.dumps(features, ensure_ascii=False, separators=(",",":"), sort_keys=True).encode("utf-8")
    assert _sha256(records_blob) == EXPECTED_RECORDS
    assert Counter(feature["ssft"] for feature in features) == Counter(EXPECTED_SSFT)

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
                for point in ring:
                    assert len(point) == 2, "persisted source geometry must remain horizontal Lambert72 XY only"
    assert (polygons, rings, vertices) == (EXPECTED_POLYGONS, EXPECTED_RINGS, EXPECTED_VERTICES)


if __name__ == "__main__":
    test_persisted_official_sidewalk_geometry_is_exact_and_fail_closed()
    print("OFFICIAL_SIDEWALK_CANONICAL_GEOMETRY_OK")
