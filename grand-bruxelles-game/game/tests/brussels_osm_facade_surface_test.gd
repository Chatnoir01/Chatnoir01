extends SceneTree

const MATERIAL_PATH := "res://game/scripts/brussels_osm_facade_surface_material.gd"
const RUNTIME_PATH := "res://game/scripts/brussels_osm_facade_surface_runtime.gd"
const ARTICULATION_RUNTIME_NAME := "BrusselsOsmFacadeArticulationRuntime"
const MATERIAL_FAMILY := "brussels_osm_facade_surface_v1"
const ARTICULATION_FAMILY := "brussels_osm_facade_articulation_v1"
const MIN_GENERIC_BUILDINGS := 40
const MAX_BIND_FRAMES := 240

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_FACADE_SURFACE_FAIL: %s" % message)
    quit(1)

func _wait_for_runtime(runtime: Node) -> bool:
    for _frame: int in range(MAX_BIND_FRAMES):
        await process_frame
        if runtime.ready_complete() and not runtime.failed() and runtime.applied_building_count() >= MIN_GENERIC_BUILDINGS:
            return true
    return false

func _wait_for_articulation(runtime: Node) -> bool:
    for _frame: int in range(MAX_BIND_FRAMES):
        await process_frame
        if runtime.failed():
            return false
        if runtime.ready_complete() and runtime.applied_building_count() >= MIN_GENERIC_BUILDINGS:
            return true
    return false

func _validate_bound_runtime(runtime: Node, label: String) -> bool:
    if not runtime.ready_complete():
        _fail("%s runtime did not finish" % label)
        return false
    if runtime.failed():
        _fail("%s runtime reported failure" % label)
        return false
    if runtime.applied_building_count() < MIN_GENERIC_BUILDINGS:
        _fail("%s too few generic OSM buildings received shared surface" % label)
        return false
    if runtime.shared_material_count() < 2:
        _fail("%s shared facade material family is not reusable" % label)
        return false
    if not runtime.geometry_unchanged():
        _fail("%s facade surface runtime changed or retained stale building geometry" % label)
        return false
    if runtime.hero_replacement_count() != 0:
        _fail("%s facade surface runtime touched hero replacement geometry" % label)
        return false
    if runtime.material_family() != MATERIAL_FAMILY:
        _fail("%s unexpected material family" % label)
        return false
    return true

func _validate_articulation_runtime(runtime: Node, label: String) -> bool:
    if not runtime.ready_complete():
        _fail("%s articulation runtime did not finish" % label)
        return false
    if runtime.failed():
        _fail("%s articulation runtime reported failure" % label)
        return false
    if runtime.applied_building_count() < MIN_GENERIC_BUILDINGS:
        _fail("%s too few authoritative buildings received facade articulation" % label)
        return false
    if not runtime.geometry_unchanged():
        _fail("%s articulation runtime changed building geometry" % label)
        return false
    return true

func _make_nested_decoy() -> Node3D:
    var wrapper := Node3D.new()
    wrapper.name = "ForeignFacadeOwner"
    var decoy_main := Node3D.new()
    decoy_main.name = "ForeignNestedMain"
    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    var buildings := Node3D.new()
    buildings.name = "GeneratedBuildings"
    var building := CSGPolygon3D.new()
    building.name = "Building_Decoy"
    building.polygon = PackedVector2Array([Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 3.0), Vector2(-1.0, 3.0)])
    building.depth = 1.0
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.55, 0.52, 0.48, 1.0)
    material.roughness = 0.8
    building.material = material
    buildings.add_child(building)
    osm.add_child(buildings)
    decoy_main.add_child(osm)
    wrapper.add_child(decoy_main)
    return wrapper

func _run() -> void:
    if not FileAccess.file_exists(MATERIAL_PATH):
        _fail("reusable facade surface material missing")
        return
    if not FileAccess.file_exists(RUNTIME_PATH):
        _fail("reusable facade surface runtime missing")
        return

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return

    var runtime := root.get_node_or_null("BrusselsOsmFacadeSurfaceRuntime")
    if runtime == null:
        _fail("shared facade surface runtime missing")
        return
    var articulation := root.get_node_or_null(ARTICULATION_RUNTIME_NAME)
    if articulation == null:
        _fail("shared facade articulation runtime missing")
        return

    var foreign_wrapper := _make_nested_decoy()
    root.add_child(foreign_wrapper)
    for _frame: int in range(8):
        await process_frame
    if runtime.ready_complete() or runtime.applied_building_count() != 0:
        _fail("foreign nested GeneratedBuildings captured facade surface authority")
        return
    if articulation.ready_complete() or articulation.applied_building_count() != 0:
        _fail("foreign nested GeneratedBuildings captured facade articulation authority before base bind")
        return
    var foreign_building := foreign_wrapper.get_node_or_null("ForeignNestedMain/BrusselsOSM/GeneratedBuildings/Building_Decoy") as CSGPolygon3D
    if foreign_building == null:
        _fail("foreign facade decoy missing")
        return
    if str(foreign_building.get_meta("material_family", "")) == MATERIAL_FAMILY:
        _fail("foreign nested facade building received owned material metadata")
        return

    var first_scene := packed.instantiate() as Node3D
    root.add_child(first_scene)

    if not await _wait_for_runtime(runtime):
        _fail("first scene facade bind timed out")
        return
    if not _validate_bound_runtime(runtime, "first scene"):
        return
    if not await _wait_for_articulation(articulation):
        _fail("first scene articulation bind failed after authoritative surface became ready")
        return
    if not _validate_articulation_runtime(articulation, "first scene"):
        return
    var first_count: int = int(runtime.applied_building_count())
    if str(foreign_building.get_meta("material_family", "")) == MATERIAL_FAMILY:
        _fail("foreign nested facade building was mutated after authoritative bind")
        return
    if str(foreign_building.get_meta("facade_articulation_family", "")) == ARTICULATION_FAMILY:
        _fail("foreign nested facade building received articulation ownership")
        return

    first_scene.queue_free()
    for _frame: int in range(4):
        await process_frame

    var replacement_scene := packed.instantiate() as Node3D
    root.add_child(replacement_scene)

    if not await _wait_for_runtime(runtime):
        _fail("replacement scene facade rebind timed out")
        return
    if not _validate_bound_runtime(runtime, "replacement scene"):
        return
    if runtime.applied_building_count() != first_count:
        _fail("replacement scene building coverage drifted: first=%d replacement=%d" % [first_count, runtime.applied_building_count()])
        return
    if not await _wait_for_articulation(articulation):
        _fail("replacement scene articulation rebind timed out")
        return
    if not _validate_articulation_runtime(articulation, "replacement scene"):
        return

    print("BRUSSELS_OSM_FACADE_SURFACE_OK: buildings=%d materials=%d family=%s geometry_changed=false hero_replacements=0 scene_rebind=true foreign_nested_owner_rejected=true articulation_owner_isolated=true" % [runtime.applied_building_count(), runtime.shared_material_count(), runtime.material_family()])
    quit(0)