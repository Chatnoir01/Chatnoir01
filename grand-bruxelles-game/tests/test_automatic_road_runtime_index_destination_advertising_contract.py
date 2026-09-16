from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _load_runtime_index_body() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _load_runtime_index() -> bool:")
    end = text.index("\nfunc runtime_index_road_count()", start)
    return text[start:end]


def test_source_lookup_index_rejects_destination_advertising_authority() -> None:
    """A source-lookup-only index must never be accepted as destination-advertisable."""
    body = _load_runtime_index_body()
    assert '"destination_advertisable"' in body, (
        "runtime index loader does not fail closed on destination_advertisable; "
        "a source-lookup-only manifest can claim advertising authority without invalidating the index"
    )
    assert 'bool(auth.get("destination_advertisable", true))' in body, (
        "destination advertising must be explicitly false, not merely absent or ignored"
    )


def test_destination_advertising_guard_precedes_document_registration() -> None:
    """Authorization must fail before any source/road authority map can mutate."""
    body = _load_runtime_index_body()
    guard = 'if bool(auth.get("destination_advertisable", true)):\n        return false'
    assert guard in body
    assert body.index(guard) < body.index("var documents: Variant")
    assert body.index(guard) < body.index("_source_sha_by_path[source_path] = expected_sha")
