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
    body = _load_runtime_index_body()
    assert '"destination_advertisable"' in body
    assert 'auth.get("destination_advertisable", true)' in body


def test_destination_advertising_requires_exact_boolean_false() -> None:
    assert _strict_guard() in _load_runtime_index_body()


def test_destination_advertising_guard_precedes_document_registration() -> None:
    body = _load_runtime_index_body(); guard = _strict_guard()
    assert guard in body
    assert body.index(guard) < body.index("var documents: Variant")
    assert body.index(guard) < body.index("_source_sha_by_path[source_path] = expected_sha")


def test_destination_advertising_guard_is_separate_from_legacy_authorization_loop() -> None:
    body = _load_runtime_index_body()
    legacy_loop = 'for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:'
    guard = _strict_guard()
    assert legacy_loop in body and guard in body
    assert body.index(legacy_loop) < body.index(guard) < body.index("var documents: Variant")


def test_destination_advertising_guard_is_unique() -> None:
    assert _load_runtime_index_body().count(_strict_guard()) == 1


def test_destination_advertising_has_one_loader_semantic() -> None:
    assert _load_runtime_index_body().count('"destination_advertisable"') == 1


def test_destination_advertising_guard_runs_before_runtime_index_validity_can_be_set() -> None:
    body = _load_runtime_index_body(); guard = _strict_guard()
    valid_assignment = "_runtime_index_valid = not _road_source_path_by_id.is_empty()"
    assert guard in body and valid_assignment in body
    assert body.index(guard) < body.index(valid_assignment)


def test_current_source_only_index_omits_advertising_authority_as_negative_control() -> None:
    payload = json.loads(RUNTIME_INDEX.read_text(encoding="utf-8"))
    authorization = payload.get("authorization")
    assert isinstance(authorization, dict)
    assert authorization.get("source_lookup_only") is True
    assert "destination_advertisable" not in authorization


def test_current_source_only_authorization_flags_are_exact_booleans() -> None:
    payload = json.loads(RUNTIME_INDEX.read_text(encoding="utf-8"))
    authorization = payload.get("authorization")
    assert isinstance(authorization, dict)
    assert authorization.get("source_lookup_only") is True
    for key in ("render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"):
        assert key in authorization
        assert type(authorization[key]) is bool
        assert authorization[key] is False


def test_loader_rejects_coercible_legacy_authorization_values() -> None:
    body = _load_runtime_index_body()
    legacy_loop = 'for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:'
    assert legacy_loop in body
    assert 'var forbidden_value: Variant = auth.get(forbidden, true)' in body
    assert 'typeof(forbidden_value) != TYPE_BOOL or bool(forbidden_value)' in body


def test_loader_requires_exact_boolean_source_lookup_authority() -> None:
    body = _load_runtime_index_body()
    declaration = 'var source_lookup_only: Variant = auth.get("source_lookup_only", false)'
    assert declaration in body
    assert 'typeof(source_lookup_only) != TYPE_BOOL or not bool(source_lookup_only)' in body
    assert body.index(declaration) < body.index("var documents: Variant")


def test_loader_requires_exact_boolean_top_level_source_lookup_authority() -> None:
    body = _load_runtime_index_body()
    declaration = 'var index_source_lookup_only: Variant = index.get("source_lookup_only", false)'
    guard = 'typeof(index_source_lookup_only) != TYPE_BOOL or not bool(index_source_lookup_only)'
    assert declaration in body and guard in body
    assert body.index(declaration) < body.index('var authorization: Variant = index.get("authorization", {})')
