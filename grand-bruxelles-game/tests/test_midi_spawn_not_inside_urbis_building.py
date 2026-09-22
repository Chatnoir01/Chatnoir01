import json
import math
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


def _scalar(text: str, pattern: str) -> float:
    match = re.search(pattern, text, re.MULTILINE)
    assert match, f"missing scalar contract: {pattern}"
    return float(match.group(1))


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


def _containing_buildings(runtime: dict, point: tuple[float, float]) -> list[str]:
    containing = []
    for feature in runtime.get("buildings", []):
        if _point_in_polygon(point, feature.get("footprint", [])):
            containing.append(str(feature.get("id", "<missing-id>")))
    return containing


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
    player_rotation = _vec3(
        player_block.group(1),
        r"rotation_degrees\s*=\s*Vector3\(([-0-9.]+),\s*([-0-9.]+),\s*([-0-9.]+)\)",
    )
    origin = _vec3(builder, r"const MIDI_WORLD\s*:=\s*Vector3\(([-0-9.]+),\s*([-0-9.]+),\s*([-0-9.]+)\)")
    local_spawn = (player[0] - origin[0], player[2] - origin[2])

    containing_spawn = _containing_buildings(runtime, local_spawn)
    assert not containing_spawn, (
        "canonical Midi player spawn lies inside rendered UrbIS building footprint(s): "
        f"{containing_spawn}; world_xz=({player[0]}, {player[2]}), local_xz={local_spawn}. "
        "This is a source/render/spawn placement defect; do not hide it with camera/FOV changes or procedural NPCs."
    )

    spring_block = re.search(
        r'\[node name="SpringArm3D" type="SpringArm3D" parent="Player/CameraPivot"\](.*?)(?=\n\[node )',
        scene,
        re.DOTALL,
    )
    assert spring_block, "canonical Player SpringArm3D node missing"
    spring_length = _scalar(spring_block.group(1), r"spring_length\s*=\s*([-0-9.]+)")

    # Godot SpringArm3D places its child camera along local +Z.  Classify the
    # authored full-length camera endpoint separately from the player capsule:
    # a source building can contain the camera while leaving the player outside,
    # which presents as a flat wall filling the first frame when that building
    # is render-only and therefore cannot shorten the spring arm.
    yaw = math.radians(player_rotation[1])
    camera_world_x = player[0] + math.sin(yaw) * spring_length
    camera_world_z = player[2] + math.cos(yaw) * spring_length
    local_camera = (camera_world_x - origin[0], camera_world_z - origin[2])
    containing_camera = _containing_buildings(runtime, local_camera)

    assert not containing_camera, (
        "canonical Midi full-length player camera endpoint lies inside rendered UrbIS building footprint(s): "
        f"{containing_camera}; camera_world_xz=({camera_world_x:.6f}, {camera_world_z:.6f}), "
        f"camera_local_xz=({local_camera[0]:.6f}, {local_camera[1]:.6f}), "
        f"player_yaw={player_rotation[1]}, spring_length={spring_length}. "
        "Player containment is already excluded; this is a camera/building overlap classification. "
        "Do not rescue it by changing camera/FOV or rewriting UrbIS geometry."
    )
