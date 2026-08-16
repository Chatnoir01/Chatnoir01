extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_MIDI_SIDEWALK_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await process_frame
    var player := main.get_node_or_null("Player") as CharacterBody3D
    if not _expect(player != null, "player missing"):
        return
    player.call("_apply_direct_spawn_from_user_args", PackedStringArray(["spawn=ixelles"]))
    for _frame: int in range(16):
        await process_frame

    var slice := main.get_node_or_null("IxellesDirectMicroSlice")
    if not _expect(slice != null and bool(slice.get("runtime_loaded")), "Ixelles LABO runtime did not load"):
        return
    if not _expect(int(slice.get("street_surface_count")) == 309 and int(slice.get("street_segment_count")) == 277, "Ixelles street contract drifted"):
        return
    if not _expect(int(slice.get("building_count")) == 260 and int(slice.get("skipped_unapproved_height_buildings")) == 460, "Ixelles building/no-invention contract drifted"):
        return
    if not _expect(slice.find_child("OfficialIxellesDTMCollision", true, false) != null, "Ixelles DTM collision missing"):
        return

    var runtime := root.get_node_or_null("IxellesMidiSidewalkRuntime")
    if not _expect(runtime != null and bool(runtime.call("ready_complete")) and not bool(runtime.call("failed")), "Ixelles sidewalk runtime not ready"):
        return
    if not _expect(int(runtime.call("applied_surface_count")) == 1, "Midi sidewalk recipe not applied"):
        return
    var material := runtime.call("enhanced_material") as ShaderMaterial
    if not _expect(material != null, "enhanced sidewalk material missing"):
        return
    if not _expect(str(material.get_meta("recipe_source", "")) == "midi" and str(material.get_meta("zone", "")) == "ixelles", "material provenance drifted"):
        return
    if not _expect(not bool(material.get_meta("geometry_changed", true)), "material lot changed geometry"):
        return

    var sidewalk := slice.find_child("StreetSurfaces_SW", true, false) as MeshInstance3D
    if not _expect(sidewalk != null and sidewalk.material_override == material, "official Ixelles sidewalk mesh is not using the Midi recipe"):
        return

    print("IXELLES_MIDI_SIDEWALK_OK: zone=ixelles status=LABO surfaces=1 recipe=midi streets=309 axes=277 buildings=260 skipped=460 geometry_changed=false collision_preserved=true")
    quit(0)
