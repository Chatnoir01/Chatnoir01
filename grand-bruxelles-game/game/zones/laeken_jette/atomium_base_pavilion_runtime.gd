extends Node3D

## Source-bounded Atomium base-pavilion facade.
## The 26 m circular plan and fully glazed facade are official heritage facts.
## The facade top uses the 4.027 m lower DSM-DTM median from the overlapping
## UrbIS building footprint. Roof pitch, skylight, doors, stairs and supports
## remain unresolved and are deliberately not rendered here.

@export_file("*.json") var evidence_path := "res://data/sources/laeken_jette/atomium_base_pavilion_runtime_evidence.json"

const SEGMENTS := 64

var pavilion_built := false
var source_diameter_m := 0.0
var measured_facade_height_m := 0.0
var glass_facade_only := true
var roof_geometry_resolved := false
var support_geometry_resolved := false

func build_on_terrain(terrain: Node, anchor_global: Vector3) -> bool:
    if pavilion_built:
        return true
    if terrain == null or not terrain.has_method("sample_height"):
        push_error("AtomiumBasePavilionRuntime: terrain sampler unavailable")
        return false
    var evidence := _load_evidence()
    if evidence.is_empty():
        return false
    var semantics: Dictionary = evidence.get("official_semantics", {})
    var vertical: Dictionary = evidence.get("measured_vertical_evidence", {})
    var status: Dictionary = evidence.get("status", {})
    source_diameter_m = float(semantics.get("diameter_m", 0.0))
    measured_facade_height_m = float(vertical.get("runtime_facade_height_m", 0.0))
    roof_geometry_resolved = bool(status.get("roof_geometry_resolved", true))
    support_geometry_resolved = bool(status.get("support_geometry_resolved", true))
    if absf(source_diameter_m - 26.0) > 0.001 or absf(measured_facade_height_m - 4.027) > 0.001:
        push_error("AtomiumBasePavilionRuntime: source contract drifted")
        return false
    if roof_geometry_resolved or support_geometry_resolved:
        push_error("AtomiumBasePavilionRuntime: unresolved roof/support geometry was promoted")
        return false
    if str(semantics.get("facade", "")) != "fully_glazed":
        push_error("AtomiumBasePavilionRuntime: fully-glazed heritage semantic missing")
        return false

    var mesh := ArrayMesh.new()
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var uvs := PackedVector2Array()
    var indices := PackedInt32Array()
    var radius := source_diameter_m * 0.5
    var top_local_y := measured_facade_height_m
    for i: int in range(SEGMENTS + 1):
        var t := float(i) / float(SEGMENTS)
        var angle := t * TAU
        var x := cos(angle) * radius
        var z := sin(angle) * radius
        var ground_global_y := float(terrain.call("sample_height", anchor_global.x + x, anchor_global.z + z))
        var bottom_local_y := ground_global_y - anchor_global.y + 0.02
        vertices.append(Vector3(x, bottom_local_y, z))
        vertices.append(Vector3(x, top_local_y, z))
        var outward := Vector3(x, 0.0, z).normalized()
        normals.append(outward)
        normals.append(outward)
        uvs.append(Vector2(t, 1.0))
        uvs.append(Vector2(t, 0.0))
    for i: int in range(SEGMENTS):
        var a := i * 2
        var b := a + 1
        var c := a + 2
        var d := a + 3
        indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

    var glass := StandardMaterial3D.new()
    glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    glass.albedo_color = Color(0.42, 0.64, 0.72, 0.40)
    glass.metallic = 0.08
    glass.roughness = 0.12
    glass.cull_mode = BaseMaterial3D.CULL_DISABLED
    glass.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    mesh.surface_set_material(0, glass)

    var facade := MeshInstance3D.new()
    facade.name = "SourceBoundedGlazedPavilionFacade"
    facade.mesh = mesh
    add_child(facade)
    pavilion_built = true
    print("ATOMIUM_BASE_PAVILION_RUNTIME_READY: diameter=%.3f measured_facade_height=%.3f segments=%d roof_resolved=%s supports_resolved=%s" % [source_diameter_m, measured_facade_height_m, SEGMENTS, str(roof_geometry_resolved), str(support_geometry_resolved)])
    return true

func _load_evidence() -> Dictionary:
    if not FileAccess.file_exists(evidence_path):
        push_error("AtomiumBasePavilionRuntime: evidence missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(evidence_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("AtomiumBasePavilionRuntime: invalid evidence")
        return {}
    var evidence := parsed as Dictionary
    if str(evidence.get("crs", "")) != "EPSG:31370":
        push_error("AtomiumBasePavilionRuntime: CRS drifted")
        return {}
    return evidence
