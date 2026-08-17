extends Node3D

const CONTRACT_PATH := "res://data/qa/grand_place_brasseurs_wall_skin_contract.json"
const EXPECTED_BUILDING := "1639974"
const EXPECTED_WALL := "10945501"
const EXPECTED_TRIANGLES := 3
const EXPECTED_SPAN := 8.7490357183
const TRIANGLE_FAN := [0, 1, 2, 0, 2, 4, 0, 4, 3]

var skin_ready := false
var building_id := EXPECTED_BUILDING
var source_wall_id := EXPECTED_WALL
var official_triangle_count := EXPECTED_TRIANGLES
var official_span_m := EXPECTED_SPAN
var skin_surface_count := 0
var detail_count := 0
var free_standing_grid_present := false
var geometry_claimed_surveyed := false
var triangulation_role := "presentation_retriangulation_of_exact_official_envelope"
var _skin: MeshInstance3D

func _ready() -> void:
    call_deferred("_build")

func _build() -> void:
    if not FileAccess.file_exists(CONTRACT_PATH):
        return
    var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    if not (raw is Dictionary):
        return
    var contract := raw as Dictionary
    if str(contract.get("building_id", "")) != EXPECTED_BUILDING:
        return
    if str(contract.get("front_wall_id", "")) != EXPECTED_WALL:
        return
    if int(contract.get("triangle_count", 0)) != EXPECTED_TRIANGLES:
        return
    if abs(float(contract.get("horizontal_span_m", 0.0)) - EXPECTED_SPAN) > 0.000001:
        return
    if str(contract.get("surface_policy", "")) != "one_continuous_official_wall_skin_before_relief":
        return
    if bool(contract.get("free_standing_architectural_grid_allowed", true)):
        return
    if bool(contract.get("detail_relief_allowed_before_skin_ready", true)):
        return
    if bool(contract.get("raw_photo_pixels_shipped", true)):
        return
    if bool(contract.get("photo_geometry_claimed_surveyed", true)):
        return

    var raw_vertices: Array = contract.get("world_vertices", [])
    if raw_vertices.size() != 5:
        return
    var source_vertices: Array[Vector3] = []
    for raw_vertex: Variant in raw_vertices:
        if not (raw_vertex is Array) or (raw_vertex as Array).size() != 3:
            return
        var values := raw_vertex as Array
        source_vertices.append(Vector3(float(values[0]), float(values[1]), float(values[2])))

    var surface_vertices := PackedVector3Array()
    for index: int in TRIANGLE_FAN:
        surface_vertices.append(source_vertices[index])

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = surface_vertices

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    if mesh.get_surface_count() != 1:
        return

    var stone := StandardMaterial3D.new()
    stone.albedo_color = Color(0.72, 0.66, 0.54, 1.0)
    stone.roughness = 0.82
    stone.cull_mode = BaseMaterial3D.CULL_DISABLED

    _skin = MeshInstance3D.new()
    _skin.name = "OfficialBrasseursWallSkin"
    _skin.mesh = mesh
    _skin.material_override = stone
    add_child(_skin)

    skin_surface_count = mesh.get_surface_count()
    detail_count = 0
    free_standing_grid_present = false
    geometry_claimed_surveyed = false
    set_meta("building_id", EXPECTED_BUILDING)
    set_meta("source_wall_id", EXPECTED_WALL)
    set_meta("source_face_triangle_count", EXPECTED_TRIANGLES)
    set_meta("triangulation_role", triangulation_role)
    set_meta("raw_photo_pixels_shipped", false)
    set_meta("detail_relief_present", false)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    skin_ready = true
    print("GRAND_PLACE_BRASSEURS_WALL_SKIN_READY: building=1639974 wall=10945501 triangles=3 surfaces=1 details=0")
