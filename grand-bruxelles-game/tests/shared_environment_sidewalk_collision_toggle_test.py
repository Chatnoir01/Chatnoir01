from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"
text = RUNTIME.read_text(encoding="utf-8")

assert "var _sidewalks_enabled := true" in text, "runtime must retain requested sidewalk enabled state across rebuilds"
assert "pavement.use_collision = _sidewalks_enabled" in text, "newly rebound sidewalks must inherit collision enabled state"
assert "func set_sidewalks_enabled(enabled: bool) -> void:" in text
assert "_sidewalks_enabled = enabled" in text, "toggle must persist requested state"
assert "pavement.use_collision = enabled" in text, "toggle must synchronize owned collision with visibility"
assert "_root.visible = enabled" in text, "toggle must synchronize visual visibility"
print("SHARED_ENVIRONMENT_SIDEWALK_COLLISION_TOGGLE_OK: visibility_and_collision=locked rebind_state=locked")
