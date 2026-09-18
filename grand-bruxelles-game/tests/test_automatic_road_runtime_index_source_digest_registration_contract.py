import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"
RUNTIME_INDEX = ROOT / "data" / "runtime" / "road_destination_runtime_index.json"


def _function_body(text: str, name: str, next_name: str) -> str:
    start = text.index(f"func {name}")
    end = text.index(f"\nfunc {next_name}", start)
    return text[start:end]


def test_runtime_index_locked_source_bytes_match_declared_sha256() -> None:
    index = json.loads(RUNTIME_INDEX.read_text(encoding="utf-8"))
    documents = index["documents"]
    assert documents, "runtime index must contain at least one locked source document"

    seen_paths: set[str] = set()
    seen_road_ids: set[int] = set()
    for descriptor in documents:
        source_rel = descriptor["path"]
        expected_sha = descriptor["sha256"]
        road_ids = descriptor["road_ids"]

        assert source_rel not in seen_paths, f"duplicate runtime-index source path: {source_rel}"
        seen_paths.add(source_rel)
        source_path = ROOT / source_rel
        assert source_path.is_file(), f"locked runtime-index source is missing: {source_rel}"
        actual_sha = hashlib.sha256(source_path.read_bytes()).hexdigest()
        assert actual_sha == expected_sha, (
            f"locked runtime-index source bytes drifted for {source_rel}: "
            f"expected {expected_sha}, got {actual_sha}"
        )

        assert road_ids, f"locked runtime-index source has no road ids: {source_rel}"
        for road_id in road_ids:
            assert isinstance(road_id, int) and not isinstance(road_id, bool) and road_id > 0
            assert road_id not in seen_road_ids, f"road id {road_id} is assigned to multiple source documents"
            seen_road_ids.add(road_id)


def test_runtime_index_verifies_source_bytes_before_registration() -> None:
    text = RUNTIME.read_text(encoding="utf-8")
    loader = _function_body(text, "_load_runtime_index() -> bool:", "runtime_index_road_count()")

    existence_guard = "if not FileAccess.file_exists(source_path):\n            return false"
    digest_read = "var actual_sha := FileAccess.get_sha256(source_path).to_lower()"
    digest_guard = "if actual_sha.is_empty() or actual_sha != expected_sha:\n            return false"
    source_stage = "staged_source_sha_by_path[source_path] = actual_sha"
    forbidden_declared_stage = "staged_source_sha_by_path[source_path] = expected_sha"
    road_id_intake = "for raw_id: Variant in road_ids:"
    road_stage = "staged_road_source_path_by_id[osm_id] = source_path"
    source_publish = "_source_sha_by_path = staged_source_sha_by_path"
    road_publish = "_road_source_path_by_id = staged_road_source_path_by_id"

    assert loader.count(existence_guard) == 1, (
        "runtime-index registration must reject a missing canonical source before hashing or staging it"
    )
    assert loader.count(digest_read) == 1, (
        "runtime-index registration must hash every canonical source document exactly once; "
        "a digest check deferred to _source_bundle_by_id() is too late"
    )
    assert loader.count(digest_guard) == 1, (
        "runtime-index registration must fail closed when source bytes are missing or stale"
    )
    assert loader.count(source_stage) == 1, (
        "runtime-index registration must stage the digest derived from verified source bytes, "
        "not merely copy the catalog-declared digest"
    )
    assert forbidden_declared_stage not in loader, (
        "runtime-index registration must never stage descriptor-provided expected_sha as authority; "
        "only the digest computed from authenticated source bytes may be published"
    )
    assert loader.count(road_id_intake) == 1, (
        "runtime-index registration must have one deterministic road-id intake loop per descriptor"
    )

    existence_pos = loader.index(existence_guard)
    read_pos = loader.index(digest_read)
    guard_pos = loader.index(digest_guard)
    source_stage_pos = loader.index(source_stage)
    road_id_intake_pos = loader.index(road_id_intake)
    road_stage_pos = loader.index(road_stage)
    source_publish_pos = loader.index(source_publish)
    road_publish_pos = loader.index(road_publish)

    assert existence_pos < read_pos < guard_pos < source_stage_pos
    assert guard_pos < road_id_intake_pos < road_stage_pos
    assert guard_pos < source_publish_pos
    assert guard_pos < road_publish_pos


def test_per_road_lookup_keeps_defense_in_depth_digest_check() -> None:
    text = RUNTIME.read_text(encoding="utf-8")
    lookup = _function_body(text, "_source_bundle_by_id(osm_id: int) -> Dictionary:", "_exact_source_point_2d(raw: Variant) -> Variant:")

    assert lookup.count("var actual_sha := FileAccess.get_sha256(path).to_lower()") == 1
    assert lookup.count("if expected_sha.is_empty() or actual_sha.is_empty() or actual_sha != expected_sha:\n        return {}") == 1
