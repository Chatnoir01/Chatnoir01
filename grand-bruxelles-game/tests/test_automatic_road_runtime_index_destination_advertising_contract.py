import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"
RUNTIME_INDEX = ROOT / "data" / "runtime" / "road_destination_runtime_index.json"


def _load_runtime_index_body() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _load_runtime_index() -> bool:")
    end = text.index("\nfunc runtime_index_road_count()", start)
    return text[start:end]


def _strict_guard() -> str:
    return (
        'var destination_advertisable: Variant = auth.get("destination_advertisable", true)\n'
        '    if typeof(destination_advertisable) != TYPE_BOOL or bool(destination_advertisable):\n'
        '        return false'
    )


def test_source_lookup_index_rejects_destination_advertising_authority() -> None:
    """A source-lookup-only index must never be accepted as destination-advertisable."""
    body = _load_runtime_index_body()
    assert '"destination_advertisable"' in body, (
        "runtime index loader does not fail closed on destination_advertisable; "
        "a source-lookup-only manifest can claim advertising authority without invalidating the index"
    )
    assert 'auth.get("destination_advertisable", true)' in body, (
        "destination advertising must default fail-closed when absent"
    )


def test_destination_advertising_requires_exact_boolean_false() -> None:
    """JSON numbers/strings/null must not coerce into authorization semantics."""
    body = _load_runtime_index_body()
    assert _strict_guard() in body, (
        "destination_advertisable must be an explicit JSON boolean false; coercible values such as 0, "
        "empty strings, or null must fail closed"
    )


def test_destination_advertising_guard_precedes_document_registration() -> None:
    """Authorization must fail before any source/road authority map can mutate."""
    body = _load_runtime_index_body()
    guard = _strict_guard()
    assert guard in body
    assert body.index(guard) < body.index("var documents: Variant")
    assert body.index(guard) < body.index("_source_sha_by_path[source_path] = expected_sha")


def test_destination_advertising_guard_is_separate_from_legacy_authorization_loop() -> None:
    """Keep advertising promotion explicit rather than silently widening the legacy authority list."""
    body = _load_runtime_index_body()
    legacy_loop = 'for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:'
    guard = _strict_guard()
    assert legacy_loop in body
    assert guard in body
    assert body.index(legacy_loop) < body.index(guard) < body.index("var documents: Variant")


def test_destination_advertising_guard_is_unique() -> None:
    """One explicit promotion boundary avoids ambiguous duplicate guards or dead copies."""
    body = _load_runtime_index_body()
    guard = _strict_guard()
    assert body.count(guard) == 1, "destination advertising guard must exist exactly once in the loader"


def test_destination_advertising_has_one_loader_semantic() -> None:
    """No alternate default or dead advertising read may coexist with the canonical fail-closed guard."""
    body = _load_runtime_index_body()
    assert body.count('"destination_advertisable"') == 1, (
        "loader must have exactly one destination_advertisable read; alternate defaults or dead reads "
        "would make the promotion boundary ambiguous"
    )


def test_destination_advertising_guard_runs_before_runtime_index_validity_can_be_set() -> None:
    """Promotion authorization must be resolved before the loader can ever mark the index valid."""
    body = _load_runtime_index_body()
    guard = _strict_guard()
    valid_assignment = "_runtime_index_valid = not _road_source_path_by_id.is_empty()"
    assert guard in body
    assert valid_assignment in body
    assert body.index(guard) < body.index(valid_assignment), (
        "destination advertising guard must execute before runtime index validity can become true"
    )


def test_current_source_only_index_omits_advertising_authority_as_negative_control() -> None:
    """Do not repair the defect by editing current data; loader absence semantics must stay fail-closed."""
    payload = json.loads(RUNTIME_INDEX.read_text(encoding="utf-8"))
    authorization = payload.get("authorization")
    assert isinstance(authorization, dict)
    assert authorization.get("source_lookup_only") is True
    assert "destination_advertisable" not in authorization, (
        "current source-only data must remain an absence negative-control; "
        "the runtime loader, not a data rewrite, owns fail-closed default semantics"
    )


def test_current_source_only_authorization_flags_are_exact_booleans() -> None:
    """The negative-control manifest must not hide coercible authorization values."""
    payload = json.loads(RUNTIME_INDEX.read_text(encoding="utf-8"))
    authorization = payload.get("authorization")
    assert isinstance(authorization, dict)
    assert authorization.get("source_lookup_only") is True
    for key in (
        "render_authorized",
        "collision_authorized",
        "runtime_mount_authorized",
        "safe_spawn_authorized",
        "jouable_authorized",
    ):
        assert key in authorization, f"missing explicit source-only authorization flag: {key}"
        assert type(authorization[key]) is bool, f"{key} must be an exact JSON boolean"
        assert authorization[key] is False, f"{key} must remain false in source-lookup-only data"
