from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "game" / "scripts" / "automatic_road_direct_spawn.gd"

def _loader_body() -> str:
    source = SCRIPT.read_text(encoding="utf-8")
    start = source.index("func _load_runtime_index() -> bool:")
    end = source.index("\n\nfunc runtime_index_road_count()", start)
    return source[start:end]

def test_runtime_index_declares_transaction_local_authority_before_descriptor_validation() -> None:
    body = _loader_body()
    staged_roads = body.index("var staged_road_source_path_by_id: Dictionary = {}")
    staged_sha = body.index("var staged_source_sha_by_path: Dictionary = {}")
    descriptor_loop = body.index("for raw_document: Variant in documents:")
    assert staged_roads < descriptor_loop
    assert staged_sha < descriptor_loop

def test_runtime_index_authenticates_source_bytes_before_staging_authority() -> None:
    body = _loader_body()
    duplicate_guard = body.index("if staged_source_sha_by_path.has(source_path):")
    existence_guard = body.index("if not FileAccess.file_exists(source_path):")
    digest_read = body.index("var actual_sha := FileAccess.get_sha256(source_path).to_lower()")
    digest_match = body.index("if actual_sha.is_empty() or actual_sha != expected_sha:")
    digest_stage = body.index("staged_source_sha_by_path[source_path] = actual_sha")
    road_stage = body.index("staged_road_source_path_by_id[osm_id] = source_path")
    assert duplicate_guard < existence_guard < digest_read < digest_match < digest_stage < road_stage
    assert "staged_source_sha_by_path[source_path] = expected_sha" not in body
    assert "_source_sha_by_path[source_path] = expected_sha" not in body

def test_runtime_index_rejects_duplicates_inside_transaction_local_maps() -> None:
    body = _loader_body()
    source_guard = body.index("if staged_source_sha_by_path.has(source_path):")
    source_stage = body.index("staged_source_sha_by_path[source_path] = actual_sha")
    road_loop = body.index("for raw_id: Variant in road_ids:")
    road_guard = body.index("if osm_id <= 0 or staged_road_source_path_by_id.has(osm_id):")
    road_stage = body.index("staged_road_source_path_by_id[osm_id] = source_path")
    assert source_guard < source_stage < road_loop < road_guard < road_stage
    assert "if _source_sha_by_path.has(source_path):" not in body
    assert "if osm_id <= 0 or _road_source_path_by_id.has(osm_id):" not in body

def test_runtime_index_publishes_only_after_all_descriptors_validate() -> None:
    body = _loader_body()
    loop = body.index("for raw_document: Variant in documents:")
    nonempty_guard = body.index("if staged_road_source_path_by_id.is_empty():")
    publish_roads = body.index("_road_source_path_by_id = staged_road_source_path_by_id")
    publish_sha = body.index("_source_sha_by_path = staged_source_sha_by_path")
    descriptor_loop = body[loop:nonempty_guard]
    assert "_road_source_path_by_id[" not in descriptor_loop
    assert "_source_sha_by_path[" not in descriptor_loop
    assert loop < nonempty_guard < publish_roads < publish_sha
    assert body.count("_road_source_path_by_id = staged_road_source_path_by_id") == 1
    assert body.count("_source_sha_by_path = staged_source_sha_by_path") == 1

def test_runtime_index_failure_cannot_publish_partial_descriptor_authority() -> None:
    body = _loader_body()
    clear_roads = body.index("_road_source_path_by_id.clear()")
    clear_sha = body.index("_source_sha_by_path.clear()")
    loop = body.index("for raw_document: Variant in documents:")
    nonempty_guard = body.index("if staged_road_source_path_by_id.is_empty():")
    publish_roads = body.index("_road_source_path_by_id = staged_road_source_path_by_id")
    publish_sha = body.index("_source_sha_by_path = staged_source_sha_by_path")
    assert clear_roads < loop
    assert clear_sha < loop
    assert nonempty_guard < publish_roads
    assert nonempty_guard < publish_sha
    assert body[loop:nonempty_guard].count("return false") >= 4
