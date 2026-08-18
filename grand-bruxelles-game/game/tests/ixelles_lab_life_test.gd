extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"
const EXPECTED_AXIS_ID := "https://databrussels.be/id/streetaxe/71374:1"
const EXPECTED_TARGET_AXIS_ID := "https://databrussels.be/id/streetaxe/71306:2"
const EXPECTED_CIVILIANS := 8
const EXPECTED_MOVING_VEHICLES := 2
const EXPECTED_VISUAL_PROFILE := "profiled_humanoid_v2"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_LAB_LIFE_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _ixelles_catalog_row() -> Dictionary:
    if not FileAccess.file_exists(CATALOG_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
    if not parsed is Dictionary:
        return {}
    var zones: Variant = (parsed as Dictionary).get("zones", [])
    if not zones is Array:
        return {}
    for raw: Variant in zones:
        if raw is Dictionary and str((raw as Dictionary).get("id", "")) == "ixelles":
            return (raw as Dictionary).duplicate(true)
    return {}

func _run() -> void:
    var row := _ixelles_catalog_row()
    if not _expect(not row.is_empty(), "Ixelles catalog row missing"):
        return
    if not _expect(str(row.get("life_script", "")) == "res://game/scripts/ixelles_lab_life.gd", "Ixelles life_script is not registered"):
        return
    var minimum: Variant = row.get("life_minimum", {})
    if not _expect(minimum is Dictionary and int((minimum as Dictionary).get("civilians", 0)) >= 1 and int((minimum as Dictionary).get("moving_vehicles", 0)) >= 1, "Ixelles life minimum contract missing"):
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await process_frame
    var player := main.get_node_or_null("Player") as CharacterBody3D
    if not _expect(player != null, "player missing"):
        return
    player.call("_apply_direct_spawn_from_user_args", PackedStringArray(["spawn=ixelles"]))
    for _frame: int in range(30):
        await process_frame

    var slice := main.get_node_or_null("IxellesDirectMicroSlice")
    if not _expect(slice != null and bool(slice.get("runtime_loaded")), "Ixelles source runtime did not load"):
        return
    var life := main.get_node_or_null("ZoneLife_ixelles")
    if not _expect(life != null, "direct Ixelles entry did not mount ZoneLife_ixelles"):
        return
    if not _expect(life.has_method("has_minimum_playable_life") and bool(life.call("has_minimum_playable_life")), "Ixelles life minimum is not satisfied"):
        return

    var counts: Variant = life.call("get_counts") if life.has_method("get_counts") else {}
    if not _expect(counts is Dictionary, "Ixelles life counts unavailable"):
        return
    if not _expect(int((counts as Dictionary).get("civilians", 0)) == EXPECTED_CIVILIANS, "Ixelles civilian count drifted"):
        return
    if not _expect(int((counts as Dictionary).get("moving_vehicles", 0)) == EXPECTED_MOVING_VEHICLES, "Ixelles moving vehicle count drifted"):
        return

    var contract: Variant = life.call("source_contract") if life.has_method("source_contract") else {}
    if not _expect(contract is Dictionary, "Ixelles life source contract unavailable"):
        return
    if not _expect(str((contract as Dictionary).get("vehicle_axis_id", "")) == EXPECTED_AXIS_ID, "moving vehicles are not bound to accepted official StreetAxis"):
        return
    if not _expect(str((contract as Dictionary).get("target_axis_id", "")) == EXPECTED_TARGET_AXIS_ID, "life sightline drifted from accepted Ixelles target StreetAxis"):
        return
    if not _expect(str((contract as Dictionary).get("pedestrian_surface_type", "")) == "SW", "pedestrians are not bound to official sidewalk surfaces"):
        return
    if not _expect(int((contract as Dictionary).get("pedestrian_anchor_count", 0)) == EXPECTED_CIVILIANS, "pedestrian source-anchor count drifted"):
        return
    if not _expect(bool((contract as Dictionary).get("all_pedestrian_anchors_inside_source", false)), "one or more pedestrian anchors escaped official sidewalk polygons"):
        return
    if not _expect(bool((contract as Dictionary).get("all_pedestrian_anchors_in_spawn_view", false)), "one or more pedestrian anchors escaped the accepted direct-spawn view"):
        return
    if not _expect(not bool((contract as Dictionary).get("lane_geometry_claimed", true)), "LABO traffic presentation incorrectly claims surveyed lane geometry"):
        return

    var civilians := main.find_children("IxellesCivilian_*", "Node3D", true, false)
    if not _expect(civilians.size() == EXPECTED_CIVILIANS, "visible Ixelles civilian nodes missing"):
        return
    for civilian: Node in civilians:
        if not _expect(str(civilian.get_meta("source_surface_type", "")) == "SW" and bool(civilian.get_meta("source_point_inside_official_surface", false)) and bool(civilian.get_meta("source_point_in_direct_spawn_view", false)), "civilian source/view provenance missing"):
            return
        if not _expect(str(civilian.get_meta("visual_profile", "")) == EXPECTED_VISUAL_PROFILE and bool(civilian.get_meta("shared_humanoid_pipeline", false)), "civilian did not receive shared profiled humanoid visual"):
            return
        var proxy := civilian.get_node_or_null("VisualAgent") as NpcAgent
        if not _expect(proxy != null and not proxy.active, "stationary Ixelles visual NpcAgent proxy missing or active"):
            return
        var visual := proxy.get_node_or_null("HumanoidVisual") as Node3D
        if not _expect(visual != null and visual.get_node_or_null("Torso") != null and visual.get_node_or_null("Head") != null and visual.get_node_or_null("LeftArm") != null and visual.get_node_or_null("RightLeg") != null, "profiled humanoid mesh parts missing"):
            return
        if not _expect(str(visual.get_meta("custom_mesh_pipeline", "")) == "array_mesh_profiled_v2", "Ixelles civilian is not using profiled NPC mesh pipeline"):
            return
        var visible_legacy := 0
        for child: Node in civilian.get_children():
            if child is VisualInstance3D and (child as VisualInstance3D).visible:
                visible_legacy += 1
        if not _expect(visible_legacy == 0, "legacy cuboid civilian visual remains visible"):
            return

    var life_runtime := root.find_child("IxellesLabLifeRuntime", true, false)
    if not _expect(life_runtime != null and life_runtime.has_method("upgraded_civilian_count") and int(life_runtime.call("upgraded_civilian_count")) == EXPECTED_CIVILIANS, "Ixelles runtime did not upgrade all civilian visuals"):
        return

    var before: Variant = life.call("moving_probe_position") if life.has_method("moving_probe_position") else null
    if not _expect(before is Vector3, "moving vehicle probe unavailable"):
        return
    for _frame: int in range(45):
        await process_frame
    var after: Variant = life.call("moving_probe_position")
    if not _expect(after is Vector3 and (after as Vector3).distance_to(before as Vector3) > 0.02, "Ixelles moving vehicle did not move"):
        return

    print("IXELLES_LAB_LIFE_OK: zone=ixelles status=LABO civilians=%d moving=%d vehicle_axis=%s target_axis=%s pedestrian_surface=SW direct_entry=true anchors_in_spawn_view=true humanoid_profile=%s geography_expanded=false" % [EXPECTED_CIVILIANS, EXPECTED_MOVING_VEHICLES, EXPECTED_AXIS_ID, EXPECTED_TARGET_AXIS_ID, EXPECTED_VISUAL_PROFILE])
    quit(0)
