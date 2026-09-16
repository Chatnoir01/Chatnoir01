from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


EXPECTED_SOURCE_ONLY_KEYS = (
    "source_lookup_only",
    "render_authorized",
    "collision_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
    "jouable_authorized",
    "destination_advertisable",
)


def _loader_body() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _load_runtime_index() -> bool:")
    end = text.index("\nfunc runtime_index_road_count()", start)
    return text[start:end]


def test_runtime_index_rejects_unknown_authorization_keys_before_documents() -> None:
    """Unknown authority rails must fail closed instead of being silently ignored."""
    body = _loader_body()
    marker = "authorization.keys()"
    assert marker in body, (
        "runtime loader never validates the authorization key set; an unknown future authority rail "
        "could be silently ignored while the source-only index is accepted"
    )
    assert body.index(marker) < body.index("var documents: Variant"), (
        "authorization key-set validation must complete before any runtime-index document registration"
    )


def test_runtime_index_authorization_schema_is_explicit_and_complete() -> None:
    """The source-only loader must enumerate every authority it understands, including advertising."""
    body = _loader_body()
    for key in EXPECTED_SOURCE_ONLY_KEYS:
        assert body.count(f'"{key}"') >= 1, f"loader authority schema omits {key}"
    assert "allowed_authorization_keys" in body, (
        "unknown-key rejection must be driven by an explicit source-only allowlist rather than an "
        "open-ended or partial key check"
    )
    assert body.index("allowed_authorization_keys") < body.index("authorization.keys()") < body.index("var documents: Variant")


def test_unknown_authority_rejection_precedes_all_authority_map_mutation() -> None:
    """No document/source/road registration may happen before the key-set boundary closes."""
    body = _loader_body()
    marker = "authorization.keys()"
    assert marker in body
    for mutation in (
        "_source_sha_by_path[source_path] = expected_sha",
        "_road_source_path_by_id[osm_id] = source_path",
        "_runtime_index_valid = not _road_source_path_by_id.is_empty()",
    ):
        assert mutation in body
        assert body.index(marker) < body.index(mutation), (
            f"unknown authorization keys must fail before runtime authority mutation: {mutation}"
        )
