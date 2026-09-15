from pathlib import Path

RUNTIME = Path("grand-bruxelles-game/game/scripts/anneessens_osm_furniture_runtime.gd")


def _function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    end = source.index("\nfunc ", start + 1)
    return source[start:end]


def test_cached_player_must_match_canonical_scene_path_anchor() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    process_body = _function_body(source, "func _process(_delta: float) -> void:")

    canonical_lookup = '_scene.get_node_or_null("Player") as Node3D'
    assert canonical_lookup in process_body, "_process must resolve the canonical scene Player path"

    # Object validity / SceneTree membership are insufficient ownership proofs: an old
    # Player can remain alive after being reparented away from Main/Player. Require an
    # explicit identity comparison against the current canonical path anchor.
    identity_forms = (
        "_player != canonical_player",
        "canonical_player != _player",
        "_player != scene_player",
        "scene_player != _player",
        "_player != current_player",
        "current_player != _player",
    )
    assert any(form in process_body for form in identity_forms), (
        "_process still lacks an explicit cached-player vs canonical Main/Player identity check"
    )

    # Losing the canonical path must remain fail-closed rather than allowing the stale
    # cached object to keep furniture visible merely because it is still inside SceneTree.
    assert "_apply_tree_activation(false)" in process_body


def test_process_must_reconcile_path_ownership_before_activation_sync() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    process_body = _function_body(source, "func _process(_delta: float) -> void:")

    canonical_lookup = '_scene.get_node_or_null("Player") as Node3D'
    lookup_index = process_body.index(canonical_lookup)
    sync_index = process_body.index("_sync_build_and_activation()")
    assert lookup_index < sync_index, (
        "canonical Main/Player ownership must be reconciled before activation can read cached Player state"
    )

    # The old membership-only guard is specifically insufficient for a reparented Player.
    # Keep this ordering lock so a later refactor cannot perform the identity check only
    # after stale cached coordinates have already driven visibility/build decisions.
    assert "_player.is_inside_tree()" in process_body
