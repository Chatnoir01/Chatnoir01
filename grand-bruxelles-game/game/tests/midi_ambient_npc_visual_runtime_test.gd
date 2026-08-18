extends SceneTree

const VISUAL_RUNTIME_SCRIPT := preload("res://game/scripts/midi_ambient_npc_visual_runtime.gd")
const GAIT_RUNTIME_SCRIPT := preload("res://game/scripts/midi_profiled_npc_gait_runtime.gd")
const VISUAL_MODULE_PATH := "res://data/runtime/modules/midi_ambient_npc_visual.json"
const GAIT_MODULE_PATH := "res://data/runtime/modules/midi_profiled_npc_gait.json"


func _init() -> void:
    var failures: Array[String] = []
    var fixture := Node3D.new()
    fixture.name = "MidiNpcVisualFixture"
    root.add_child(fixture)

    var urban_life := Node3D.new()
    urban_life.name = "MidiUrbanLife"
    fixture.add_child(urban_life)

    var person := Node3D.new()
    person.name = "AmbientPedestrian_03"
    urban_life.add_child(person)
    person.add_to_group("ambient_pedestrian")
    for part_name: String in ["Torso", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Head", "Bag"]:
        _add_legacy_box(person, part_name)

    var runtime := VISUAL_RUNTIME_SCRIPT.new()
    var first: Dictionary = runtime.bridge_scene(fixture)
    if int(first.get("bridged", 0)) != 1 or int(first.get("failed", 0)) != 0:
        failures.append("one Midi ambient pedestrian should bridge successfully")

    var proxy := person.get_node_or_null("ProfiledNpcProxy") as NpcAgent
    if proxy == null:
        failures.append("profiled visual proxy is missing")
    else:
        if proxy.active:
            failures.append("visual proxy must not own NPC simulation")
        if proxy.process_mode != Node.PROCESS_MODE_DISABLED:
            failures.append("visual proxy processing must stay disabled")
        if not proxy.is_in_group("npc_agent"):
            failures.append("visual proxy must join npc_agent so the shared quality pass can polish it")
        if absf(proxy.position.y - 0.90) > 0.001:
            failures.append("profiled proxy should place humanoid feet on the existing pedestrian ground")
        if str(proxy.get_meta("visual_profile", "")) != "profiled_humanoid_v2":
            failures.append("visual proxy should advertise the current profiled humanoid version")

        var visual := proxy.get_node_or_null("VisualUpgrade") as Node3D
        if visual == null:
            failures.append("shared HumanoidVisual root is missing")
        else:
            for required_part: String in ["Torso", "Head", "LeftLeg", "RightLeg", "LeftArm", "RightArm"]:
                if visual.get_node_or_null(required_part) == null:
                    failures.append("profiled humanoid part missing: %s" % required_part)
            var detailed_torso := visual.get_node_or_null("Torso") as GeometryInstance3D
            if detailed_torso != null and absf(detailed_torso.visibility_range_end - 90.0) > 0.001:
                failures.append("profiled humanoid should be the near-camera LOD")

    if str(person.get_meta("visual_profile", "")) != "profiled_humanoid_v2":
        failures.append("ambient pedestrian should be marked with the current visual profile")
    if not bool(person.get_meta("shared_humanoid_pipeline", false)):
        failures.append("ambient pedestrian should declare the shared humanoid pipeline")

    for part_name: String in ["Torso", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Head", "Bag"]:
        var legacy := person.get_node_or_null(part_name) as GeometryInstance3D
        if legacy == null:
            failures.append("legacy far-LOD part missing: %s" % part_name)
        elif absf(legacy.visibility_range_begin - 90.0) > 0.001:
            failures.append("legacy cuboid must be excluded from the near-camera range: %s" % part_name)

    var second: Dictionary = runtime.bridge_scene(fixture)
    if int(second.get("bridged", 0)) != 0 or int(second.get("already", 0)) != 1:
        failures.append("visual bridge must be idempotent")
    if person.find_children("ProfiledNpcProxy", "NpcAgent", false, false).size() != 1:
        failures.append("visual bridge must never duplicate the proxy")

    # The gait runtime uses the same ProfiledNpcProxy/VisualUpgrade contract. Verify
    # it observes movement owned by midi_urban_life.gd instead of taking navigation over.
    var gait := GAIT_RUNTIME_SCRIPT.new()
    root.add_child(gait)
    gait.call("_update_profiled_gait", 0.10)
    person.position.x += 0.10
    gait.call("_update_profiled_gait", 0.10)
    var gait_stats: Dictionary = gait.gait_stats()
    if int(gait_stats.get("tracked_pedestrians", 0)) < 1:
        failures.append("profiled gait runtime should discover the upgraded ambient pedestrian")
    if float(gait_stats.get("max_measured_speed_mps", 0.0)) <= 0.0:
        failures.append("profiled gait runtime should observe existing ambient movement")
    if bool(gait_stats.get("changes_navigation", true)):
        failures.append("gait runtime must remain visual-only")

    _assert_module_descriptor(failures, VISUAL_MODULE_PATH, "MidiAmbientNpcVisualRuntime", "res://game/scripts/midi_ambient_npc_visual_runtime.gd")
    _assert_module_descriptor(failures, GAIT_MODULE_PATH, "MidiProfiledNpcGaitRuntime", "res://game/scripts/midi_profiled_npc_gait_runtime.gd")

    var contract: Dictionary = runtime.truth_contract()
    if bool(contract.get("ambient_density_changed", true)):
        failures.append("NPC quality pass must not silently raise the Midi population")
    if str(contract.get("visual_profile", "")) != "profiled_humanoid_v2":
        failures.append("truth contract should expose the current humanoid profile")

    gait.free()
    fixture.free()
    runtime.free()

    if failures.is_empty():
        print("MIDI_AMBIENT_NPC_VISUAL_RUNTIME_OK")
        quit(0)
    else:
        for failure: String in failures:
            push_error("MIDI_AMBIENT_NPC_VISUAL_RUNTIME_FAIL: %s" % failure)
        quit(1)


func _add_legacy_box(parent: Node3D, part_name: String) -> void:
    var part := MeshInstance3D.new()
    part.name = part_name
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.25, 0.35, 0.20)
    part.mesh = mesh
    parent.add_child(part)


func _assert_module_descriptor(failures: Array[String], path: String, expected_name: String, expected_script: String) -> void:
    if not FileAccess.file_exists(path):
        failures.append("runtime module descriptor missing: %s" % path)
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary:
        failures.append("runtime module descriptor is not valid JSON: %s" % path)
        return
    var descriptor := parsed as Dictionary
    if str(descriptor.get("schema", "")) != "grand-bruxelles-runtime-module-v1":
        failures.append("runtime module descriptor schema mismatch: %s" % path)
    if str(descriptor.get("name", "")) != expected_name:
        failures.append("runtime module descriptor name mismatch: %s" % path)
    if str(descriptor.get("path", "")) != expected_script:
        failures.append("runtime module descriptor path mismatch: %s" % path)
    if not bool(descriptor.get("enabled", false)):
        failures.append("runtime module descriptor must be enabled: %s" % path)
