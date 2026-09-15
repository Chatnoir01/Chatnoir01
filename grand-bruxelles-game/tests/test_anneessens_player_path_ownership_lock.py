from pathlib import Path

RUNTIME = Path("grand-bruxelles-game/game/scripts/anneessens_osm_furniture_runtime.gd")


def test_cached_player_must_match_canonical_scene_path_anchor() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    process_start = source.index("func _process(_delta: float) -> void:")
    process_end = source.index("\nfunc ", process_start + 1)
    process_body = source[process_start:process_end]

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
