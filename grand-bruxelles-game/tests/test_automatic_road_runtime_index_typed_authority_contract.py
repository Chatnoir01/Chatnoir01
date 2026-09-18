from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _loader() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _load_runtime_index() -> bool:")
    end = text.index("\nfunc runtime_index_road_count()", start)
    return text[start:end]


def test_runtime_index_authority_is_typed_and_fail_closed_before_documents() -> None:
    body = _loader()
    documents = body.index("var documents: Variant")

    top_level = (
        'var index_source_lookup_only: Variant = index.get("source_lookup_only", false)\n'
        '    if typeof(index_source_lookup_only) != TYPE_BOOL or not index_source_lookup_only:\n'
        '        return false'
    )
    auth_level = (
        'var auth_source_lookup_only: Variant = auth.get("source_lookup_only", false)\n'
        '    if typeof(auth_source_lookup_only) != TYPE_BOOL or not auth_source_lookup_only:\n'
        '        return false'
    )
    advertising = (
        'var destination_advertisable: Variant = auth.get("destination_advertisable", true)\n'
        '    if typeof(destination_advertisable) != TYPE_BOOL or destination_advertisable:\n'
        '        return false'
    )

    for label, guard in (
        ("top-level source_lookup_only", top_level),
        ("authorization source_lookup_only", auth_level),
        ("destination_advertisable", advertising),
    ):
        assert guard in body, f"missing exact typed fail-closed guard: {label}"
        assert body.count(guard) == 1, f"{label} must have one canonical authority boundary"
        assert body.index(guard) < documents, f"{label} must be resolved before document registration"

    legacy_loop = 'for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:'
    legacy_guard = (
        'var forbidden_value: Variant = auth.get(forbidden, true)\n'
        '        if typeof(forbidden_value) != TYPE_BOOL or forbidden_value:\n'
        '            return false'
    )
    assert legacy_loop in body
    assert body.count(legacy_loop) == 1, "legacy negative rails must have one canonical iteration boundary"
    assert legacy_guard in body, "legacy negative authority rails must require exact JSON booleans"
    assert body.count(legacy_guard) == 1, "legacy typed-negative guard must have one canonical authority boundary"
    assert body.index(legacy_loop) < body.index(legacy_guard) < body.index(advertising) < documents

    for coercive in (
        'if not bool(index.get("source_lookup_only", false)):',
        'if not bool(auth.get("source_lookup_only", false)):',
        'if bool(auth.get(forbidden, true)):',
        'not bool(auth_source_lookup_only)',
        'bool(forbidden_value)',
        'bool(destination_advertisable)',
    ):
        assert coercive not in body, f"coercive authorization form must be removed: {coercive}"

    # Keep one canonical top-level binding shared by the typed-authority and
    # keyset contracts. A second alias would permit the two gates to validate
    # different reads of the same authority field.
    top_binding = 'var index_source_lookup_only: Variant = index.get("source_lookup_only", false)'
    assert body.count(top_binding) == 1, "top-level source_lookup_only must have one shared canonical binding"
    assert 'var source_lookup_only: Variant = index.get("source_lookup_only", false)' not in body

    # Authorization must be fully resolved before any source/road staging can
    # make the attempted index eligible for final publication. The transactional
    # loader intentionally keeps canonical maps empty until complete validation.
    source_registration = 'staged_source_sha_by_path[source_path] = expected_sha'
    road_registration = 'staged_road_source_path_by_id[osm_id] = source_path'
    source_commit = '_source_sha_by_path = staged_source_sha_by_path'
    road_commit = '_road_source_path_by_id = staged_road_source_path_by_id'
    valid_promotion = '_runtime_index_valid = not _road_source_path_by_id.is_empty()'
    for label, mutation in (
        ("staged source document registration", source_registration),
        ("staged road registration", road_registration),
        ("source-map commit", source_commit),
        ("road-map commit", road_commit),
        ("runtime-index validity promotion", valid_promotion),
    ):
        assert mutation in body, f"missing canonical loader mutation: {label}"
        assert body.count(mutation) == 1, f"{label} must have one canonical mutation point"
        assert documents < body.index(mutation), f"{label} must remain after all authorization boundaries"

    assert body.index(source_registration) < body.index(source_commit) < body.index(valid_promotion)
    assert body.index(road_registration) < body.index(road_commit) < body.index(valid_promotion)
