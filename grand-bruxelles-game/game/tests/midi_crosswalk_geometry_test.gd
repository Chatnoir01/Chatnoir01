extends SceneTree

const MIDI := Vector3(-668.5, 0.0, 627.84)
const FONSNY_AXIS := Vector3(-0.627, 0.0, 0.779)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)
const EXPECTED_BANDS := 13
const BAND_WIDTH_M := 0.50
const BAND_GAP_M := 0.50
const CROSSING_LENGTH_M := 4.0
const ROAD_SURFACE_Y_M := 0.075


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene did not load")
        return
    var scene := packed.instantiate()
    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    root.add_child(scene)
    await process_frame

    var midi := scene.get_node_or_null("MidiHeroZone") as Node3D
    if midi == null:
        _fail("production MidiHeroZone is missing")
        return
    var bands: Array[MeshInstance3D] = []
    for child: Node in midi.get_children():
        if child is MeshInstance3D and child.name.begins_with("Crosswalk_"):
            bands.append(child as MeshInstance3D)
    if bands.size() != EXPECTED_BANDS:
        _fail("expected %d longitudinal bands, got %d" % [EXPECTED_BANDS, bands.size()])
        return

    var crossing_center := MIDI + FONSNY_AXIS * -18.0
    var fonsny_axis := FONSNY_AXIS.normalized()
    var road_side := ROAD_SIDE.normalized()
    var lateral_offsets: Array[float] = []
    for band: MeshInstance3D in bands:
        var box := band.mesh as BoxMesh
        if box == null:
            _fail("%s must use a flat BoxMesh marking" % band.name)
            return
        if not is_equal_approx(box.size.x, BAND_WIDTH_M):
            _fail("%s width is %.3f m, expected %.2f m" % [band.name, box.size.x, BAND_WIDTH_M])
            return
        if not is_equal_approx(box.size.z, CROSSING_LENGTH_M):
            _fail("%s length is %.3f m, expected %.1f m" % [band.name, box.size.z, CROSSING_LENGTH_M])
            return
        if box.size.y > 0.01:
            _fail("%s is a raised slab (%.3f m), not road paint" % [band.name, box.size.y])
            return
        if band.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
            _fail("%s road paint must not cast a raised-object shadow" % band.name)
            return
        var bottom_y := band.global_position.y - box.size.y * 0.5
        if bottom_y < ROAD_SURFACE_Y_M or bottom_y > ROAD_SURFACE_Y_M + 0.006:
            _fail("%s paint bottom %.4f m does not hug road y=%.3f m" % [band.name, bottom_y, ROAD_SURFACE_Y_M])
            return
        if absf(band.global_basis.x.normalized().dot(road_side)) < 0.999:
            _fail("%s narrow axis is not lateral across Avenue Fonsny" % band.name)
            return
        if absf(band.global_basis.z.normalized().dot(fonsny_axis)) < 0.999:
            _fail("%s long axis is not parallel to Avenue Fonsny" % band.name)
            return
        var relative := band.global_position - crossing_center
        if absf(relative.dot(fonsny_axis)) > 0.01:
            _fail("%s shifted longitudinally out of the crossing" % band.name)
            return
        lateral_offsets.append(relative.dot(road_side))

    lateral_offsets.sort()
    var expected_pitch := BAND_WIDTH_M + BAND_GAP_M
    for index: int in range(1, lateral_offsets.size()):
        var pitch := lateral_offsets[index] - lateral_offsets[index - 1]
        if absf(pitch - expected_pitch) > 0.001:
            _fail("band pitch %.3f m does not preserve 0.50 m paint / 0.50 m gap" % pitch)
            return
    var marked_width := lateral_offsets[-1] - lateral_offsets[0] + BAND_WIDTH_M
    if absf(marked_width - 12.5) > 0.001:
        _fail("crosswalk spans %.3f m instead of the 12.5 m carriageway" % marked_width)
        return

    print(
        "MIDI_CROSSWALK_GEOMETRY_OK: %d bands, %.2f m paint, %.2f m gap, %.1f m length, %.1f m carriageway" %
        [bands.size(), BAND_WIDTH_M, BAND_GAP_M, CROSSING_LENGTH_M, marked_width]
    )
    scene.queue_free()
    quit(0)


func _fail(message: String) -> void:
    push_error("MIDI_CROSSWALK_GEOMETRY_FAIL: %s" % message)
    quit(1)
