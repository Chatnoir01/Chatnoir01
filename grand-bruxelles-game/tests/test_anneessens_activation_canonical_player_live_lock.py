from pathlib import Path

RUNTIME = Path("game/scripts/anneessens_osm_furniture_runtime.gd")


def _function_body(source: str, name: str) -> str:
    marker = f"func {name}("
    start = source.find(marker)
    assert start >= 0, f"missing {name}"
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_activation_consumer_resolves_live_canonical_player_before_coordinates() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    sync = _function_body(source, "_sync_build_and_activation")

    resolve = '_scene.get_node_or_null("Player") as Node3D'
    inside_tree = "is_inside_tree()"
    coordinate_use = "_player.global_position"

    assert resolve in sync, "activation consumer must resolve canonical Main/Player every call"
    assert inside_tree in sync, "activation consumer must reject a canonical Player outside SceneTree"
    assert coordinate_use in sync, "activation consumer no longer owns Player-coordinate consumption"

    resolve_pos = sync.index(resolve)
    inside_tree_pos = sync.index(inside_tree, resolve_pos)
    coordinate_pos = sync.index(coordinate_use)
    assert resolve_pos < inside_tree_pos < coordinate_pos, (
        "canonical Player resolution and live-tree validation must happen before coordinate consumption"
    )


def test_process_delegates_player_identity_to_activation_consumer() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    process = _function_body(source, "_process")

    assert '_scene.get_node_or_null("Player")' not in process, (
        "_process must not retain a second Player identity authority"
    )
    assert "_player.is_inside_tree()" not in process, (
        "_process must not retain a second Player liveness authority"
    )
    assert "_sync_build_and_activation()" in process, (
        "_process must delegate Player reconciliation and activation to the single consumer"
    )
