extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var world := packed.instantiate()
    get_root().add_child(world)
    await process_frame
    await process_frame
    var mount := get_root().get_node_or_null("MidiArchitecturalConcreteSurfaceRuntime")
    if mount == null or not mount.has_method("fonsny_full_entrance_runtime"):
        _fail("Midi visual mount missing full entrance runtime")
        return
    var runtime: Node = mount.fonsny_full_entrance_runtime()
    for _i in range(120):
        if runtime != null and (runtime.built() or runtime.build_failure()):
            break
        await process_frame
    if runtime == null or runtime.build_failure() or not runtime.built():
        _fail("full entrance runtime did not build")
        return
    if runtime.superseded_count() != 8:
        _fail("expected exactly 8 superseded production objects")
        return
    var root := runtime.replacement_root() as Node3D
    if root == null:
        _fail("replacement root missing")
        return
    if int(root.get_meta("source_urban_id", -1)) != 9423:
        _fail("Urban 9423 provenance missing")
        return
    if str(root.get_meta("official_station_plan_authority", "")) != "UrbIS":
        _fail("UrbIS plan authority missing")
        return
    if not bool(root.get_meta("register_dimensions_are_visualization_convention", false)):
        _fail("register dimension disclaimer missing")
        return
    if root.get_node_or_null("PorchLowerRegisterGlazing") == null or root.get_node_or_null("PorchBlindUpperRegister") == null:
        _fail("three-register articulation incomplete")
        return
    var glass_bays := 0
    var columns := 0
    for child in root.get_children():
        if str(child.name).begins_with("PorchGlassBlockBay_"):
            glass_bays += 1
        if str(child.name).begins_with("PorchPolygonalColumn_"):
            columns += 1
    if glass_bays != 3:
        _fail("expected three heritage glass-block bays")
        return
    if columns != 4:
        _fail("expected four polygonal presentation supports")
        return
    var canopy := root.get_node_or_null("PorchPerforatedCanopy") as Node3D
    if canopy == null or not bool(canopy.get_meta("preserves_existing_canopy_size", false)):
        _fail("perforated canopy contract missing")
        return
    var panels := 0
    for child in canopy.get_children():
        if str(child.name).begins_with("CanopyGlassBlockPanel_"):
            panels += 1
    if panels != 20:
        _fail("expected 20 presentation-convention canopy panels")
        return

    runtime.set_replacement_enabled(false)
    if root.visible:
        _fail("baseline toggle did not hide replacement")
        return
    var entrance := get_root().find_child("MidiMainEntranceFonsny", true, false) as Node3D
    for node_name in ["EntranceBlueStoneWall", "EntranceGlazing", "EntranceConcreteCanopy", "CanopyMetalEdge"]:
        var baseline := entrance.get_node_or_null(node_name) as Node3D
        if baseline == null or not baseline.visible:
            _fail("baseline object not restored: %s" % node_name)
            return
    runtime.set_replacement_enabled(true)
    if not root.visible:
        _fail("candidate toggle did not restore replacement")
        return
    for node_name in ["EntranceBlueStoneWall", "EntranceGlazing", "EntranceConcreteCanopy", "CanopyMetalEdge"]:
        var baseline := entrance.get_node_or_null(node_name) as Node3D
        if baseline == null or baseline.visible:
            _fail("candidate still duplicates baseline object: %s" % node_name)
            return
    print("MIDI_FONSNY_FULL_ENTRANCE_TEST_OK bays=%d columns=%d canopy_panels=%d superseded=%d" % [glass_bays, columns, panels, runtime.superseded_count()])
    quit(0)

func _fail(message: String) -> void:
    push_error("MIDI_FONSNY_FULL_ENTRANCE_TEST_FAIL: " + message)
    quit(1)
