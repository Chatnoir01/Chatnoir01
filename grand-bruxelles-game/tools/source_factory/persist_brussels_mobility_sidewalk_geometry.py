#!/usr/bin/env python3
import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

EXPECTED_FEATURE_COUNT = 3158
EXPECTED_FEATURE_ID_SHA256 = "779f6fdac205ebf3ebfa99dd360f992e5b13682a99f05a27858405bb34fe5fb8"
EXPECTED_CANONICAL_SOURCE_SHA256 = "fff46be67855b1d2e651e735397e970550513e4e657bda3b3f09cc285b30b3dc"
EXPECTED_DOMAIN_SHA256 = "7c6fcec4a5b8add262e127bb0097350928450ebb2fe01aa96c63025e627cdc79"
EXPECTED_RECORD_SHA256 = "477909006506e48d9ac8dac24f2fefe66a3421ea3d9b19a49b46452992b6cc7b"
EXPECTED_SSFT = {"A":12,"AC":2,"C":26,"G":12,"I":1337,"IC":55,"K":22,"M":96,"O":1,"S":1554,"SC":7,"W":34}
CHUNK_SIZE = 800


def canonical_json(value) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def validate_source(payload: dict) -> list[dict]:
    assert payload["schema"] == "grand-bruxelles-official-sidewalk-corridor-extract-v1"
    assert payload["feature_count"] == EXPECTED_FEATURE_COUNT
    assert payload["feature_id_sha256"] == EXPECTED_FEATURE_ID_SHA256
    assert payload["canonical_source_content_sha256"] == EXPECTED_CANONICAL_SOURCE_SHA256
    assert payload["source"]["attribute_domain_sha256"] == EXPECTED_DOMAIN_SHA256
    assert payload["source"]["layer"] == "bm_urbis:urbadm_ssw"
    assert payload["source"]["license"] == "CC0-1.0"
    assert payload["crs"] == "EPSG:31370"
    assert payload["ssft_counts"] == EXPECTED_SSFT
    policy = payload["policy"]
    for key in ("runtime_geometry_authorized", "jouable_promotion_authorized", "vertical_extrusion_allowed", "curb_height_inference_allowed"):
        assert policy[key] is False, f"unsafe source policy enabled: {key}"

    features = sorted(payload["features"], key=lambda feature: feature["feature_id"])
    assert len(features) == EXPECTED_FEATURE_COUNT
    assert len({feature["feature_id"] for feature in features}) == EXPECTED_FEATURE_COUNT
    ids = "\n".join(feature["feature_id"] for feature in features).encode("utf-8")
    assert sha256_bytes(ids) == EXPECTED_FEATURE_ID_SHA256
    assert sha256_bytes(canonical_json(features)) == EXPECTED_RECORD_SHA256
    assert Counter(feature["ssft"] for feature in features) == Counter(EXPECTED_SSFT)

    for feature in features:
        assert feature["feature_id"] == f"urbadm_ssw.{feature['source_gid']}"
        geometry = feature["geometry"]
        assert geometry["type"] == "MultiPolygon"
        for polygon in geometry["coordinates"]:
            for ring in polygon:
                for point in ring:
                    assert len(point) == 2, "source persistence must remain horizontal Lambert72 XY"
    return features


def write_geometry(source: dict, features: list[dict], output_root: Path, production_base_sha: str) -> None:
    chunk_dir = output_root / "brussels_mobility_sidewalk_corridor_geometry"
    chunk_dir.mkdir(parents=True, exist_ok=True)
    chunks = []
    polygon_count = ring_count = vertex_count = 0

    for feature in features:
        for polygon in feature["geometry"]["coordinates"]:
            polygon_count += 1
            for ring in polygon:
                ring_count += 1
                vertex_count += len(ring)

    for chunk_index, start in enumerate(range(0, len(features), CHUNK_SIZE)):
        subset = features[start:start + CHUNK_SIZE]
        payload = {
            "schema": "grand-bruxelles-official-sidewalk-corridor-geometry-chunk-v1",
            "chunk_index": chunk_index,
            "feature_start": start,
            "feature_count": len(subset),
            "features": subset,
        }
        raw = canonical_json(payload)
        filename = f"chunk_{chunk_index:02d}.json"
        (chunk_dir / filename).write_bytes(raw)
        chunks.append({
            "chunk_index": chunk_index,
            "file": filename,
            "feature_count": len(subset),
            "sha256": sha256_bytes(raw),
            "first_feature_id": subset[0]["feature_id"],
            "last_feature_id": subset[-1]["feature_id"],
        })

    manifest = {
        "schema": "grand-bruxelles-official-sidewalk-corridor-geometry-manifest-v1",
        "production_base_sha": production_base_sha,
        "source": {
            "publisher": "Paradigm",
            "dataset": "Trottoir",
            "layer": "bm_urbis:urbadm_ssw",
            "license": "CC0-1.0",
            "crs": "EPSG:31370",
        },
        "source_snapshot": {
            "feature_count": EXPECTED_FEATURE_COUNT,
            "feature_id_sha256": EXPECTED_FEATURE_ID_SHA256,
            "canonical_source_content_sha256": EXPECTED_CANONICAL_SOURCE_SHA256,
            "feature_record_sha256": EXPECTED_RECORD_SHA256,
            "attribute_domain_sha256": EXPECTED_DOMAIN_SHA256,
            "query_bbox": source["query_bbox"],
            "ssft_counts": EXPECTED_SSFT,
            "multipolygon_count": polygon_count,
            "ring_count": ring_count,
            "vertex_count": vertex_count,
        },
        "chunks": chunks,
        "claims": {
            "horizontal_sidewalk_geometry_source_backed": True,
            "official_feature_identity_source_backed": True,
            "ssft_values_source_backed": True,
            "curb_height_source_backed": False,
            "surface_elevation_source_backed": False,
            "sidewalk_profile_source_backed": False,
            "paving_unit_dimensions_source_backed": False,
            "material_identity_source_backed": False,
        },
        "policy": {
            "source_geometry_modified": False,
            "runtime_geometry_authorized": False,
            "jouable_promotion_authorized": False,
            "vertical_extrusion_allowed": False,
            "curb_height_inference_allowed": False,
            "game_world_transform_applied": False,
            "overlap_measurement_required_before_runtime": True,
            "overlap_measurement_authorizes_runtime": False,
        },
        "next_gate": {
            "measure_horizontal_overlap_against_generic_sidewalks": True,
            "generic_sidewalk_count_reference": 430,
            "runtime_replacement_forbidden_until_gate_green": True,
        },
    }
    manifest_path = output_root / "brussels_mobility_sidewalk_corridor_geometry_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"OFFICIAL_SIDEWALK_GEOMETRY_PERSISTED features={len(features)} polygons={polygon_count} rings={ring_count} vertices={vertex_count} chunks={len(chunks)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_extract", type=Path)
    parser.add_argument("output_root", type=Path)
    parser.add_argument("--production-base-sha", required=True)
    args = parser.parse_args()
    source = json.loads(args.source_extract.read_text(encoding="utf-8"))
    features = validate_source(source)
    write_geometry(source, features, args.output_root, args.production_base_sha)


if __name__ == "__main__":
    main()
