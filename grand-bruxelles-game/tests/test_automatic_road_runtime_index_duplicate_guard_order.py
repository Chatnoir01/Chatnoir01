from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _load_runtime_index_body() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _load_runtime_index() -> bool:")
    end = text.index("\nfunc runtime_index_road_count()", start)
    return text[start:end]


def test_duplicate_source_path_guard_precedes_descriptor_registration() -> None:
    """Duplicate document identity must fail before transaction-local authority stages."""
    body = _load_runtime_index_body()
    guard = "if staged_source_sha_by_path.has(source_path):\n            return false"
    assert guard in body, (
        "duplicate canonical source_path must fail closed against transaction-local staging"
    )
    guard_at = body.index(guard)
    sha_write_at = body.index("staged_source_sha_by_path[source_path]")
    road_write_at = body.index("staged_road_source_path_by_id[osm_id] = source_path")
    assert guard_at < sha_write_at < road_write_at, (
        "duplicate descriptor rejection must happen before staged source or road authority registration"
    )

    assert "if _source_sha_by_path.has(source_path):" not in body, (
        "descriptor validation must not consult canonical source authority before atomic publication"
    )


def test_duplicate_guard_is_not_digest_conditional() -> None:
    """Same-digest aliases are still duplicate descriptor authorities."""
    body = _load_runtime_index_body()
    guard_line = "if staged_source_sha_by_path.has(source_path):"
    assert guard_line in body
    line = next(line.strip() for line in body.splitlines() if guard_line in line)
    assert "expected_sha" not in line and "actual_sha" not in line and "!=" not in line and "==" not in line, (
        "duplicate path rejection must not depend on whether repeated digests match"
    )
