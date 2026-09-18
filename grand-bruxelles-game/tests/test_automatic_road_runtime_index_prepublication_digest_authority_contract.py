from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOADER = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def test_authenticated_digest_is_the_only_value_staged_before_publication() -> None:
    """The runtime index must publish authenticated bytes, never descriptor authority."""
    source = LOADER.read_text(encoding="utf-8")
    loader = source.split("func _load_runtime_index() -> bool:", 1)[1].split(
        "func runtime_index_road_count() -> int:", 1
    )[0]

    duplicate_guard = "if staged_source_sha_by_path.has(source_path):"
    existence_guard = "if not FileAccess.file_exists(source_path):"
    digest_read = "var actual_sha := FileAccess.get_sha256(source_path).to_lower()"
    digest_guard = "if actual_sha.is_empty() or actual_sha != expected_sha:"
    authenticated_stage = "staged_source_sha_by_path[source_path] = actual_sha"
    descriptor_stage = "staged_source_sha_by_path[source_path] = expected_sha"
    road_stage = "staged_road_source_path_by_id[osm_id] = source_path"
    publish_digest = "_source_sha_by_path = staged_source_sha_by_path"
    publish_road = "_road_source_path_by_id = staged_road_source_path_by_id"

    for needle in (
        duplicate_guard,
        existence_guard,
        digest_read,
        digest_guard,
        authenticated_stage,
        road_stage,
        publish_digest,
        publish_road,
    ):
        assert needle in loader, f"missing prepublication digest-authority step: {needle}"

    assert descriptor_stage not in loader, "descriptor SHA must never become runtime authority"
    assert loader.index(duplicate_guard) < loader.index(existence_guard)
    assert loader.index(existence_guard) < loader.index(digest_read)
    assert loader.index(digest_read) < loader.index(digest_guard)
    assert loader.index(digest_guard) < loader.index(authenticated_stage)
    assert loader.index(authenticated_stage) < loader.index(road_stage)
    assert loader.index(road_stage) < loader.index(publish_digest)
    assert loader.index(publish_digest) < loader.index(publish_road)
