extends Node

# Source-bounded Fonsny arrival planimetry controller. It preserves the readable
# #323 station architecture/materials and only toggles broad arrival-context
# geometry already present in production: hide the authored 18 x 174 m slab to
# reveal exact UrbIS StreetSurfaces, and replace the generic straight zebra with
# marking cells derived from the official Ortho2023 QA crop.

const CROSSWALK_SOURCE := "res://data/qa/midi_fonsny_crosswalk_ortho2023.json"
const OFFICIAL_CROSSWALK_NAME := "OfficialFonsnyCrosswalkOrtho2023"
const HERO_PATH := NodePath("MidiHeroZone")

var _arrival_planimetry_enabled := true
var _hero: Node3D
var _source_crosswalk: MeshInstance3D
var visual_built := false

func _ready() -> void:
    call_deferred("_mount_runtime")

func _mount_runtime() -> void:
    var scene := get_tree().current_scene
    if scene == null:
        await get_tree().process_frame
        scene = get_tree().current_scene
    if scene == null:
        push_error("Midi arrival planimetry: current scene missing")
        return
    _hero = scene.get_node_or_null(HERO_PATH) as Node3D
    if _hero == null:
        push_error("Midi arrival planimetry: MidiHeroZone missing")
        return
    _source_crosswalk = _build_source_crosswalk()
    if _source_crosswalk == null:
        return
    _hero.add_child(_source_crosswalk)
    visual_built = true
    set_arrival_planimetry_enabled(true)
    set_meta("midi_arrival_planimetry_source_bounded", true)
    set_meta("midi_arrival_planimetry_source", "Paradigm UrbIS StreetSurfaces + Ortho2023")

func _build_source_crosswalk() -> MeshInstance3D:
    if not FileAccess.file_exists(CROSSWALK_SOURCE):
        push_error("Midi arrival planimetry: crosswalk source missing")
        return null
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CROSSWALK_SOURCE))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Midi arrival planimetry: invalid crosswalk source")
        return null
    var data := parsed as Dictionary
    var render: Dictionary = data.get("render", {})
    var rects: Array = render.get("rects_world_xz_size_m", [])
    if rects.size() != int(render.get("rect_count", -1)) or rects.size() < 100:
        push_error("Midi arrival planimetry: incomplete source crosswalk")
        return null

    var white := StandardMaterial3D.new()
    white.albedo_color = Color(0.91, 0.91, 0.87, 1.0)
    white.roughness = 0.92
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(white)
    const Y := 0.185
    for raw: Variant in rects:
        if typeof(raw) != TYPE_ARRAY or raw.size() != 4:
            push_error("Midi arrival planimetry: malformed source marking cell")
            return null
        var values := raw as Array
        var cx := float(values[0])
        var cz := float(values[1])
        var sx := float(values[2])
        var sz := float(values[3])
        var x0 := cx - sx * 0.5
        var x1 := cx + sx * 0.5
        var z0 := cz - sz * 0.5
        var z1 := cz + sz * 0.5
        for vertex: Vector3 in [
            Vector3(x0, Y, z0), Vector3(x1, Y, z0), Vector3(x1, Y, z1),
            Vector3(x0, Y, z0), Vector3(x1, Y, z1), Vector3(x0, Y, z1)
        ]:
            tool.set_normal(Vector3.UP)
            tool.add_vertex(vertex)

    var mesh := tool.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        push_error("Midi arrival planimetry: source crosswalk mesh empty")
        return null
    var instance := MeshInstance3D.new()
    instance.name = OFFICIAL_CROSSWALK_NAME
    instance.mesh = mesh
    instance.visible = false
    instance.set_meta("source_rect_count", rects.size())
    instance.set_meta("source_paint_area_m2", float(render.get("paint_area_m2", 0.0)))
    instance.set_meta("source_pixel_size_m", 0.125)
    return instance

func set_arrival_planimetry_enabled(enabled: bool) -> void:
    _arrival_planimetry_enabled = enabled
    if _hero == null:
        return
    var forecourt := _hero.get_node_or_null("FonsnyStationForecourt") as GeometryInstance3D
    if forecourt != null:
        forecourt.visible = not enabled
    for stripe_index: int in range(10):
        var stripe := _hero.get_node_or_null("Crosswalk_%02d" % stripe_index) as GeometryInstance3D
        if stripe != null:
            stripe.visible = not enabled
    if _source_crosswalk != null:
        _source_crosswalk.visible = enabled
    set_meta("midi_arrival_planimetry_enabled", enabled)

func arrival_planimetry_enabled() -> bool:
    return _arrival_planimetry_enabled
