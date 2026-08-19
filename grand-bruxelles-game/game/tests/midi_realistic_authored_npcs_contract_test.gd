extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/midi_ambient_npc_visual_runtime.gd")
const AUTHORED_RUNTIME_SCRIPT := preload("res://game/scripts/midi_realistic_authored_npc_runtime.gd")
const LEGACY_NAMES := ["Torso", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Head", "Bag"]
const CONTRACT_PATH := "res://data/qa/midi_realistic_authored_npcs_contract.json"
const ROCKETBOX_VERDICT_PATH := "res://data/qa/midi_realistic_authored_npcs_candidate_verdict.json"
const BANNED_CIVILIAN_ASSET := "res://assets/characters/player_character.glb"

func _init() -> void:
    var failures: Array[String] = []
    _check_runtime_contract(failures)
    _check_authored_locomotion_runtime(failures)
    _check_lot_contract(failures)
    _check_rejected_candidate(failures)

    if failures.is_empty():
        print("MIDI_REALISTIC_AUTHORED_NPCS_CONTRACT_GREEN")
        quit(0)
        return
    for failure in failures:
        push_error("MIDI_REALISTIC_AUTHORED_NPCS_CONTRACT_FAIL: %s" % failure)
    quit(1)

func _check_runtime_contract(failures: Array[String]) -> void:
    var runtime := RUNTIME_SCRIPT.new()
    var scene := Node3D.new()
    var urban_life := Node3D.new()
    urban_life.name = "MidiUrbanLife"
    scene.add_child(urban_life)

    var person := Node3D.new()
    person.name = "AmbientPedestrian_CONTRACT_00"
    person.add_to_group("ambient_pedestrian")
    urban_life.add_child(person)
    for legacy_name: String in LEGACY_NAMES:
        var legacy := MeshInstance3D.new()
        legacy.name = legacy_name
        legacy.mesh = BoxMesh.new()
        legacy.visible = true
        person.add_child(legacy)

    var result: Dictionary = runtime.bridge_scene(scene)
    if int(result.get("bridged", 0)) != 1:
        failures.append("Midi pedestrian bridge was not exercised")
    if int(result.get("lod_legacy_visible", -1)) != 0:
        failures.append("legacy primitive must be invisible immediately after bridge")

    runtime._set_legacy_visuals(person, true)
    for legacy_name: String in LEGACY_NAMES:
        var legacy := person.get_node_or_null(legacy_name) as GeometryInstance3D
        if legacy != null and legacy.visible:
            failures.append("explicit legacy re-enable resurrected %s" % legacy_name)

    var truth: Dictionary = runtime.truth_contract()
    if str(truth.get("legacy_body_fallback", "")) != "retired":
        failures.append("runtime truth must retire legacy body fallback")
    if bool(truth.get("legacy_primitives_far", true)):
        failures.append("runtime truth must forbid far legacy primitives")
    if "legacy cuboid primitives never rendered" not in str(truth.get("distance_lod", "")):
        failures.append("runtime truth must explicitly state cuboid retirement")

    scene.free()
    runtime.free()

func _check_authored_locomotion_runtime(failures: Array[String]) -> void:
    var scene := Node3D.new()
    root.add_child(scene)
    var runtime := AUTHORED_RUNTIME_SCRIPT.new()
    scene.add_child(runtime)

    var unauthorized := _make_mock_authored_person("UnauthorizedCivil", false)
    scene.add_child(unauthorized)
    if bool(runtime.call("bind_person", unauthorized)):
        failures.append("authored runtime accepted production_authorized=false character")

    var person := _make_mock_authored_person("AuthorizedCivil", true)
    scene.add_child(person)
    if not bool(runtime.call("bind_person", person)):
        failures.append("authored runtime could not bind a complete authorized idle/walk/run character")
        scene.free()
        return

    var resolved: Dictionary = runtime.call("resolved_locomotion_for", person)
    if str(resolved.get("idle", "")) != "Civil_Idle":
        failures.append("authored runtime did not resolve idle clip")
    if str(resolved.get("walk", "")) != "Civil_Walk":
        failures.append("authored runtime did not resolve walk clip")
    if str(resolved.get("run", "")) != "Civil_Run":
        failures.append("authored runtime did not resolve run clip")

    runtime.call("update_person_from_observed_speed", person, 0.0, 1.0 / 60.0)
    if str(runtime.call("current_locomotion_state_for", person)) != "idle":
        failures.append("authored runtime did not enter idle at zero speed")
    if str(runtime.call("current_animation_for", person)) != "Civil_Idle":
        failures.append("authored runtime did not play resolved idle")

    runtime.call("update_person_from_observed_speed", person, 0.95, 1.0 / 60.0)
    if str(runtime.call("current_locomotion_state_for", person)) != "walk":
        failures.append("authored runtime did not enter walk at civilian walking speed")
    if str(runtime.call("current_animation_for", person)) != "Civil_Walk":
        failures.append("authored runtime did not play resolved walk")
    var walk_scale := float(runtime.call("current_playback_speed_scale_for", person))
    if walk_scale < 0.65 or walk_scale > 1.50:
        failures.append("authored walk playback speed escaped safe synchronization range")

    runtime.call("update_person_from_observed_speed", person, 1.90, 1.0 / 60.0)
    if str(runtime.call("current_locomotion_state_for", person)) != "run":
        failures.append("authored runtime did not enter run at civilian running speed")
    if str(runtime.call("current_animation_for", person)) != "Civil_Run":
        failures.append("authored runtime did not play resolved run")

    var stats: Dictionary = runtime.call("locomotion_stats")
    if bool(stats.get("changes_movement_owner", true)):
        failures.append("authored locomotion must not own pedestrian movement")
    if bool(stats.get("changes_navigation", true)):
        failures.append("authored locomotion must not change navigation")
    if not bool(stats.get("production_authorization_required", false)):
        failures.append("authored locomotion must require explicit production authorization")
    if not bool(stats.get("requires_idle_walk_run", false)):
        failures.append("authored locomotion must require idle/walk/run")
    if not bool(stats.get("speed_sync", false)):
        failures.append("authored locomotion must synchronize playback to observed speed")
    if int(stats.get("authorized_bindings", 0)) < 1:
        failures.append("authored locomotion did not account for authorized binding")
    if int(stats.get("unauthorized_rejections", 0)) < 1:
        failures.append("authored locomotion did not account for unauthorized rejection")

    scene.free()

func _make_mock_authored_person(person_name: String, production_authorized: bool) -> Node3D:
    var person := Node3D.new()
    person.name = person_name
    person.add_to_group("ambient_pedestrian")

    var proxy := Node3D.new()
    proxy.name = "ProfiledNpcProxy"
    person.add_child(proxy)

    var authored := Node3D.new()
    authored.name = "AuthoredCharacter"
    authored.set_meta("production_authorized", production_authorized)
    proxy.add_child(authored)

    var animation_player := AnimationPlayer.new()
    animation_player.name = "AnimationPlayer"
    var library := AnimationLibrary.new()
    for clip_name: String in ["Civil_Idle", "Civil_Walk", "Civil_Run"]:
        var animation := Animation.new()
        animation.length = 1.0
        library.add_animation(clip_name, animation)
    animation_player.add_animation_library("", library)
    authored.add_child(animation_player)
    return person

func _check_lot_contract(failures: Array[String]) -> void:
    var contract := _read_json(CONTRACT_PATH)
    if contract.is_empty():
        failures.append("LOT contract could not be read")
        return
    if str(contract.get("zone", "")) != "midi":
        failures.append("LOT must remain Midi-only")
    if str(contract.get("scope", "")) != "visual_only":
        failures.append("LOT must remain visual-only")
    if bool(contract.get("runtime_authorized", true)):
        failures.append("runtime must remain unauthorized until owner GARDER")
    if bool(contract.get("merge_authorized", true)):
        failures.append("merge must remain unauthorized during fidelity iteration")
    if int(contract.get("minimum_civilian_identities", 0)) < 6:
        failures.append("LOT requires at least six civilian identities")
    if not bool(contract.get("human_visual_verdict_required", false)):
        failures.append("human visual verdict must remain mandatory")
    if bool(contract.get("done", true)):
        failures.append("LOT cannot be DONE before authored roster fidelity passes")

    var lod := contract.get("lod", {}) as Dictionary
    if bool(lod.get("legacy_cuboid_fallback_allowed", true)):
        failures.append("LOT contract cannot authorize cuboid fallback")
    if str(lod.get("far_policy", "")) != "authored_humanoid_lod_or_cull":
        failures.append("far policy must be authored humanoid LOD or cull")

    var required_animation_roles := contract.get("required_animation_roles", []) as Array
    for role: String in ["idle", "walk", "run"]:
        if role not in required_animation_roles:
            failures.append("LOT contract must require authored %s animation" % role)

    var banned := contract.get("banned_civilian_assets", []) as Array
    if BANNED_CIVILIAN_ASSET not in banned:
        failures.append("player_character.glb must stay banned for civilian roster")

func _check_rejected_candidate(failures: Array[String]) -> void:
    var verdict := _read_json(ROCKETBOX_VERDICT_PATH)
    if verdict.is_empty():
        failures.append("Rocketbox rejection record missing")
        return
    if str(verdict.get("visual_result", "")) != "JETER":
        failures.append("Rocketbox must remain visually rejected")
    if bool(verdict.get("production_authorized", true)):
        failures.append("Rocketbox must not become production-authorized")

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var text := FileAccess.get_file_as_string(path)
    var parsed = JSON.parse_string(text)
    return parsed as Dictionary if parsed is Dictionary else {}
