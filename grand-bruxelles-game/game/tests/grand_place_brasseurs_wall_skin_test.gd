extends SceneTree

const RUNTIME_PATH := "res://game/scripts/grand_place_brasseurs_wall_skin_runtime.gd"
const WALL_NODE := "GrandPlaceBrasseursWall10945501"
const EXPECTED_BUILDING_ID := "1639974"
const EXPECTED_WALL_ID := "10945501"
const EXPECTED_VERTEX_COUNT := 5
const EXPECTED_TRIANGLE_COUNT := 3
const EXPECTED_SPAN_M := 8.749036
const EXPECTED_Y_MAX_M := 24.746

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRASSEURS_WALL_SKIN_FAIL: " + message)
    quit(1)

func _run() -> void:
    if not ResourceLoader.exists(RUNTIME_PATH):
        _fail("coherent wall-skin runtime missing")
        return
    var script := load(RUNTIME_PATH)
    if script == null:
        _fail("cannot load coherent wall-skin runtime")
        return
    var runtime := script.new()
    root.add_child(runtime)
    await process_frame
    await process_frame

    if not runtime.has_method("source_contract"):
        _fail("source_contract() missing")
        return
    var contract: Dictionary = runtime.source_contract()
    if str(contract.get("building_id", "")) != EXPECTED_BUILDING_ID:
        _fail("wrong UrbIS building id")
        return
    if str(contract.get("front_wall_id", "")) != EXPECTED_WALL_ID:
        _fail("wrong UrbIS front wall id")
        return
    if int(contract.get("unique_vertex_count", -1)) != EXPECTED_VERTEX_COUNT:
        _fail("official unique-vertex count changed")
        return
    if int(contract.get("triangle_count", -1)) != EXPECTED_TRIANGLE_COUNT:
        _fail("official triangle count changed")
        return
    if absf(float(contract.get("horizontal_span_m", 0.0)) - EXPECTED_SPAN_M) > 0.0005:
        _fail("official wall span changed")
        return
    if absf(float(contract.get("world_y_max_m", 0.0)) - EXPECTED_Y_MAX_M) > 0.0005:
        _fail("official wall vertical extent changed")
        return
    if bool(contract.get("outward_offset_used", true)):
        _fail("outward displacement is forbidden")
        return
    if int(contract.get("detail_count", -1)) != 0:
        _fail("base-skin proof must have details=0")
        return

    var mesh_instance := runtime.get_node_or_null(WALL_NODE) as MeshInstance3D
    if mesh_instance == null or mesh_instance.mesh == null:
        _fail("continuous wall mesh missing")
        return
    var mesh := mesh_instance.mesh as ArrayMesh
    if mesh == null or mesh.get_surface_count() != 1:
        _fail("wall skin must be one continuous mesh surface")
        return
    var arrays := mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    if vertices.size() != EXPECTED_TRIANGLE_COUNT * 3:
        _fail("mesh must emit exactly the three source-wall triangles")
        return
    var unique := {}
    for vertex: Vector3 in vertices:
        unique["%.4f|%.4f|%.4f" % [vertex.x, vertex.y, vertex.z]] = true
    if unique.size() != EXPECTED_VERTEX_COUNT:
        _fail("mesh must use exactly five official unique vertices")
        return

    print("BRASSEURS_WALL_SKIN_OK: building=1639974 wall=10945501 unique_vertices=5 triangles=3 details=0 outward_offset=false")
    quit(0)
