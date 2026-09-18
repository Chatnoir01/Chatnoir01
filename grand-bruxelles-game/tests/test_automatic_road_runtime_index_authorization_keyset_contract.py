from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _loader() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _load_runtime_index() -> bool:")
    end = text.index("\nfunc runtime_index_road_count()", start)
    return text[start:end]


def test_runtime_index_rejects_unknown_authorization_keys_before_documents() -> None:
    body = _loader()
    documents = body.index("var documents: Variant")
    auth_binding = "var auth := authorization as Dictionary"
    auth_source_guard = 'var auth_source_lookup_only: Variant = auth.get("source_lookup_only", false)'
    legacy_loop = 'for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:'
    advertising_guard = 'var destination_advertisable: Variant = auth.get("destination_advertisable", true)'
    allowed = (
        'var allowed_authorization_keys := {\n'
        '        "source_lookup_only": true,\n'
        '        "render_authorized": true,\n'
        '        "collision_authorized": true,\n'
        '        "runtime_mount_authorized": true,\n'
        '        "safe_spawn_authorized": true,\n'
        '        "jouable_authorized": true,\n'
        '        "destination_advertisable": true,\n'
        '    }'
    )
    rejection = (
        'for raw_key: Variant in auth.keys():\n'
        '        if typeof(raw_key) != TYPE_STRING or not allowed_authorization_keys.has(str(raw_key)):\n'
        '            return false'
    )
    exact_size = "if auth.size() != allowed_authorization_keys.size():\n        return false"
    assert allowed in body, "authorization schema must enumerate the complete allowed key set"
    assert rejection in body, "unknown/non-string authorization keys must fail closed"
    assert exact_size in body, "authorization schema must require every canonical key exactly once"
    assert body.count(allowed) == 1, "authorization schema must have one canonical boundary"
    assert body.count(rejection) == 1, "unknown-key rejection must have one canonical boundary"
    assert body.count(exact_size) == 1, "authorization exact-size guard must have one canonical boundary"
    for marker in (auth_binding, auth_source_guard, legacy_loop, advertising_guard):
        assert marker in body, f"missing authorization boundary marker: {marker}"
        assert body.count(marker) == 1, f"authorization boundary marker must be unique: {marker}"
    assert (
        body.index(auth_binding)
        < body.index(allowed)
        < body.index(exact_size)
        < body.index(rejection)
        < body.index(auth_source_guard)
        < body.index(legacy_loop)
        < body.index(advertising_guard)
        < documents
    ), "require exact authorization schema and reject unknown keys before interpreting any authority value"


def test_runtime_index_rejects_unknown_top_level_keys_before_authorization() -> None:
    body = _loader()
    authorization = body.index('var authorization: Variant = index.get("authorization", {})')
    allowed = (
        'var allowed_index_keys := {\n'
        '        "format": true,\n'
        '        "source_lookup_only": true,\n'
        '        "catalog_sha256": true,\n'
        '        "authorization": true,\n'
        '        "documents": true,\n'
        '    }'
    )
    rejection = (
        'for raw_key: Variant in index.keys():\n'
        '        if typeof(raw_key) != TYPE_STRING or not allowed_index_keys.has(str(raw_key)):\n'
        '            return false'
    )
    assert allowed in body, "runtime-index schema must enumerate the complete top-level key set"
    assert rejection in body, "unknown/non-string top-level keys must fail closed"
    assert body.count(allowed) == 1, "top-level schema must have one canonical boundary"
    assert body.count(rejection) == 1, "top-level unknown-key rejection must have one canonical boundary"
    assert body.index(allowed) < body.index(rejection) < authorization, (
        "reject unknown top-level keys before interpreting authorization or registering documents"
    )


def test_runtime_index_format_is_exact_string_before_schema_or_authority() -> None:
    body = _loader()
    schema = body.index("var allowed_index_keys := {")
    authorization = body.index('var authorization: Variant = index.get("authorization", {})')
    binding = 'var runtime_index_format: Variant = index.get("format", "")'
    guard = 'if typeof(runtime_index_format) != TYPE_STRING or runtime_index_format != RUNTIME_INDEX_FORMAT:\n        return false'

    assert binding in body, "runtime-index format must be bound without coercion"
    assert guard in body, "runtime-index format must require an exact JSON string"
    assert body.count(binding) == 1, "runtime-index format must have one canonical binding"
    assert body.count(guard) == 1, "runtime-index format must have one canonical validation boundary"
    assert body.index(binding) < body.index(guard) < schema < authorization, (
        "format identity must fail closed before schema and authority interpretation"
    )
    assert 'str(index.get("format", ""))' not in body, "runtime-index format must never use string coercion"


def test_runtime_index_top_level_source_lookup_only_is_exact_boolean_before_authorization() -> None:
    body = _loader()
    schema = body.index("var allowed_index_keys := {")
    authorization = body.index('var authorization: Variant = index.get("authorization", {})')
    binding = 'var index_source_lookup_only: Variant = index.get("source_lookup_only", false)'
    guard = 'if typeof(index_source_lookup_only) != TYPE_BOOL or not index_source_lookup_only:\n        return false'

    assert binding in body, "top-level source_lookup_only must be bound without coercion"
    assert guard in body, "top-level source_lookup_only must require exact JSON true"
    assert body.count(binding) == 1, "top-level source_lookup_only must have one canonical binding"
    assert body.count(guard) == 1, "top-level source_lookup_only must have one canonical validation boundary"
    assert schema < body.index(binding) < body.index(guard) < authorization, (
        "source-only authority must fail closed before nested authorization interpretation"
    )
    assert 'bool(index.get("source_lookup_only", false))' not in body, (
        "top-level source_lookup_only must never use boolean coercion"
    )


def test_runtime_index_top_level_schema_is_exact_before_authorization() -> None:
    body = _loader()
    schema = body.index("var allowed_index_keys := {")
    authorization = body.index('var authorization: Variant = index.get("authorization", {})')
    exact_size = "if index.size() != allowed_index_keys.size():\n        return false"

    assert exact_size in body, "runtime-index top-level schema must require every canonical key exactly once"
    assert body.count(exact_size) == 1, "top-level exact-size guard must have one canonical boundary"
    assert schema < body.index(exact_size) < authorization, (
        "require exact top-level schema before interpreting nested authorization"
    )
