from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _loader() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _load_runtime_index() -> bool:")
    end = text.index("\nfunc runtime_index_road_count()", start)
    return text[start:end]


def test_runtime_index_registration_is_transactional_until_full_validation() -> None:
    body = _loader()

    documents = body.index("var documents: Variant")
    valid_promotion = body.index("_runtime_index_valid = not _road_source_path_by_id.is_empty()")

    attempted_guard = "if _runtime_index_attempted:"
    attempted_commit = "_runtime_index_attempted = true"
    invalid_default = "_runtime_index_valid = false"
    clear_roads = "_road_source_path_by_id.clear()"
    clear_sources = "_source_sha_by_path.clear()"
    parse_index = "var index := _parse_document(RUNTIME_INDEX_PATH)"

    for label, token in (
        ("attempted guard", attempted_guard),
        ("attempt marker", attempted_commit),
        ("invalid default", invalid_default),
        ("road-map reset", clear_roads),
        ("source-map reset", clear_sources),
        ("index parse", parse_index),
    ):
        assert body.count(token) == 1, f"{label} must have one canonical boundary"

    assert body.index(attempted_guard) < body.index(attempted_commit)
    assert body.index(attempted_commit) < body.index(invalid_default)
    assert body.index(invalid_default) < body.index(clear_roads) < body.index(parse_index)
    assert body.index(invalid_default) < body.index(clear_sources) < body.index(parse_index)

    staged_sources = "var staged_source_sha_by_path: Dictionary = {}"
    staged_roads = "var staged_road_source_path_by_id: Dictionary = {}"
    staged_source_duplicate_check = "staged_source_sha_by_path.has(source_path)"
    staged_road_duplicate_check = "staged_road_source_path_by_id.has(osm_id)"
    staged_source_write = "staged_source_sha_by_path[source_path] = actual_sha"
    staged_road_write = "staged_road_source_path_by_id[osm_id] = source_path"
    commit_sources = "_source_sha_by_path = staged_source_sha_by_path"
    commit_roads = "_road_source_path_by_id = staged_road_source_path_by_id"

    for label, token in (
        ("staged source map", staged_sources),
        ("staged road map", staged_roads),
        ("staged source duplicate check", staged_source_duplicate_check),
        ("staged road duplicate check", staged_road_duplicate_check),
        ("verified source registration", staged_source_write),
        ("staged road registration", staged_road_write),
        ("source-map commit", commit_sources),
        ("road-map commit", commit_roads),
    ):
        assert token in body, f"missing transactional runtime-index boundary: {label}"
        assert body.count(token) == 1, f"{label} must have one canonical mutation point"

    staged_sources_decl = body.index(staged_sources)
    staged_roads_decl = body.index(staged_roads)
    source_duplicate_check = body.index(staged_source_duplicate_check)
    road_duplicate_check = body.index(staged_road_duplicate_check)
    source_write = body.index(staged_source_write)
    road_write = body.index(staged_road_write)
    source_commit = body.index(commit_sources)
    road_commit = body.index(commit_roads)

    parse_pos = body.index(parse_index)
    assert parse_pos < staged_sources_decl < documents
    assert parse_pos < staged_roads_decl < documents
    assert staged_sources_decl < source_duplicate_check
    assert staged_roads_decl < road_duplicate_check

    assert documents < source_duplicate_check < source_write < source_commit < valid_promotion
    assert documents < road_duplicate_check < road_write < road_commit < valid_promotion
    assert source_write < road_commit, "road map must commit only after all source staging mutations"
    assert road_write < source_commit, "source map must commit only after all road staging mutations"

    source_commit_line = next(line for line in body.splitlines() if commit_sources in line)
    road_commit_line = next(line for line in body.splitlines() if commit_roads in line)
    assert source_commit_line == "    " + commit_sources
    assert road_commit_line == "    " + commit_roads

    assert "_source_sha_by_path.has(source_path)" not in body
    assert "_road_source_path_by_id.has(osm_id)" not in body
    assert "_source_sha_by_path[source_path] = expected_sha" not in body
    assert "_road_source_path_by_id[osm_id] = source_path" not in body
    assert "staged_source_sha_by_path[source_path] = expected_sha" not in body, (
        "descriptor digest must not become staged runtime authority; only authenticated bytes may be staged"
    )

    nonempty_guard = "if staged_road_source_path_by_id.is_empty():\n        return false"
    assert nonempty_guard in body, "empty staged runtime index must fail before canonical publication"
    assert body.count(nonempty_guard) == 1, "staged nonempty guard must have one canonical boundary"
    guard_pos = body.index(nonempty_guard)
    assert road_write < guard_pos < source_commit
    assert road_write < guard_pos < road_commit

    # A descriptor's declared SHA is only a comparison target. Runtime authority
    # must be derived from the bytes that were actually authenticated before either
    # canonical lookup map is published.
    source_exists_guard = "if not FileAccess.file_exists(source_path):\n            return false"
    source_digest_read = "var actual_sha := FileAccess.get_sha256(source_path).to_lower()"
    source_digest_guard = "if actual_sha.is_empty() or actual_sha != expected_sha:\n            return false"
    assert body.count(source_exists_guard) == 1, "runtime-index load must require the canonical source document before hashing"
    assert body.count(source_digest_read) == 1, "runtime-index load must hash each canonical source document exactly once"
    assert body.count(source_digest_guard) == 1, "runtime-index load must compare source bytes to the descriptor digest and fail closed"
    exists_pos = body.index(source_exists_guard)
    digest_read_pos = body.index(source_digest_read)
    digest_guard_pos = body.index(source_digest_guard)
    assert documents < source_duplicate_check < exists_pos < digest_read_pos < digest_guard_pos < source_write, (
        "duplicate rejection and source-byte authentication must complete before verified digest staging"
    )
    assert digest_guard_pos < source_commit and digest_guard_pos < road_commit, (
        "source digest comparison must complete before canonical publication"
    )
