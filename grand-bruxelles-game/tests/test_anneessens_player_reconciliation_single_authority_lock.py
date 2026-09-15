from pathlib import Path

RUNTIME = Path("grand-bruxelles-game/game/scripts/anneessens_osm_furniture_runtime.gd")


def _function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    end = source.index("\nfunc ", start + 1)
    return source[start:end]


def test_activation_consumer_is_single_canonical_player_reconciliation_authority() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    process_body = _function_body(source, "func _process(_delta: float) -> void:")
    sync_body = _function_body(source, "func _sync_build_and_activation() -> void:")

    canonical_lookup = '_scene.get_node_or_null("Player") as Node3D'
    assert canonical_lookup in sync_body, (
        "activation consumer must own canonical Main/Player reconciliation"
    )
    assert "_player != canonical_player" in sync_body or "canonical_player != _player" in sync_body, (
        "activation consumer must replace/reject stale cached Player identity"
    )
    assert "_apply_tree_activation(false)" in sync_body, (
        "activation consumer must fail closed when canonical Player ownership is absent"
    )

    assert canonical_lookup not in process_body, (
        "_process must not retain a second Player reconciliation authority; delegate to "
        "_sync_build_and_activation so ownership and coordinate consumption cannot drift"
    )
    assert "_sync_build_and_activation()" in process_body, (
        "_process must delegate activation decisions to the single ownership-aware consumer"
    )
