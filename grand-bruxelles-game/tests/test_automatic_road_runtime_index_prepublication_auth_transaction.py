from pathlib import Path

ROOT = Path(__file__).parents[1]
RESOLVER = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _loader_body() -> str:
    source = RESOLVER.read_text(encoding="utf-8")
    start = source.index("func _load_runtime_index() -> bool:")
    end = source.index("\n\nfunc runtime_index_road_count()", start)
    return source[start:end]


def test_failed_validation_has_no_incremental_canonical_authority() -> None:
    body = _loader_body()
    assert "var staged_road_source_path_by_id" in body
    assert "var staged_source_sha_by_path" in body
    assert "staged_source_sha_by_path.has(source_path)" in body
    assert "staged_road_source_path_by_id.has(osm_id)" in body
    publish_source = "_source_sha_by_path = staged_source_sha_by_path"
    publish_roads = "_road_source_path_by_id = staged_road_source_path_by_id"
    assert body.count(publish_source) == 1
    assert body.count(publish_roads) == 1
    assert "_source_sha_by_path[source_path] =" not in body
    assert "_road_source_path_by_id[osm_id] =" not in body
    last_stage_source = body.rindex("staged_source_sha_by_path[source_path] = actual_sha")
    last_stage_road = body.rindex("staged_road_source_path_by_id[osm_id] = source_path")
    first_publish = min(body.index(publish_source), body.index(publish_roads))
    assert last_stage_source < first_publish
    assert last_stage_road < first_publish
    valid = body.index("_runtime_index_valid = true")
    assert body.index(publish_source) < valid
    assert body.index(publish_roads) < valid


def test_failed_validation_latches_empty_canonical_authority() -> None:
    body = _loader_body()
    attempted_guard = body.index("if _runtime_index_attempted:")
    attempted_set = body.index("_runtime_index_attempted = true")
    invalid_set = body.index("_runtime_index_valid = false")
    clear_roads = body.index("_road_source_path_by_id.clear()")
    clear_sources = body.index("_source_sha_by_path.clear()")
    parse_index = body.index("var index := _parse_document(RUNTIME_INDEX_PATH)")
    assert attempted_guard < attempted_set < invalid_set
    assert invalid_set < clear_roads < parse_index
    assert invalid_set < clear_sources < parse_index
    assert body.count("_runtime_index_valid = true") == 1
    publish_source = body.index("_source_sha_by_path = staged_source_sha_by_path")
    publish_roads = body.index("_road_source_path_by_id = staged_road_source_path_by_id")
    valid = body.index("_runtime_index_valid = true")
    assert publish_source < valid
    assert publish_roads < valid


def test_all_validation_failures_precede_atomic_publication() -> None:
    body = _loader_body()
    publish_source = body.index("_source_sha_by_path = staged_source_sha_by_path")
    publish_roads = body.index("_road_source_path_by_id = staged_road_source_path_by_id")
    first_publish = min(publish_source, publish_roads)
    last_failure = body.rindex("return false")
    assert last_failure < first_publish
    assert "if staged_road_source_path_by_id.is_empty():\n        return false" in body
    nonempty_guard = body.index("if staged_road_source_path_by_id.is_empty():")
    assert nonempty_guard < first_publish


def test_publication_is_terminal_success_path() -> None:
    body = _loader_body()
    publish_source = body.index("_source_sha_by_path = staged_source_sha_by_path")
    publish_roads = body.index("_road_source_path_by_id = staged_road_source_path_by_id")
    valid = body.index("_runtime_index_valid = true")
    success_return = body.rindex("return _runtime_index_valid")
    assert publish_source < valid < success_return
    assert publish_roads < valid < success_return
    tail = body[min(publish_source, publish_roads):]
    assert "return false" not in tail
