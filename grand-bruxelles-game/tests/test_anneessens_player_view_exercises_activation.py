#!/usr/bin/env python3
"""Fail closed unless the player-view witness actually places canonical Main/Player at Anneessens."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
capture = root / "game/tests/anneessens_player_view_capture.gd"
text = capture.read_text(encoding="utf-8")

required = [
    'scene.get_node_or_null("Player")',
    "ANNEESSENS_SPAWN",
    "global_position = ANNEESSENS_SPAWN",
]
missing = [token for token in required if token not in text]
if missing:
    raise SystemExit(
        "ANNEESSENS_PLAYER_VIEW_ACTIVATION_WITNESS_FAIL: capture can render a GREEN A/B "
        "without placing canonical Main/Player at Anneessens; missing=" + repr(missing)
    )

player_lookup = text.index('scene.get_node_or_null("Player")')
player_move = text.index("global_position = ANNEESSENS_SPAWN")
wait = text.index("range(WAIT_FRAMES)")
if not (player_lookup < player_move < wait):
    raise SystemExit(
        "ANNEESSENS_PLAYER_VIEW_ACTIVATION_WITNESS_FAIL: canonical Player must be resolved "
        "and positioned before activation wait/capture"
    )

print("ANNEESSENS_PLAYER_VIEW_ACTIVATION_WITNESS_OK")
