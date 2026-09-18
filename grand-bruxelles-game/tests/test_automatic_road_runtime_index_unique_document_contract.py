from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def test_runtime_index_rejects_duplicate_source_document_descriptors() -> None:
    """One canonical source document must have exactly one staged descriptor.

    Repeating a path, even with the same digest and disjoint road IDs, creates two
    textual authorities for one source bundle. The duplicate check must happen
    against transaction-local staging so failed validation cannot consult or mutate
    canonical runtime state before the final atomic publish.
    """
    text = RUNTIME.read_text(encoding="utf-8")
    required_guard = "if staged_source_sha_by_path.has(source_path):\n            return false"
    assert required_guard in text, (
        "automatic road runtime index accepts duplicate source document descriptors; "
        "reject any repeated canonical source_path in transaction-local staging before "
        "registering its roads or publishing canonical runtime maps"
    )

    canonical_guard = "if _source_sha_by_path.has(source_path):\n            return false"
    assert canonical_guard not in text, (
        "duplicate descriptor validation must not consult canonical runtime state; "
        "use transaction-local staging until the full index validates"
    )
