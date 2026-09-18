from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _loader() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _load_runtime_index() -> bool:")
    end = text.index("\nfunc runtime_index_road_count()", start)
    return text[start:end]


def test_runtime_index_document_descriptor_is_exact_closed_schema() -> None:
    body = _loader()
    descriptor = "var descriptor := raw_document as Dictionary"
    allowed = (
        'var allowed_document_keys := {\n'
        '            "path": true,\n'
        '            "sha256": true,\n'
        '            "road_ids": true,\n'
        '        }'
    )
    exact_size = "if descriptor.size() != allowed_document_keys.size():\n            return false"
    rejection = (
        'for raw_key: Variant in descriptor.keys():\n'
        '            if typeof(raw_key) != TYPE_STRING or not allowed_document_keys.has(str(raw_key)):\n'
        '                return false'
    )
    source_path = 'var source_path := _canonical_runtime_source_path(descriptor.get("path", ""))'

    for label, marker in (
        ("document descriptor binding", descriptor),
        ("closed document keyset", allowed),
        ("exact document key count", exact_size),
        ("document unknown-key rejection", rejection),
        ("source path interpretation", source_path),
    ):
        assert marker in body, f"missing runtime-index document boundary: {label}"
        assert body.count(marker) == 1, f"{label} must have one canonical boundary"

    assert (
        body.index(descriptor)
        < body.index(allowed)
        < body.index(exact_size)
        < body.index(rejection)
        < body.index(source_path)
    ), "require exact closed descriptor schema before interpreting document content"
