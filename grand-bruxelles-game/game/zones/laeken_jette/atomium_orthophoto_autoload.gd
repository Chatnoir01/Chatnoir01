extends Node

## Presentation-only orthophoto drape for validated Atomium DTM terrain.
## Source pixels are official 2024 Paradigm RGB orthophoto in EPSG:31370.
## No physical geometry, height, vegetation or landmark pose facts are inferred.

const TERRAIN_SCRIPT_PATH := "res://game/zones/laeken_jette/atomium_dtm_terrain.gd"
const ORTHO_PATH := "res://data/orthophoto/laeken_jette/phase1_ortho.jpg"
const ORTHO_MIN_E := 147300.0
const ORTHO_MIN_N := 173650.0
const ORTHO_MAX_E := 149100.0
const ORTHO_MAX_N := 176750.0
const SURFACE_OFFSET_M := 0.025

var attached_overlay_count := 0

func _ready() -> void:
    get_tree().node_added.connect(_on_node_added)
    for node: Node in get_tree().get_nodes_in_group("atomium_dtm_runtime"):
        _on_node_added(node)

func _on_node_added(node: Node) -> void:
    var script := node.get_script() as Script
    if script == null or script.resource_path != TERRAIN_SCRIPT_PATH:
        return
    call_deferred("_attach_when_ready", node)

func _attach_when_ready(terrain: Node) -> void:
    if not is_instance_valid(terrain):
        return
    for _frame: int in range(20):
        if bool(terrain.get("terrain_loaded")):
            break
        await get_tree().process_frame
    if not is_instance_valid(terrain) or not bool(terrain.get("terrain_loaded")):
        push_error("AtomiumOrthophoto: terrain never became ready")
        return
    if terrain.get_node_or_null("OfficialAtomiumOrthophotoDrape") != null:
        return
    if not _build_overlay(terrain):
        push_error("AtomiumOrthophoto: overlay build failed")
        return
    attached_overlay_count += 1

func _build_overlay(terrain: Node) -> bool:
    var texture := load(ORTHO_PATH) as Texture2D
    if texture == null:
        return false
    var width := int(terrain.get("width"))
    var height := int(terrain.get("height"))
    var heights: PackedFloat32Array = terrain.get("heights")
    var valid_mask: PackedByteArray = terrain.get("valid_mask")
    var first_e := float(terrain.get("first_e"))
    var first_n := float(terrain.get("first_n"))
    var step_e := float(terrain.get("step_e"))
    var step_n := float(terrain.get("step_n"))
    var origin_e := float(terrain.get("origin_e"))
    var origin_n := float(terrain.get("origin_n"))
    if width < 2 or height < 2 or heights.size() != width * height or valid_mask.size() != heights.size():
        return false

    var vertices := PackedVector3Array()
    var uvs := PackedVector2Array()
    vertices.resize(width * height)
    uvs.resize(width * height)
    for row: int in range(height):
        for col: int in range(width):
            var index := row * width + col
            var e := first_e + float(col) * step_e
            var n := first_n + float(row) * step_n
            var game_x := e - origin_e
            var game_z := -(n - origin_n)
            vertices[index] = Vector3(game_x, heights[index] + SURFACE_OFFSET_M, game_z)
            var u := (e - ORTHO_MIN_E) / (ORTHO_MAX_E - ORTHO_MIN_E)
            var v := (ORTHO_MAX_N - n) / (ORTHO_MAX_N - ORTHO_MIN_N)
            uvs[index] = Vector2(u, v)

    var indices := PackedInt32Array()
    for row: int in range(height - 1):
        for col: int in range(width - 1):
            var i0 := row * width + col
            var i1 := (row + 1) * width + col
            var i2 := row * width + col + 1
            var i3 := (row + 1) * width + col + 1
            if valid_mask[i0] != 0 and valid_mask[i1] != 0 and valid_mask[i2] != 0:
                indices.append_array(PackedInt32Array([i0, i1, i2]))
            if valid_mask[i2] != 0 and valid_mask[i1] != 0 and valid_mask[i3] != 0:
                indices.append_array(PackedInt32Array([i2, i1, i3]))
    if indices.is_empty():
        return false

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

    var shader := Shader.new()
    shader.code = """shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform sampler2D ortho_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 fallback_color = vec3(0.20, 0.31, 0.14);
void fragment() {
    bool covered = UV.x >= 0.0 && UV.x <= 1.0 && UV.y >= 0.0 && UV.y <= 1.0;
    vec3 rgb = covered ? texture(ortho_texture, UV).rgb : fallback_color;
    ALBEDO = rgb;
    ROUGHNESS = 0.92;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("ortho_texture", texture)
    var instance := MeshInstance3D.new()
    instance.name = "OfficialAtomiumOrthophotoDrape"
    instance.mesh = mesh
    instance.material_override = material
    instance.set_meta("source_crs", "EPSG:31370")
    instance.set_meta("source_year", 2024)
    instance.set_meta("source_resolution_m_per_pixel", 0.87890625)
    instance.set_meta("presentation_only", true)
    terrain.add_child(instance)
    return true
