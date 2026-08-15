#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
visual_path = ROOT / "grand-bruxelles-game/game/scripts/humanoid_visual.gd"
workflow_path = ROOT / ".github/workflows/grand-bruxelles-character-loader.yml"

s = visual_path.read_text()
old = '''const FALLBACK_AUTHORED_CHARACTER_PATHS := [\n    "res://assets/characters/player/thandi/Thandi.fbx",\n    "res://assets/characters/player_character.glb",\n]'''
new = '''const FALLBACK_AUTHORED_CHARACTER_PATHS := [\n    "res://assets/characters/player/thandi/Thandi.fbx",\n    "res://assets/characters/player/kaykit_rogue/Rogue.glb",\n    "res://assets/characters/player_character.glb",\n]'''
if new not in s:
    assert old in s
    s = s.replace(old, new, 1)

vars_old = 'var _visual_signature: String = ""\n'
vars_new = '''var _visual_signature: String = ""\nvar _authored_animation_player: AnimationPlayer\nvar _authored_idle_animation: StringName = &""\nvar _authored_walk_animation: StringName = &""\nvar _authored_run_animation: StringName = &""\n'''
if vars_new not in s:
    assert vars_old in s
    s = s.replace(vars_old, vars_new, 1)

process_old = '''    if is_instance_valid(_authored_character):\n        return\n'''
process_new = '''    if is_instance_valid(_authored_character):\n        _update_authored_locomotion()\n        return\n'''
if process_new not in s:
    assert process_old in s
    s = s.replace(process_old, process_new, 1)

load_old = '''                _visual_signature = "authored:%s" % candidate\n                print("Grand Bruxelles authored player loaded: %s" % candidate)\n'''
load_new = '''                _visual_signature = "authored:%s" % candidate\n                _configure_authored_animation_player()\n                print("Grand Bruxelles authored player loaded: %s" % candidate)\n'''
if load_new not in s:
    assert load_old in s
    s = s.replace(load_old, load_new, 1)

marker = '\nfunc is_using_authored_character() -> bool:\n'
methods = r'''

func _configure_authored_animation_player() -> void:
    _authored_animation_player = _find_animation_player(_authored_character)
    if _authored_animation_player == null:
        return
    var names: PackedStringArray = _authored_animation_player.get_animation_list()
    _authored_idle_animation = _find_animation_name(names, ["idle"])
    _authored_walk_animation = _find_animation_name(names, ["walk"])
    _authored_run_animation = _find_animation_name(names, ["run", "sprint"])
    if _authored_idle_animation == &"":
        _authored_idle_animation = _first_non_reset_animation(names)
    if _authored_idle_animation != &"":
        _authored_animation_player.play(_authored_idle_animation)


func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child: Node in node.get_children():
        var found: AnimationPlayer = _find_animation_player(child)
        if found != null:
            return found
    return null


func _find_animation_name(names: PackedStringArray, needles: Array[String]) -> StringName:
    for animation_name: String in names:
        var lower: String = animation_name.to_lower()
        for needle: String in needles:
            if needle in lower:
                return StringName(animation_name)
    return &""


func _first_non_reset_animation(names: PackedStringArray) -> StringName:
    for animation_name: String in names:
        if animation_name != "RESET":
            return StringName(animation_name)
    return &""


func _update_authored_locomotion() -> void:
    if _authored_animation_player == null:
        return
    var actor: CharacterBody3D = get_parent() as CharacterBody3D
    if actor == null:
        return
    var speed: float = Vector2(actor.velocity.x, actor.velocity.z).length()
    var target: StringName = _authored_idle_animation
    if speed > 5.2 and _authored_run_animation != &"":
        target = _authored_run_animation
    elif speed > 0.25 and _authored_walk_animation != &"":
        target = _authored_walk_animation
    if target != &"" and _authored_animation_player.current_animation != String(target):
        _authored_animation_player.play(target)


func authored_animation_player() -> AnimationPlayer:
    return _authored_animation_player


func authored_locomotion_animations() -> Dictionary:
    return {
        "idle": String(_authored_idle_animation),
        "walk": String(_authored_walk_animation),
        "run": String(_authored_run_animation),
    }
'''
if 'func _configure_authored_animation_player()' not in s:
    assert marker in s
    s = s.replace(marker, methods + marker, 1)
visual_path.write_text(s)

w = workflow_path.read_text()
anchor = '      - "grand-bruxelles-game/assets/characters/player/thandi/**"\n'
addition = '      - "grand-bruxelles-game/assets/characters/player/kaykit_rogue/**"\n      - "grand-bruxelles-game/game/tests/real_authored_player_asset_test.gd"\n'
if addition not in w:
    assert anchor in w
    w = w.replace(anchor, anchor + addition, 1)
needle = '          grep -q "HUMANOID_AUTHORED_PLAYER_OK" /tmp/character-loader.log\n'
proof = '''\n      - name: Prove real authored player rig, material and animation runtime\n        shell: bash\n        run: |\n          set -o pipefail\n          timeout 60s godot --headless --path grand-bruxelles-game \\\n            --script res://game/tests/real_authored_player_asset_test.gd 2>&1 | tee /tmp/real-player.log\n          if grep -E "SCRIPT ERROR|Parse Error:|REAL_AUTHORED_PLAYER_FAIL" /tmp/real-player.log; then\n            exit 1\n          fi\n          grep -q "REAL_AUTHORED_PLAYER_OK" /tmp/real-player.log\n'''
if 'Prove real authored player rig' not in w:
    assert needle in w
    w = w.replace(needle, needle + proof, 1)
workflow_path.write_text(w)
