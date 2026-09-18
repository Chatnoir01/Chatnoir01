from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def test_runtime_index_authenticates_source_bytes_before_any_staging_or_publication() -> None:
    """A stale/tampered source must never enter the canonical runtime-index maps."""
    text = SCRIPT.read_text(encoding="utf-8")
    loader = text.split("func _load_runtime_index() -> bool:", 1)[1].split(
        "func runtime_index_road_count() -> int:", 1
    )[0]

    source_path_guard = 'if not FileAccess.file_exists(source_path):'
    digest_read = 'var actual_sha := FileAccess.get_sha256(source_path).to_lower()'
    digest_guard = 'if actual_sha.is_empty() or actual_sha != expected_sha:'
    stage_digest = 'staged_source_sha_by_path[source_path] = actual_sha'
    stage_road = 'staged_road_source_path_by_id[osm_id] = source_path'
    publish_digest = '_source_sha_by_path = staged_source_sha_by_path'
    publish_road = '_road_source_path_by_id = staged_road_source_path_by_id'

    for needle in (
        source_path_guard,
        digest_read,
        digest_guard,
        stage_digest,
        stage_road,
        publish_digest,
        publish_road,
    ):
        assert needle in loader, f"missing fail-closed runtime-index source-auth step: {needle}"

    assert loader.index(source_path_guard) < loader.index(digest_read)
    assert loader.index(digest_read) < loader.index(digest_guard)
    assert loader.index(digest_guard) < loader.index(stage_digest)
    assert loader.index(digest_guard) < loader.index(stage_road)
    assert loader.index(stage_digest) < loader.index(publish_digest)
    assert loader.index(stage_road) < loader.index(publish_road)

    # The staged authority must be the digest computed from authenticated bytes,
    # not a second copy of the descriptor's declaration.
    assert 'staged_source_sha_by_path[source_path] = expected_sha' not in loader


def test_runtime_index_does_not_rely_on_lazy_lookup_for_source_authentication() -> None:
    """Defense-in-depth lookup hashing cannot substitute for load-time authentication."""
    text = SCRIPT.read_text(encoding="utf-8")
    loader = text.split("func _load_runtime_index() -> bool:", 1)[1].split(
        "func runtime_index_road_count() -> int:", 1
    )[0]
    lookup = text.split("func _source_bundle_by_id(osm_id: int) -> Dictionary:", 1)[1]

    assert "FileAccess.get_sha256(source_path)" in loader
    assert "FileAccess.get_sha256(path)" in lookup
