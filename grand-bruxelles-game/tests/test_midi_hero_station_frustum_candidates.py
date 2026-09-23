import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCENE = ROOT / "game" / "main.tscn"
HERO = ROOT / "game" / "scripts" / "midi_hero_zone.gd"


def _vec3(text: str, pattern: str) -> tuple[float, float, float]:
    match = re.search(pattern, text, re.MULTILINE)
    assert match, f"missing vector contract: {pattern}"
    return tuple(float(match.group(i)) for i in range(1, 4))


def _scalar(text: str, pattern: str) -> float:
    match = re.search(pattern, text, re.MULTILINE)
    assert match, f"missing scalar contract: {pattern}"
    return float(match.group(1))


def _camera_contract(scene: str) -> tuple[tuple[float, float], tuple[float, float], float]:
    player_block = re.search(
        r'\[node name="Player" type="CharacterBody3D" parent="\."\](.*?)(?=\n\[node )',
        scene,
        re.DOTALL,
    )
    assert player_block, "canonical Player node missing"
    player = _vec3(player_block.group(1), r"position\s*=\s*Vector3\(([-0-9.]+),\s*([-0-9.]+),\s*([-0-9.]+)\)")
    rotation = _vec3(player_block.group(1), r"rotation_degrees\s*=\s*Vector3\(([-0-9.]+),\s*([-0-9.]+),\s*([-0-9.]+)\)")

    spring_block = re.search(
        r'\[node name="SpringArm3D" type="SpringArm3D" parent="Player/CameraPivot"\](.*?)(?=\n\[node )',
        scene,
        re.DOTALL,
    )
    camera_block = re.search(
        r'\[node name="Camera3D" type="Camera3D" parent="Player/CameraPivot/SpringArm3D"\](.*?)(?=\n\[node )',
        scene,
        re.DOTALL,
    )
    assert spring_block and camera_block, "canonical player camera contract missing"
    spring_length = _scalar(spring_block.group(1), r"spring_length\s*=\s*([-0-9.]+)")
    fov = _scalar(camera_block.group(1), r"fov\s*=\s*([-0-9.]+)")

    yaw = math.radians(rotation[1])
    camera = (player[0] + math.sin(yaw) * spring_length, player[2] + math.cos(yaw) * spring_length)
    forward = (-math.sin(yaw), -math.cos(yaw))
    return camera, forward, fov


def _world_xz(root: tuple[float, float], angle: float, local_x: float, local_z: float) -> tuple[float, float]:
    return (
        root[0] + math.cos(angle) * local_x + math.sin(angle) * local_z,
        root[1] - math.sin(angle) * local_x + math.cos(angle) * local_z,
    )


def _authored_office_blocks(hero: str) -> tuple[tuple[str, float, float], ...]:
    complex_block = re.search(
        r"func _build_station_complex\(\) -> void:(.*?)(?=\n\nfunc )",
        hero,
        re.DOTALL,
    )
    assert complex_block, "_build_station_complex() missing"
    calls = re.findall(
        r'_add_office_block\(station,\s*"([^"]+)",\s*([-0-9.]+),\s*([-0-9.]+),\s*\d+,\s*(?:true|false)\)',
        complex_block.group(1),
    )
    assert calls, "no authored station office blocks found"
    names = [name for name, _, _ in calls]
    assert len(names) == len(set(names)), f"duplicate authored office block names: {names}"
    return tuple((f"{name}/BlueStoneBase", float(local_z), float(length)) for name, local_z, length in calls)


def _blue_stone_local_x_bounds(hero: str) -> tuple[float, float]:
    office_block = re.search(
        r"func _add_office_block\(.*?\) -> void:(.*?)(?=\n\nfunc )",
        hero,
        re.DOTALL,
    )
    assert office_block, "_add_office_block() missing"
    body = office_block.group(1)
    block_x = _scalar(body, r"block\.position\s*=\s*Vector3\(([-0-9.]+),")
    width = _scalar(body, r"var width:\s*float\s*=\s*([-0-9.]+)")
    assert re.search(
        r'_add_box\(block,\s*"BlueStoneBase",\s*Vector3\(width,\s*base_height,\s*length\)',
        body,
    ), "BlueStoneBase no longer uses authored office-block width/length"
    half_width = width * 0.5
    return block_x - half_width, block_x + half_width


def test_rank_authored_midi_station_blue_stone_frustum_candidates() -> None:
    scene = SCENE.read_text(encoding="utf-8")
    hero = HERO.read_text(encoding="utf-8")
    camera, forward, fov = _camera_contract(scene)

    midi = _vec3(hero, r"const MIDI: Vector3 = Vector3\(([-0-9.]+),\s*([-0-9.]+),\s*([-0-9.]+)\)")
    fonsny = _vec3(hero, r"const FONSNY_AXIS: Vector3 = Vector3\(([-0-9.]+),\s*([-0-9.]+),\s*([-0-9.]+)\)")
    station_side = _vec3(hero, r"const STATION_SIDE: Vector3 = Vector3\(([-0-9.]+),\s*([-0-9.]+),\s*([-0-9.]+)\)")
    root = (
        midi[0] + station_side[0] * 34.0 + fonsny[0] * 2.0,
        midi[2] + station_side[2] * 34.0 + fonsny[2] * 2.0,
    )
    angle = math.atan2(fonsny[0], fonsny[2])
    right = (-forward[1], forward[0])

    # Derive block positions/lengths and BlueStoneBase width from the production
    # authoring calls so this diagnostic fails closed if the runtime articulation
    # changes instead of silently ranking stale hard-coded geometry.
    blocks = _authored_office_blocks(hero)
    local_x_bounds = _blue_stone_local_x_bounds(hero)
    half_fov = fov * 0.5
    candidates: list[tuple[float, str, float]] = []
    for name, block_z, length in blocks:
        min_abs_angle = 180.0
        nearest_forward = float("inf")
        for local_x in local_x_bounds:
            for local_z in (block_z - length * 0.5, block_z + length * 0.5):
                point = _world_xz(root, angle, local_x, local_z)
                delta = (point[0] - camera[0], point[1] - camera[1])
                forward_m = delta[0] * forward[0] + delta[1] * forward[1]
                lateral_m = delta[0] * right[0] + delta[1] * right[1]
                if forward_m > 0.0:
                    min_abs_angle = min(min_abs_angle, abs(math.degrees(math.atan2(lateral_m, forward_m))))
                    nearest_forward = min(nearest_forward, forward_m)
        if min_abs_angle <= half_fov:
            candidates.append((nearest_forward, name, min_abs_angle))

    candidates.sort()
    names = [candidate[1] for candidate in candidates]
    print("MIDI_HERO_BLUE_STONE_FRUSTUM_CANDIDATES=" + repr(candidates))
    assert names == ["FonsnyWingSouth/BlueStoneBase"], (
        "Expected the authored player-camera frustum to isolate the south Fonsny office base as the only "
        f"BlueStoneBase candidate, got {candidates}. This diagnostic does not authorize hiding or moving "
        "geometry; inspect/toggle that exact runtime node before any visual correction."
    )
