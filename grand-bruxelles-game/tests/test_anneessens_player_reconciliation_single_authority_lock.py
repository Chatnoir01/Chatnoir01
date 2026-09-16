from pathlib import Path

RUNTIME = Path(
    "grand-bruxelles-game/game/scripts/anneessens_osm_furniture_authoritative_runtime.gd"
)
BASE_RUNTIME = Path("grand-bruxelles-game/game/scripts/anneessens_osm_furniture_runtime.gd")


def _function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    end = source.find("\nfunc ", start + 1)
    return source[start:] if end < 0 else source[start:end]


def test_activation_consumer_is_single_canonical_player_reconciliation_authority() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    process_body = _function_body(source, "func _process(_delta: float) -> void:")
    sync_body = _function_body(source, "func _sync_build_and_activation() -> void:")

    canonical_lookup = '_scene.get_node_or_null("Player") as Node3D'
    assert canonical_lookup in sync_body, (
        "activation consumer must own canonical Main/Player reconciliation"
    )
    assert "_player = canonical_player" in sync_body, (
        "activation consumer must replace stale cached Player identity with canonical Main/Player"
    )
    assert "canonical_player.is_inside_tree()" in sync_body, (
        "activation consumer must reject a canonical Player that is not live in the SceneTree"
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


def test_publication_boundary_cannot_reread_player_coordinates() -> None:
    """Pin the last stale-coordinate escape hatch before visual publication.

    The authoritative consumer computes ``active`` from the canonical Main/Player.  The base
    builder must consume that already-proven decision rather than reading ``_player`` again;
    otherwise ownership can change between validation and root publication.
    """
    authoritative = RUNTIME.read_text(encoding="utf-8")
    base = BASE_RUNTIME.read_text(encoding="utf-8")
    sync_body = _function_body(authoritative, "func _sync_build_and_activation() -> void:")
    build_body = _function_body(base, "func _build_once")

    assert "_build_once(active)" in sync_body, (
        "canonical activation decision must be passed atomically to the publication boundary"
    )
    assert "global_position" not in build_body, (
        "_build_once must not reread Player coordinates after canonical ownership was validated"
    )
