#!/usr/bin/env python3
from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_osm_furniture_runtime.gd"


def body(source: str, function_name: str) -> str:
    marker = f"func {function_name}"
    start = source.find(marker)
    assert start >= 0, f"missing {function_name}"
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def main() -> int:
    source = RUNTIME.read_text(encoding="utf-8")
    process = body(source, "_process")
    sync = body(source, "_sync_build_and_activation")

    # There must be one authority reconciliation point: the activation consumer.
    # _process() may handle scene/root lifecycle, but must not independently decide
    # whether a cached Player remains authoritative.
    assert '_scene.get_node_or_null("Player")' not in process, (
        "_process still performs independent Player reconciliation; delegate to "
        "_sync_build_and_activation so stale cached Player identity cannot diverge"
    )
    assert "_player.is_inside_tree()" not in process, (
        "_process still treats SceneTree membership as Player authority; a reparented "
        "Player remains inside the tree but is no longer canonical Main/Player"
    )
    assert "_sync_build_and_activation()" in process, "_process must delegate activation"

    canonical = '_scene.get_node_or_null("Player") as Node3D'
    assert canonical in sync, "activation consumer must resolve canonical Main/Player every call"
    resolve_at = sync.index(canonical)
    position_at = sync.find("global_position")
    assert position_at > resolve_at, "Player ownership must be reconciled before coordinates are consumed"
    assert "_player =" in sync[resolve_at:position_at], (
        "activation consumer must replace cached Player from canonical Main/Player before coordinate use"
    )
    assert "_apply_tree_activation(false)" in sync[resolve_at:position_at], (
        "activation consumer must fail closed when canonical Main/Player is absent"
    )

    print("ANNEESSENS_PROCESS_DELEGATES_PLAYER_RECONCILIATION_LOCK_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
