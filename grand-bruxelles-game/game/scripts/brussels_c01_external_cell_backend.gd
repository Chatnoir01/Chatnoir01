extends Node
class_name BrusselsC01ExternalCellBackend

## Candidate external backend for the locked C01 30k LoD2 campaign.
## This file is intentionally NOT wired into BrusselsWorldStreamingRuntime yet.
## Runtime/collision/JOUABLE authorization stays closed until public delivery is proven.

signal cell_loaded(cell_id: String)
signal cell_failed(cell_id: String, reason: String)

const CELL_PATH_PREFIX := "cells/"
const CELL_PATH_SUFFIX := "/world.ndjson"

@export var request_timeout_seconds := 30.0

var _manager: BrusselsCellStreamingManager
var _base_url := ""
var _bindings: Dictionary = {}
var _desired_active: Dictionary = {}
var _instances: Dictionary = {}
var _requests: Dictionary = {}
var _load_count := 0
var _unload_count := 0
var _failed_load_count := 0
var _skipped_hole_faces := 0


func configure_public_base_url(url: String) -> bool:
    var normalized := url.strip_edges()
    while normalized.ends_with("/"):
        normalized = normalized.trim_suffix("/")
    if not normalized.begins_with("https://"):
        return false
    _base_url = normalized
    return true


func get_public_base_url() -> String:
    return _base_url


func bind_manager(manager: BrusselsCellStreamingManager) -> void:
    if _manager == manager:
        return
    if is_instance_valid(_manager):
        if _manager.cell_activation_requested.is_connected(_on_activation_requested):
            _manager.cell_activation_requested.disconnect(_on_activation_requested)
        if _manager.cell_deactivation_requested.is_connected(_on_deactivation_requested):
            _manager.cell_deactivation_requested.disconnect(_on_deactivation_requested)
    _manager = manager
    if not is_instance_valid(_manager):
        return
    _manager.cell_activation_requested.connect(_on_activation_requested)
    _manager.cell_deactivation_requested.connect(_on_deactivation_requested)


func register_external_cell(cell_id: String, metadata: Dictionary) -> bool:
    if cell_id.is_empty() or _bindings.has(cell_id):
        return false
    var relative_path := str(metadata.get("relative_path", ""))
    var digest := str(metadata.get("sha256", "")).to_lower()
    if not _valid_relative_path(cell_id, relative_path):
        return false
    if not _valid_sha256(digest):
        return false
    _bindings[cell_id] = {
        "relative_path": relative_path,
        "sha256": digest,
        "bytes": int(metadata.get("bytes", -1)),
    }
    _desired_active[cell_id] = false
    return true


func build_cell_url(cell_id: String) -> String:
    if _base_url.is_empty() or not _bindings.has(cell_id):
        return ""
    return "%s/%s" % [_base_url, str((_bindings[cell_id] as Dictionary).get("relative_path", ""))]


func _valid_relative_path(cell_id: String, relative_path: String) -> bool:
    if relative_path.contains("..") or relative_path.contains("\\"):
        return false
    return relative_path == "%s%s%s" % [CELL_PATH_PREFIX, cell_id, CELL_PATH_SUFFIX]


func _valid_sha256(value: String) -> bool:
    if value.length() != 64:
        return false
    for code: int in value.to_ascii_buffer():
        var is_digit := code >= 48 and code <= 57
        var is_hex_lower := code >= 97 and code <= 102
        if not is_digit and not is_hex_lower:
            return false
    return true


func sha256_hex(bytes: PackedByteArray) -> String:
    var context := HashingContext.new()
    if context.start(HashingContext.HASH_SHA256) != OK:
        return ""
    if context.update(bytes) != OK:
        return ""
    return context.finish().hex_encode()


func parse_ndjson_text(text: String) -> Dictionary:
    var triangle_vertices := PackedVector3Array()
    var face_count := 0
    var part_count := 0
    var skipped_hole_faces := 0
    var line_number := 0

    for raw_line: String in text.split("\n", false):
        line_number += 1
        var line := raw_line.strip_edges()
        if line.is_empty():
            continue
        var parsed: Variant = JSON.parse_string(line)
        if typeof(parsed) != TYPE_DICTIONARY:
            return {"ok": false, "error": "invalid_json_line_%d" % line_number}
        var row := parsed as Dictionary
        var parts_variant: Variant = row.get("parts", [])
        if not parts_variant is Array:
            return {"ok": false, "error": "invalid_parts_line_%d" % line_number}
        var parts := parts_variant as Array
        part_count += parts.size()

        var has_inner_ring := false
        var exterior_parts: Array[Dictionary] = []
        for part_variant: Variant in parts:
            if typeof(part_variant) != TYPE_DICTIONARY:
                return {"ok": false, "error": "invalid_part_line_%d" % line_number}
            var part := part_variant as Dictionary
            var part_type := int(part.get("part_type", -1))
            if part_type == 3:
                has_inner_ring = true
            elif part_type == 2 or part_type == 4:
                exterior_parts.append(part)
            else:
                return {"ok": false, "error": "unsupported_part_type_%d_line_%d" % [part_type, line_number]}

        if has_inner_ring:
            skipped_hole_faces += 1
            face_count += 1
            continue
        if exterior_parts.is_empty():
            return {"ok": false, "error": "missing_exterior_line_%d" % line_number}

        for part: Dictionary in exterior_parts:
            var ring_result := _triangulate_ring(part.get("vertices", []))
            if not bool(ring_result.get("ok", false)):
                return {"ok": false, "error": "%s_line_%d" % [str(ring_result.get("error", "triangulation_failed")), line_number]}
            var triangles: PackedVector3Array = ring_result["triangle_vertices"]
            triangle_vertices.append_array(triangles)
        face_count += 1

    if face_count == 0:
        return {"ok": false, "error": "empty_payload"}
    return {
        "ok": true,
        "face_count": face_count,
        "part_count": part_count,
        "skipped_hole_faces": skipped_hole_faces,
        "triangle_vertices": triangle_vertices,
    }


func _triangulate_ring(vertices_variant: Variant) -> Dictionary:
    if not vertices_variant is Array:
        return {"ok": false, "error": "vertices_not_array"}
    var raw_vertices := vertices_variant as Array
    var vertices: Array[Vector3] = []
    for vertex_variant: Variant in raw_vertices:
        if not vertex_variant is Array:
            return {"ok": false, "error": "vertex_not_array"}
        var coords := vertex_variant as Array
        if coords.size() != 3:
            return {"ok": false, "error": "vertex_dimension"}
        vertices.append(Vector3(float(coords[0]), float(coords[1]), float(coords[2])))

    if vertices.size() >= 2 and vertices[0].is_equal_approx(vertices[vertices.size() - 1]):
        vertices.pop_back()
    if vertices.size() < 3:
        return {"ok": false, "error": "ring_too_small"}

    var normal := Vector3.ZERO
    for i in range(vertices.size()):
        var current := vertices[i]
        var next := vertices[(i + 1) % vertices.size()]
        normal.x += (current.y - next.y) * (current.z + next.z)
        normal.y += (current.z - next.z) * (current.x + next.x)
        normal.z += (current.x - next.x) * (current.y + next.y)
    if normal.length_squared() < 0.0000001:
        return {"ok": false, "error": "degenerate_ring"}

    var projected := PackedVector2Array()
    var absolute := normal.abs()
    for vertex: Vector3 in vertices:
        if absolute.x >= absolute.y and absolute.x >= absolute.z:
            projected.append(Vector2(vertex.y, vertex.z))
        elif absolute.y >= absolute.z:
            projected.append(Vector2(vertex.x, vertex.z))
        else:
            projected.append(Vector2(vertex.x, vertex.y))

    var indices := Geometry2D.triangulate_polygon(projected)
    if indices.is_empty() or indices.size() % 3 != 0:
        return {"ok": false, "error": "polygon_triangulation_failed"}
    var triangles := PackedVector3Array()
    for index: int in indices:
        triangles.append(vertices[index])
    return {"ok": true, "triangle_vertices": triangles}


func build_mesh_instance(parsed: Dictionary, cell_id: String) -> MeshInstance3D:
    if not bool(parsed.get("ok", false)):
        return null
    var triangle_vertices: PackedVector3Array = parsed.get("triangle_vertices", PackedVector3Array())
    if triangle_vertices.is_empty() or triangle_vertices.size() % 3 != 0:
        return null
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for vertex: Vector3 in triangle_vertices:
        surface.add_vertex(vertex)
    surface.generate_normals()
    var mesh := surface.commit()
    if mesh == null:
        return null
    var instance := MeshInstance3D.new()
    instance.name = "C01ExternalCell_%s" % cell_id
    instance.mesh = mesh
    instance.set_meta("streamed_cell_id", cell_id)
    instance.set_meta("c01_external_candidate", true)
    instance.set_meta("collision_authorized", false)
    return instance


func _on_activation_requested(cell_id: String, _descriptor: Dictionary) -> void:
    if not _bindings.has(cell_id):
        return
    _desired_active[cell_id] = true
    call_deferred("_start_request", cell_id)


func _on_deactivation_requested(cell_id: String) -> void:
    if not _bindings.has(cell_id):
        return
    _desired_active[cell_id] = false
    if _requests.has(cell_id):
        var request := _requests[cell_id] as HTTPRequest
        _requests.erase(cell_id)
        if is_instance_valid(request):
            request.cancel_request()
            request.queue_free()
    if _instances.has(cell_id):
        var instance := _instances[cell_id] as Node
        _instances.erase(cell_id)
        if is_instance_valid(instance):
            instance.queue_free()
        _unload_count += 1


func _start_request(cell_id: String) -> void:
    if not bool(_desired_active.get(cell_id, false)) or _instances.has(cell_id) or _requests.has(cell_id):
        return
    var url := build_cell_url(cell_id)
    if url.is_empty():
        _fail_cell(cell_id, "public_base_url_unconfigured")
        return
    var request := HTTPRequest.new()
    request.name = "C01Request_%s" % cell_id
    request.timeout = request_timeout_seconds
    add_child(request)
    _requests[cell_id] = request
    request.request_completed.connect(_on_request_completed.bind(cell_id, request))
    var error := request.request(url)
    if error != OK:
        _requests.erase(cell_id)
        request.queue_free()
        _fail_cell(cell_id, "request_start_%d" % error)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, cell_id: String, request: HTTPRequest) -> void:
    if _requests.get(cell_id) == request:
        _requests.erase(cell_id)
    if is_instance_valid(request):
        request.queue_free()
    if not bool(_desired_active.get(cell_id, false)):
        return
    if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
        _fail_cell(cell_id, "http_result_%d_code_%d" % [result, response_code])
        return
    var binding := _bindings[cell_id] as Dictionary
    var expected_bytes := int(binding.get("bytes", -1))
    if expected_bytes >= 0 and body.size() != expected_bytes:
        _fail_cell(cell_id, "byte_length_mismatch")
        return
    if sha256_hex(body) != str(binding.get("sha256", "")):
        _fail_cell(cell_id, "sha256_mismatch")
        return
    var parsed := parse_ndjson_text(body.get_string_from_utf8())
    if not bool(parsed.get("ok", false)):
        _fail_cell(cell_id, str(parsed.get("error", "parse_failed")))
        return
    var instance := build_mesh_instance(parsed, cell_id)
    if instance == null:
        _fail_cell(cell_id, "mesh_build_failed")
        return
    add_child(instance)
    _instances[cell_id] = instance
    _load_count += 1
    _skipped_hole_faces += int(parsed.get("skipped_hole_faces", 0))
    cell_loaded.emit(cell_id)


func _fail_cell(cell_id: String, reason: String) -> void:
    _failed_load_count += 1
    cell_failed.emit(cell_id, reason)


func has_active_instance(cell_id: String) -> bool:
    return _instances.has(cell_id) and is_instance_valid(_instances[cell_id]) and not (_instances[cell_id] as Node).is_queued_for_deletion()


func get_metrics() -> Dictionary:
    return {
        "candidate_only": true,
        "public_base_url_configured": not _base_url.is_empty(),
        "registered_cells": _bindings.size(),
        "active_instances": _instances.size(),
        "pending_requests": _requests.size(),
        "load_count": _load_count,
        "unload_count": _unload_count,
        "failed_load_count": _failed_load_count,
        "skipped_hole_faces": _skipped_hole_faces,
        "runtime_mount_authorized": false,
        "collision_authorized": false,
        "jouable_promotion_authorized": false,
    }
