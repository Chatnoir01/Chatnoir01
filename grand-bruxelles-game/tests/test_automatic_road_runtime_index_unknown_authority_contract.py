from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"
EXPECTED_SOURCE_ONLY_KEYS = ("source_lookup_only", "render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized", "destination_advertisable")


def _loader_body() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _load_runtime_index() -> bool:")
    end = text.index("\nfunc runtime_index_road_count()", start)
    return text[start:end]


def test_runtime_index_rejects_unknown_authorization_keys_before_documents() -> None:
    body = _loader_body(); marker = "authorization.keys()"
    assert marker in body
    assert body.index(marker) < body.index("var documents: Variant")


def test_runtime_index_authorization_schema_is_explicit_and_complete() -> None:
    body = _loader_body()
    for key in EXPECTED_SOURCE_ONLY_KEYS:
        assert body.count(f'"{key}"') >= 1
    assert "allowed_authorization_keys" in body
    assert body.index("allowed_authorization_keys") < body.index("authorization.keys()") < body.index("var documents: Variant")


def test_unknown_authority_rejection_precedes_all_authority_map_mutation() -> None:
    body = _loader_body(); marker = "authorization.keys()"
    assert marker in body
    for mutation in ("_source_sha_by_path[source_path] = expected_sha", "_road_source_path_by_id[osm_id] = source_path", "_runtime_index_valid = not _road_source_path_by_id.is_empty()"):
        assert mutation in body
        assert body.index(marker) < body.index(mutation)
