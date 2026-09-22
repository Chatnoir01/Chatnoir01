import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCENE = ROOT / "game" / "main.tscn"
BUILDER = ROOT / "game" / "scripts" / "urbis_midi_builder.gd"
RUNTIME = ROOT / "data" / "urbis" / "midi" / "midi_runtime.game.json"


def _vec3(text: str, pattern: str) -> tuple[float, float, float]:
    match = re.search(pattern, text, re.MULTILINE)
    assert match, f"missing vector contract: {pattern}"
    return tuple(float(match.group(i)) for i in range(1, 4))


def _point_in_polygon(point: tuple[float, float], polygon: list[list[float]]) -> bool:
    x, y = point
    inside = False
    points = [(float(p[0]), float(p[1])) for p in polygon if isinstance(p, list) and len(p) >= 2]
    if len(points) < 3:
        return False
    j = len(points) - 1
    for i in range(len(points)):
        xi, yi = points[i]
        xj, yj = points[j]
        crosses = (yi > y) != (yj > y)
        if crosses:
            x_at_y = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < x_at_y:
                inside = not inside
        j = i
    return inside


def test_canonical_midi_player_spawn_is_not_inside_rendered_urbis_building() -> None:
    scene = SCENE.read_text(encoding="utf-8")
    builder = BUILDER.read_text(encoding="utf-8")
    runtime = json.loads(RUNTIME.read_text(encoding="utf-8"))

    player_block = re.search(
        r'\[node name="Player" type="CharacterBody3D" parent="\."\](.*?)(?=\n\[node )',
        scene,
        re.DOTALL,
    )
    assert player_block, "canonical Player node missing"
    player = _vec3(player_block.group(1), r"position\s*=\s*Vector3\(([-0-9.]+),\s*([-0-9.]+),\s*([-0-9.]+)\)")
    origin = _vec3(builder, r"const MIDI_WORLD\s*:=\s*Vector3\(([-0-9.]+),\s*([-0-9.]+),\s*([-0-9.]+)\)")
    local_spawn = (player[0] - origin[0], player[2] - origin[2])

    containing = []
    for feature in runtime.get("buildings", []):
        footprint = feature.get("footprint", [])
        if _point_in_polygon(local_spawn, footprint):
            containing.append(str(feature.get("id", "<missing-id>")))

    assert not containing, (
        "canonical Midi player spawn lies inside rendered UrbIS building footprint(s): "
        f"{containing}; world_xz=({player[0]}, {player[2]}), local_xz={local_spawn}. "
        "This is a source/render/spawn placement defect; do not hide it with camera/FOV changes or procedural NPCs."
    )
