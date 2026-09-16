#!/usr/bin/env python3
"""Fail closed unless the player-view witness drives canonical Main/Player at Anneessens."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
capture = root / "game/tests/anneessens_player_view_capture.gd"
text = capture.read_text(encoding="utf-8")

required = [
    'scene.get_node_or_null("Player") as Node3D',
    "player == null or not player.is_inside_tree()",
    "player.global_position = ANNEESSENS_SPAWN",
]
missing = [token for token in required if token not in text]
if missing:
    raise SystemExit(
        "ANNEESSENS_PLAYER_VIEW_ACTIVATION_WITNESS_FAIL: capture can render a GREEN A/B "
        "without a live canonical Main/Player activation witness; missing=" + repr(missing)
    )

lookup = text.index('scene.get_node_or_null("Player") as Node3D')
liveness = text.index("player == null or not player.is_inside_tree()", lookup)
move = text.index("player.global_position = ANNEESSENS_SPAWN", liveness)
wait = text.index("range(WAIT_FRAMES)", move)
if not (lookup < liveness < move < wait):
    raise SystemExit(
        "ANNEESSENS_PLAYER_VIEW_ACTIVATION_WITNESS_FAIL: canonical Player lookup, liveness, "
        "Anneessens placement and activation wait must remain ordered"
    )

between_lookup_and_move = text[lookup:move]
if "get_tree().root" in between_lookup_and_move or 'get_node_or_null("Main/Player")' in between_lookup_and_move:
    raise SystemExit(
        "ANNEESSENS_PLAYER_VIEW_ACTIVATION_WITNESS_FAIL: witness must consume Player from the "
        "already-instantiated canonical Main scene, not a parallel root lookup"
    )

print("ANNEESSENS_PLAYER_VIEW_ACTIVATION_WITNESS_OK")
