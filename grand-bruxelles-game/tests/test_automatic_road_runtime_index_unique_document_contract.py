from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def test_runtime_index_rejects_duplicate_source_document_descriptors() -> None:
    """One canonical source document must have exactly one runtime-index descriptor.

    Repeating a path, even with the same digest and disjoint road IDs, creates two
    textual authorities for one source bundle and makes descriptor cardinality
    diverge from runtime_index_source_document_count(). Fail closed instead.
    """
    text = RUNTIME.read_text(encoding="utf-8")
    required_guard = "if _source_sha_by_path.has(source_path):\n            return false"
    assert required_guard in text, (
        "automatic road runtime index accepts duplicate source document descriptors; "
        "reject any repeated canonical source_path before registering its roads"
    )
