from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _source_path_helper() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _canonical_runtime_source_path(raw_path: Variant) -> String:")
    end = text.index("\nfunc _canonical_sha256", start)
    return text[start:end]


def test_runtime_index_source_path_has_one_generator_canonical_spelling() -> None:
    body = _source_path_helper()

    # build_road_runtime_index.py serializes repository-relative data/osm/*.game.json
    # paths. Accepting an optional res:// prefix would give one source document two
    # textual authorities before canonicalization, weakening deterministic provenance.
    raw_binding = "var raw_source_path := str(raw_path)"
    reject_res_prefix = 'if raw_source_path.begins_with("res://"):\n        return ""'
    backslash_rejection = 'if raw_source_path.contains("\\\\"):'
    canonical_scope = 'if not source_path.begins_with("data/osm/"):'
    final_return = 'return "res://" + "/".join(segments)'

    for label, marker in (
        ("raw path binding", raw_binding),
        ("raw res-prefix rejection", reject_res_prefix),
        ("raw backslash rejection", backslash_rejection),
        ("canonical OSM scope", canonical_scope),
        ("canonical resource return", final_return),
    ):
        assert marker in body, f"missing single-spelling source-path boundary: {label}"
        assert body.count(marker) == 1, f"{label} must have one canonical boundary"

    assert (
        body.index(raw_binding)
        < body.index(reject_res_prefix)
        < body.index(backslash_rejection)
        < body.index(canonical_scope)
        < body.index(final_return)
    ), "reject alternate res:// spelling before canonical source-path normalization"

    assert 'if source_path.begins_with("res://"):' not in body, (
        "runtime index must not accept both repository-relative and res:// spellings"
    )
