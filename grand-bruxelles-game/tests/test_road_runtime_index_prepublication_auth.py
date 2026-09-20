from pathlib import Path

RESOLVER = Path("game/scripts/automatic_road_direct_spawn.gd")


def _loader_body() -> str:
    text = RESOLVER.read_text(encoding="utf-8")
    start = text.index("func _load_runtime_index() -> bool:")
    end = text.index("\n\nfunc runtime_index_road_count()", start)
    return text[start:end]


def test_runtime_index_authenticates_physical_source_before_publication() -> None:
    body = _loader_body()

    # Catalog descriptors are authority candidates only. Physical source bytes must
    # be authenticated into transaction-local maps before either canonical lookup
    # map is published; otherwise a later descriptor failure leaves partial authority.
    assert "var staged_source_sha_by_path" in body
    assert "var staged_road_source_path_by_id" in body
    assert "FileAccess.file_exists(source_path)" in body
    assert "var actual_sha := FileAccess.get_sha256(source_path).to_lower()" in body
    assert "actual_sha != expected_sha" in body
    assert "staged_source_sha_by_path[source_path] = actual_sha" in body
    assert "staged_road_source_path_by_id[osm_id] = source_path" in body

    publish_source = body.index("_source_sha_by_path = staged_source_sha_by_path")
    publish_roads = body.index("_road_source_path_by_id = staged_road_source_path_by_id")
    validate = body.index("var actual_sha := FileAccess.get_sha256(source_path).to_lower()")
    assert validate < publish_source
    assert validate < publish_roads

    # Descriptor SHA must never be published directly as authenticated authority.
    assert "_source_sha_by_path[source_path] = expected_sha" not in body
    assert "_road_source_path_by_id[osm_id] = source_path" not in body
