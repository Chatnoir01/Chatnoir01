extends RefCounted
class_name AuthoredGeometryPayload

const MAGIC := "GBAG"
const VERSION := 1

static func build_from_parts(payload_dir: String, part_count: int, raw_bytes: int) -> Node3D:
    if part_count <= 0 or raw_bytes <= 0:
        return null
    var encoded := ""
    for index: int in range(part_count):
        var path := "%s/part_%02d.txt" % [payload_dir, index]
        if not FileAccess.file_exists(path):
            return null
        encoded += FileAccess.get_file_as_string(path).strip_edges()
    if encoded.is_empty():
        return null
    var compressed: PackedByteArray = Marshalls.base64_to_raw(encoded)
    if compressed.is_empty():
        return null
    var raw: PackedByteArray = compressed.decompress(raw_bytes, FileAccess.COMPRESSION_DEFLATE)
    if raw.size() != raw_bytes:
        return null
    return _decode(raw)

static func _decode(raw: PackedByteArray) -> Node3D:
    if raw.size() < 32:
        return null
    if raw.slice(0, 4).get_string_from_ascii() != MAGIC:
        return null
    var offset := 4
    var version := raw.decode_u8(offset)
    offset += 1
    if version != VERSION:
        return null
    var group_count := raw.decode_u8(offset)
    offset += 1
    offset += 2 # reserved u16
    if group_count <= 0:
        return null
    var bounds_min := Vector3(
        raw.decode_float(offset),
        raw.decode_float(offset + 4),
        raw.decode_float(offset + 8)
    )
    offset += 12
    var bounds_max := Vector3(
        raw.decode_float(offset),
        raw.decode_float(offset + 4),
        raw.decode_float(offset + 8)
    )
    offset += 12
    var span := bounds_max - bounds_min
    if span.x <= 0.0 or span.y <= 0.0 or span.z <= 0.0:
        return null
    var root := Node3D.new()
    root.name = "AuthoredSourceDerivedLOD"
    root.set_meta("source_bounds_min", bounds_min)
    root.set_meta("source_bounds_max", bounds_max)
    root.set_meta("source_group_count", group_count)
    var total_triangles := 0
    var total_vertices := 0
    for group_index: int in range(group_count):
        if offset + 5 > raw.size():
            root.free()
            return null
        var name_len := raw.decode_u8(offset)
        offset += 1
        var vertex_count := raw.decode_u16(offset)
        offset += 2
        var index_count := raw.decode_u16(offset)
        offset += 2
        if name_len <= 0 or vertex_count <= 0 or index_count <= 0 or index_count % 3 != 0:
            root.free()
            return null
        var required := name_len + vertex_count * 6 + vertex_count * 3 + index_count * 2
        if offset + required > raw.size():
            root.free()
            return null
        var material_name := raw.slice(offset, offset + name_len).get_string_from_utf8()
        offset += name_len
        var vertices := PackedVector3Array()
        vertices.resize(vertex_count)
        for vertex_index: int in range(vertex_count):
            var qx := raw.decode_u16(offset)
            var qy := raw.decode_u16(offset + 2)
            var qz := raw.decode_u16(offset + 4)
            offset += 6
            vertices[vertex_index] = bounds_min + Vector3(
                float(qx) / 65535.0 * span.x,
                float(qy) / 65535.0 * span.y,
                float(qz) / 65535.0 * span.z
            )
        var normals := PackedVector3Array()
        normals.resize(vertex_count)
        for normal_index: int in range(vertex_count):
            var nx := _decode_s8(raw.decode_u8(offset))
            var ny := _decode_s8(raw.decode_u8(offset + 1))
            var nz := _decode_s8(raw.decode_u8(offset + 2))
            offset += 3
            var normal := Vector3(float(nx), float(ny), float(nz)) / 127.0
            normals[normal_index] = normal.normalized() if normal.length_squared() > 0.000001 else Vector3.UP
        var indices := PackedInt32Array()
        indices.resize(index_count)
        for index_index: int in range(index_count):
            var value := raw.decode_u16(offset)
            offset += 2
            if value >= vertex_count:
                root.free()
                return null
            indices[index_index] = value
        var arrays := []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = vertices
        arrays[Mesh.ARRAY_NORMAL] = normals
        arrays[Mesh.ARRAY_INDEX] = indices
        var mesh := ArrayMesh.new()
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        var mesh_instance := MeshInstance3D.new()
        mesh_instance.name = "Authored_%02d_%s" % [group_index, _safe_name(material_name)]
        mesh_instance.mesh = mesh
        mesh_instance.material_override = _material_for(material_name)
        root.add_child(mesh_instance)
        total_vertices += vertex_count
        total_triangles += index_count / 3
    if offset != raw.size():
        root.free()
        return null
    root.set_meta("source_vertices", total_vertices)
    root.set_meta("source_triangles", total_triangles)
    root.set_meta("source_derived_lod", true)
    return root

static func _decode_s8(value: int) -> int:
    return value - 256 if value > 127 else value

static func _safe_name(value: String) -> String:
    var result := value
    for token: String in [" ", "-", ".", "/", "\\", ":"]:
        result = result.replace(token, "_")
    return result

static func _material_for(material_name: String) -> StandardMaterial3D:
    var key := material_name.to_lower()
    var material := StandardMaterial3D.new()
    material.roughness = 0.34
    if "glass" in key:
        material.albedo_color = Color(0.055, 0.09, 0.12, 0.62)
        if "red" in key:
            material.albedo_color = Color(0.58, 0.025, 0.025, 0.72)
            material.emission_enabled = true
            material.emission = Color(0.24, 0.0, 0.0, 1.0)
            material.emission_energy_multiplier = 0.65
        elif "clear" in key:
            material.albedo_color = Color(0.32, 0.40, 0.44, 0.42)
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
        material.roughness = 0.16
    elif "paint" in key or "car-body" in key:
        material.albedo_color = Color(0.90, 0.91, 0.92, 1.0)
        material.metallic = 0.18
        material.roughness = 0.28
    elif "chrome" in key or "metal" in key:
        material.albedo_color = Color(0.18, 0.20, 0.22, 1.0)
        material.metallic = 0.72
        material.roughness = 0.24
    elif "rubber" in key or "plastic" in key or "grill" in key or "grille" in key or "wiper" in key:
        material.albedo_color = Color(0.025, 0.028, 0.032, 1.0)
        material.metallic = 0.02
        material.roughness = 0.72
    else:
        material.albedo_color = Color(0.30, 0.32, 0.34, 1.0)
        material.metallic = 0.18
        material.roughness = 0.42
    return material
