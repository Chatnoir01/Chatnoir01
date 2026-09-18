from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _loader() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _load_runtime_index() -> bool:")
    end = text.index("\nfunc runtime_index_road_count()", start)
    return text[start:end]


def test_runtime_index_rejects_unknown_document_descriptor_keys_before_registration() -> None:
    body = _loader()
    descriptor = "var descriptor := raw_document as Dictionary"
    source_path = 'var source_path := _canonical_runtime_source_path(descriptor.get("path", ""))'
    staged_source_write = "staged_source_sha_by_path[source_path] = expected_sha"
    staged_road_write = "staged_road_source_path_by_id[osm_id] = source_path"
    allowed = (
        'var allowed_document_keys := {\n'
        '            "path": true,\n'
        '            "sha256": true,\n'
        '            "road_ids": true,\n'
        '        }'
    )
    rejection = (
        'for raw_key: Variant in descriptor.keys():\n'
        '            if typeof(raw_key) != TYPE_STRING or not allowed_document_keys.has(str(raw_key)):\n'
        '                return false'
    )

    for label, marker in (
        ("document descriptor binding", descriptor),
        ("closed document keyset", allowed),
        ("document unknown-key rejection", rejection),
        ("source path interpretation", source_path),
        ("staged source registration", staged_source_write),
        ("staged road registration", staged_road_write),
    ):
        assert marker in body, f"missing runtime-index document boundary: {label}"
        assert body.count(marker) == 1, f"{label} must have one canonical boundary"

    assert (
        body.index(descriptor)
        < body.index(allowed)
        < body.index(rejection)
        < body.index(source_path)
        < body.index(staged_source_write)
        < body.index(staged_road_write)
    ), "reject unknown/non-string document keys before interpreting or staging descriptor content"
