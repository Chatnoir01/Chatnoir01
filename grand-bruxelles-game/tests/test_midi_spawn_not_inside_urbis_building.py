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


def _cross(a: tuple[float, float], b: tuple[float, float]) -> float:
    return a[0] * b[1] - a[1] * b[0]


def _segment_edge_t(
    start: tuple[float, float],
    end: tuple[float, float],
    edge_a: tuple[float, float],
    edge_b: tuple[float, float],
) -> float | None:
    ray = (end[0] - start[0], end[1] - start[1])
    edge = (edge_b[0] - edge_a[0], edge_b[1] - edge_a[1])
    denominator = _cross(ray, edge)
    if abs(denominator) <= 1e-12:
        return None
    delta = (edge_a[0] - start[0], edge_a[1] - start[1])
    t = _cross(delta, edge) / denominator
    u = _cross(delta, ray) / denominator
    if 0.0 <= t <= 1.0 and 0.0 <= u <= 1.0:
        return t
    return None


def _building_segment_hits(
    runtime: dict,
    start: tuple[float, float],
    end: tuple[float, float],
) -> list[tuple[float, str]]:
    hits: list[tuple[float, str]] = []
    for feature in runtime.get("buildings", []):
        footprint = feature.get("footprint", [])
        points = [(float(p[0]), float(p[1])) for p in footprint if isinstance(p, list) and len(p) >= 2]
        if len(points) < 3:
            continue
        best_t: float | None = None
        for index, edge_a in enumerate(points):
            edge_b = points[(index + 1) % len(points)]
            t = _segment_edge_t(start, end, edge_a, edge_b)
            if t is not None and (best_t is None or t < best_t):
                best_t = t
        if best_t is not None:
            hits.append((best_t, str(feature.get("id", "<missing-id>"))))
    return sorted(hits, key=lambda hit: (hit[0], hit[1]))


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

    crossings = _building_segment_hits(runtime, local_spawn, local_camera)
    assert not crossings, (
        "canonical Midi player-to-camera spring-arm segment crosses rendered UrbIS building footprint edge(s): "
        f"{crossings}; player_local_xz={local_spawn}, camera_local_xz={local_camera}. "
        "Both endpoints are outside, so this identifies source building mass between Player and camera. "
        "Do not move camera/FOV or rewrite UrbIS geometry; inspect the first reported building/node and its "
        "authorized collision/spring-arm integration before any visual correction."
    )

    forward_distance_m = 80.0
    forward_end = (
        local_camera[0] - math.sin(yaw) * forward_distance_m,
        local_camera[1] - math.cos(yaw) * forward_distance_m,
    )
    forward_hits = _building_segment_hits(runtime, local_camera, forward_end)
    forward_report = [
        {"id": building_id, "distance_m": round(t * forward_distance_m, 3)}
        for t, building_id in forward_hits[:8]
    ]
    print(
        "MIDI_CAMERA_FORWARD_BUILDING_HITS="
        + json.dumps(forward_report, separators=(",", ":"), sort_keys=True)
    )
    assert not forward_report, (
        "MIDI_CAMERA_FORWARD_BUILDING_HITS="
        + json.dumps(forward_report, separators=(",", ":"), sort_keys=True)
    )
