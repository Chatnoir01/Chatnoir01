extends "res://game/zones/ixelles/ixelles_microslice.gd"
class_name IxellesStreamedMicroSlice

## Streaming-specific Ixelles adapter.
## Keeps the proven source-backed data contract unchanged while spreading heavy
## geometry work over multiple frames for Web/mobile-friendly prefetching.

@export var terrain_vertex_rows_per_frame := 24
@export var terrain_index_rows_per_frame := 40

var stream_phase_ms: Dictionary = {}
var stream_total_ms := 0
var stream_build_started := false
var terrain_vertex_chunks := 0
var terrain_index_chunks := 0
var stream_collision_enabled := false
var dynamic_collision_build_ms := 0

func _ready() -> void:
    call_deferred("_build_streamed")

func _build_streamed() -> void:
    if stream_build_started:
        return
    stream_build_started = true
    var total_started := Time.get_ticks_msec()

    var phase_started := Time.get_ticks_msec()
    if not _load_contracts():
        push_error("IxellesStreamedMicroSlice: runtime contracts unavailable")
        return
    _make_materials()
    stream_phase_ms["contracts_materials"] = Time.get_ticks_msec() - phase_started
    print("IXELLES_STREAM_PHASE: contracts_materials ms=%d" % int(stream_phase_ms["contracts_materials"]))
    await get_tree().process_frame

    await _build_terrain_over_frames()
    await get_tree().process_frame

    if build_collision:
        phase_started = Time.get_ticks_msec()
        _build_collision()
        stream_phase_ms["terrain_collision"] = Time.get_ticks_msec() - phase_started
        await get_tree().process_frame

    phase_started = Time.get_ticks_msec()
    _build_street_surfaces()
    stream_phase_ms["street_surfaces"] = Time.get_ticks_msec() - phase_started
    print("IXELLES_STREAM_PHASE: street_surfaces ms=%d" % int(stream_phase_ms["street_surfaces"]))
    await get_tree().process_frame

    phase_started = Time.get_ticks_msec()
    _build_strong_height_candidate_buildings()
    stream_phase_ms["buildings"] = Time.get_ticks_msec() - phase_started
    print("IXELLES_STREAM_PHASE: buildings ms=%d" % int(stream_phase_ms["buildings"]))

    runtime_loaded = terrain_triangle_count == 125000 and street_surface_count == 309 and street_segment_count == 277 and building_count == eligible_height_count and building_count == 260 and skipped_unapproved_height_buildings == 460
    stream_total_ms = Time.get_ticks_msec() - total_started
    if runtime_loaded:
        _sync_stream_collision()
        print("IXELLES_STREAMED_MICROSLICE_READY: cell=%s triangles=%d streets=%d buildings=%d total_ms=%d max_phase_ms=%d vertex_chunks=%d index_chunks=%d" % [cell_id, terrain_triangle_count, street_surface_count, building_count, stream_total_ms, get_max_stream_phase_ms(), terrain_vertex_chunks, terrain_index_chunks])

func set_stream_collision_enabled(enabled: bool) -> void:
    if stream_collision_enabled == enabled:
        if runtime_loaded:
            _sync_stream_collision()
        return
    stream_collision_enabled = enabled
    if runtime_loaded:
        call_deferred("_sync_stream_collision")

func _sync_stream_collision() -> void:
    if not runtime_loaded:
        return
    var existing := find_child("OfficialIxellesDTMCollision", true, false)
    if stream_collision_enabled:
        if existing != null:
            return
        var started := Time.get_ticks_msec()
        _build_collision()
        dynamic_collision_build_ms = Time.get_ticks_msec() - started
        print("IXELLES_STREAM_COLLISION: enabled build_ms=%d" % dynamic_collision_build_ms)
        return
    if existing != null:
        existing.queue_free()
        print("IXELLES_STREAM_COLLISION: disabled")

func _record_phase_peak(phase_name: String, elapsed_ms: int) -> void:
    stream_phase_ms[phase_name] = maxi(int(stream_phase_ms.get(phase_name, 0)), elapsed_ms)

func _build_terrain_over_frames() -> void:
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    vertices.resize(terrain_sample_count)
    normals.resize(terrain_sample_count)

    var row_start := 0
    var vertex_chunk_rows := maxi(terrain_vertex_rows_per_frame, 1)
    while row_start < _height:
        var started := Time.get_ticks_msec()
        var row_end := mini(row_start + vertex_chunk_rows, _height)
        for row: int in range(row_start, row_end):
            for col: int in range(_width):
                var i := _index(row, col)
                vertices[i] = _grid_game_position(row, col)
                normals[i] = _normal(row, col)
        terrain_vertex_chunks += 1
        _record_phase_peak("terrain_vertices_chunk", Time.get_ticks_msec() - started)
        row_start = row_end
        if row_start < _height:
            await get_tree().process_frame
    print("IXELLES_STREAM_PHASE: terrain_vertices chunks=%d peak_ms=%d" % [terrain_vertex_chunks, int(stream_phase_ms.get("terrain_vertices_chunk", 0))])

    var indices := PackedInt32Array()
    indices.resize((_width - 1) * (_height - 1) * 6)
    var index_chunk_rows := maxi(terrain_index_rows_per_frame, 1)
    row_start = 0
    while row_start < _height - 1:
        var started := Time.get_ticks_msec()
        var row_end := mini(row_start + index_chunk_rows, _height - 1)
        for row: int in range(row_start, row_end):
            var cursor := row * (_width - 1) * 6
            for col: int in range(_width - 1):
                var i0 := _index(row, col)
                var i1 := _index(row + 1, col)
                var i2 := _index(row, col + 1)
                var i3 := _index(row + 1, col + 1)
                indices[cursor] = i0
                indices[cursor + 1] = i1
                indices[cursor + 2] = i2
                indices[cursor + 3] = i2
                indices[cursor + 4] = i1
                indices[cursor + 5] = i3
                cursor += 6
        terrain_index_chunks += 1
        _record_phase_peak("terrain_indices_chunk", Time.get_ticks_msec() - started)
        row_start = row_end
        if row_start < _height - 1:
            await get_tree().process_frame
    print("IXELLES_STREAM_PHASE: terrain_indices chunks=%d peak_ms=%d" % [terrain_index_chunks, int(stream_phase_ms.get("terrain_indices_chunk", 0))])

    terrain_triangle_count = indices.size() / 3
    var commit_started := Time.get_ticks_msec()
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh.surface_set_material(0, _terrain_material)
    var instance := MeshInstance3D.new()
    instance.name = "OfficialIxellesDTMMesh"
    instance.mesh = mesh
    add_child(instance)
    _record_phase_peak("terrain_mesh_commit", Time.get_ticks_msec() - commit_started)
    print("IXELLES_STREAM_PHASE: terrain_mesh_commit ms=%d" % int(stream_phase_ms.get("terrain_mesh_commit", 0)))

func get_max_stream_phase_ms() -> int:
    var maximum := 0
    for phase_name: String in stream_phase_ms.keys():
        maximum = maxi(maximum, int(stream_phase_ms[phase_name]))
    return maximum
