from pathlib import Path

RUNTIME = Path("grand-bruxelles-game/game/scripts/anneessens_osm_furniture_runtime.gd")


def _function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    end = source.index("\nfunc ", start + 1)
    return source[start:end]


def test_activation_consumer_reconciles_canonical_player_before_reading_position() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    sync_body = _function_body(source, "func _sync_build_and_activation() -> void:")

    canonical_lookup = '_scene.get_node_or_null("Player") as Node3D'
    assert canonical_lookup in sync_body, (
        "activation consumer must resolve canonical Main/Player ownership itself; "
        "caller-side cache checks are insufficient"
    )

    lookup_index = sync_body.index(canonical_lookup)
    position_index = sync_body.index("global_position")
    assert lookup_index < position_index, (
        "canonical Main/Player ownership must be resolved before activation reads Player coordinates"
    )

    identity_forms = (
        "_player != canonical_player",
        "canonical_player != _player",
        "_player != scene_player",
        "scene_player != _player",
        "_player != current_player",
        "current_player != _player",
    )
    assert any(form in sync_body for form in identity_forms), (
        "activation consumer must reject a valid in-tree cached Player whose identity differs "
        "from the current Main/Player path owner"
    )


def test_activation_consumer_fails_closed_when_canonical_player_path_is_missing() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    sync_body = _function_body(source, "func _sync_build_and_activation() -> void:")

    canonical_lookup = '_scene.get_node_or_null("Player") as Node3D'
    lookup_index = sync_body.index(canonical_lookup)
    deactivate_index = sync_body.index("_apply_tree_activation(false)", lookup_index)
    position_index = sync_body.index("global_position")

    null_guards = (
        "not is_instance_valid(canonical_player)",
        "canonical_player == null",
        "not is_instance_valid(scene_player)",
        "scene_player == null",
        "not is_instance_valid(current_player)",
        "current_player == null",
    )
    assert any(guard in sync_body for guard in null_guards), (
        "activation consumer must explicitly fail closed when Main/Player has no canonical owner"
    )
    assert lookup_index < deactivate_index < position_index


def test_activation_consumer_requires_canonical_player_live_before_position_read() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    sync_body = _function_body(source, "func _sync_build_and_activation() -> void:")

    canonical_lookup = '_scene.get_node_or_null("Player") as Node3D'
    lookup_index = sync_body.index(canonical_lookup)
    position_index = sync_body.index("global_position")

    liveness_forms = (
        "not canonical_player.is_inside_tree()",
        "not scene_player.is_inside_tree()",
        "not current_player.is_inside_tree()",
    )
    live_guard = next((form for form in liveness_forms if form in sync_body), None)
    assert live_guard is not None, (
        "activation consumer must prove the current Main/Player path owner is live in SceneTree "
        "before any coordinate read"
    )
    assert lookup_index < sync_body.index(live_guard) < position_index


def test_build_path_does_not_reconsume_mutable_cached_player_coordinates() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    build_body = _function_body(source, "func _build_once(active: bool) -> void:")

    assert "_player.global_position" not in build_body, (
        "_build_once must not re-read mutable cached Player coordinates after the canonical "
        "activation consumer has reconciled ownership"
    )


def test_activation_decision_is_passed_into_atomic_publication() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    sync_body = _function_body(source, "func _sync_build_and_activation() -> void:")
    build_body = _function_body(source, "func _build_once(active: bool) -> void:")

    assert "_build_once(active)" in sync_body, (
        "canonical activation must be passed directly into atomic root publication"
    )
    assert "candidate_root.visible = active" in build_body, (
        "atomic publication must consume the already-authorized activation decision"
    )
    assert "global_position" not in build_body, (
        "publication must not introduce a second coordinate authority"
    )
