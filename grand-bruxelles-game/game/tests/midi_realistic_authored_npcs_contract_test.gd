extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/midi_ambient_npc_visual_runtime.gd")
const LEGACY_NAMES := ["Torso", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Head", "Bag"]
const CONTRACT_PATH := "res://data/qa/midi_realistic_authored_npcs_contract.json"
const ROCKETBOX_VERDICT_PATH := "res://data/qa/midi_realistic_authored_npcs_candidate_verdict.json"
const BANNED_CIVILIAN_ASSET := "res://assets/characters/player_character.glb"

func _init() -> void:
    var failures: Array[String] = []
    _check_runtime_contract(failures)
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
