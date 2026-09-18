from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _function_body(text: str, name: str, next_name: str) -> str:
    start = text.index(f"func {name}")
    end = text.index(f"\nfunc {next_name}", start)
    return text[start:end]


def test_runtime_index_verifies_source_bytes_before_registration() -> None:
    text = RUNTIME.read_text(encoding="utf-8")
    loader = _function_body(text, "_load_runtime_index() -> bool:", "runtime_index_road_count()")

    digest_read = "var actual_sha := FileAccess.get_sha256(source_path).to_lower()"
    digest_guard = "if actual_sha.is_empty() or actual_sha != expected_sha:\n            return false"
    source_stage = "staged_source_sha_by_path[source_path] = expected_sha"
    road_stage = "staged_road_source_path_by_id[osm_id] = source_path"
    source_publish = "_source_sha_by_path = staged_source_sha_by_path"
    road_publish = "_road_source_path_by_id = staged_road_source_path_by_id"

    assert loader.count(digest_read) == 1, (
        "runtime-index registration must hash every canonical source document exactly once; "
        "a digest check deferred to _source_bundle_by_id() is too late"
    )
    assert loader.count(digest_guard) == 1, (
        "runtime-index registration must fail closed when source bytes are missing or stale"
    )

    read_pos = loader.index(digest_read)
    guard_pos = loader.index(digest_guard)
    source_stage_pos = loader.index(source_stage)
    road_stage_pos = loader.index(road_stage)
    source_publish_pos = loader.index(source_publish)
    road_publish_pos = loader.index(road_publish)

    assert read_pos < guard_pos < source_stage_pos
    assert guard_pos < road_stage_pos
    assert guard_pos < source_publish_pos
    assert guard_pos < road_publish_pos


def test_per_road_lookup_keeps_defense_in_depth_digest_check() -> None:
    text = RUNTIME.read_text(encoding="utf-8")
    lookup = _function_body(text, "_source_bundle_by_id(osm_id: int) -> Dictionary:", "_exact_source_point_2d(raw: Variant) -> Variant:")

    assert lookup.count("var actual_sha := FileAccess.get_sha256(path).to_lower()") == 1
    assert lookup.count("if expected_sha.is_empty() or actual_sha.is_empty() or actual_sha != expected_sha:\n        return {}") == 1
