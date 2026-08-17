extends SceneTree

const MATERIAL_PATH := "res://game/scripts/brussels_osm_facade_surface_material.gd"
const RUNTIME_PATH := "res://game/scripts/brussels_osm_facade_surface_runtime.gd"
const MATERIAL_FAMILY := "brussels_osm_facade_surface_v1"
const MIN_GENERIC_BUILDINGS := 40

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_FACADE_SURFACE_FAIL: %s" % message)
    quit(1)

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
    var scene := packed.instantiate() as Node3D
    root.add_child(scene)

    var runtime := root.get_node_or_null("BrusselsOsmFacadeSurfaceRuntime")
    if runtime == null:
        _fail("shared facade surface runtime missing")
        return

    for _frame: int in range(240):
        await process_frame
        if runtime.ready_complete():
            break
    if not runtime.ready_complete():
        _fail("runtime did not finish")
        return
    if runtime.failed():
        _fail("runtime reported failure")
        return
    if runtime.applied_building_count() < MIN_GENERIC_BUILDINGS:
        _fail("too few generic OSM buildings received shared surface")
        return
    if runtime.shared_material_count() < 2:
        _fail("shared facade material family is not reusable")
        return
    if not runtime.geometry_unchanged():
        _fail("facade surface runtime changed building geometry")
        return
    if runtime.hero_replacement_count() != 0:
        _fail("facade surface runtime touched hero replacement geometry")
        return
    if runtime.material_family() != MATERIAL_FAMILY:
        _fail("unexpected material family")
        return

    print("BRUSSELS_OSM_FACADE_SURFACE_OK: buildings=%d materials=%d family=%s geometry_changed=false hero_replacements=0" % [runtime.applied_building_count(), runtime.shared_material_count(), runtime.material_family()])
    quit(0)
