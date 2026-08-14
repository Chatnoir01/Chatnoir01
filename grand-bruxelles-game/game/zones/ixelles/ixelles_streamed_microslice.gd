extends "res://game/zones/ixelles/ixelles_microslice.gd"
class_name IxellesStreamedMicroSlice

## Streaming-specific Ixelles adapter.
## Keeps the proven source-backed builder unchanged, but spreads its major build
## phases over separate frames so a prefetched cell does not monopolize one frame.

var stream_phase_ms: Dictionary = {}
var stream_total_ms := 0
var stream_build_started := false

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
    await get_tree().process_frame

    phase_started = Time.get_ticks_msec()
    _build_terrain()
    stream_phase_ms["terrain_mesh"] = Time.get_ticks_msec() - phase_started
    await get_tree().process_frame

    if build_collision:
        phase_started = Time.get_ticks_msec()
        _build_collision()
        stream_phase_ms["terrain_collision"] = Time.get_ticks_msec() - phase_started
        await get_tree().process_frame

    phase_started = Time.get_ticks_msec()
    _build_street_surfaces()
    stream_phase_ms["street_surfaces"] = Time.get_ticks_msec() - phase_started
    await get_tree().process_frame

    phase_started = Time.get_ticks_msec()
    _build_strong_height_candidate_buildings()
    stream_phase_ms["buildings"] = Time.get_ticks_msec() - phase_started

    runtime_loaded = terrain_triangle_count == 125000 and street_surface_count == 309 and street_segment_count == 277 and building_count == eligible_height_count and building_count == 260 and skipped_unapproved_height_buildings == 460
    stream_total_ms = Time.get_ticks_msec() - total_started
    if runtime_loaded:
        print("IXELLES_STREAMED_MICROSLICE_READY: cell=%s triangles=%d streets=%d buildings=%d total_ms=%d max_phase_ms=%d" % [cell_id, terrain_triangle_count, street_surface_count, building_count, stream_total_ms, get_max_stream_phase_ms()])

func get_max_stream_phase_ms() -> int:
    var maximum := 0
    for phase_name: String in stream_phase_ms.keys():
        maximum = maxi(maximum, int(stream_phase_ms[phase_name]))
    return maximum
