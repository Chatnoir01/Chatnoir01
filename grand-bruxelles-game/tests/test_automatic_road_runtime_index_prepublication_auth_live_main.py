from pathlib import Path

ROOT = Path(__file__).parents[1]
RESOLVER = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _loader_body() -> str:
    source = RESOLVER.read_text(encoding="utf-8")
    start = source.index("func _load_runtime_index() -> bool:")
    end = source.index("\n\nfunc runtime_index_road_count()", start)
    return source[start:end]


def test_runtime_index_authenticates_source_bytes_before_canonical_publication() -> None:
    body = _loader_body()
    assert "var staged_road_source_path_by_id" in body
    assert "var staged_source_sha_by_path" in body
    assert "FileAccess.file_exists(source_path)" in body
    assert "FileAccess.get_sha256(source_path).to_lower()" in body
    assert "actual_sha != expected_sha" in body
    assert "staged_source_sha_by_path[source_path] = actual_sha" in body
    assert "staged_road_source_path_by_id[osm_id] = source_path" in body

    duplicate_source = body.index("staged_source_sha_by_path.has(source_path)")
    source_exists = body.index("FileAccess.file_exists(source_path)")
    hash_source = body.index("FileAccess.get_sha256(source_path).to_lower()")
    validate_sha = body.index("actual_sha != expected_sha")
    stage_sha = body.index("staged_source_sha_by_path[source_path] = actual_sha")
    duplicate_road = body.index("staged_road_source_path_by_id.has(osm_id)")
    stage_road = body.index("staged_road_source_path_by_id[osm_id] = source_path")
    publish_source = body.index("_source_sha_by_path = staged_source_sha_by_path")
    publish_roads = body.index("_road_source_path_by_id = staged_road_source_path_by_id")

    assert duplicate_source < source_exists < hash_source < validate_sha < stage_sha
    assert stage_sha < duplicate_road < stage_road
    assert stage_sha < publish_source
    assert stage_road < publish_roads
    assert body.count("_source_sha_by_path = staged_source_sha_by_path") == 1
    assert body.count("_road_source_path_by_id = staged_road_source_path_by_id") == 1
    assert "_source_sha_by_path[source_path] = expected_sha" not in body
    assert "_road_source_path_by_id[osm_id] = source_path" not in body
    valid = body.index("_runtime_index_valid = true")
    assert publish_source < valid and publish_roads < valid
