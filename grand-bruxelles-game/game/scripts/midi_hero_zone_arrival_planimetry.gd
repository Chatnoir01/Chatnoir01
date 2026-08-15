extends "res://game/scripts/midi_hero_zone_materials.gd"

# Source-bounded Fonsny arrival planimetry.
# Preserve the readable #323 station architecture/materials. The only runtime
# changes are: (1) hide the hand-built 18 x 174 m forecourt slab so the already
# mounted exact UrbIS StreetSurfaces remain visible, and (2) replace the generic
# straight zebra stripes with marking cells measured from official Ortho2023.

const CROSSWALK_SOURCE := "res://data/qa/midi_fonsny_crosswalk_ortho2023.json"
const OFFICIAL_CROSSWALK_NAME := "OfficialFonsnyCrosswalkOrtho2023"

var _arrival_planimetry_enabled := true
var _source_crosswalk: MeshInstance3D

func _ready() -> void:
    super._ready()
    set_arrival_planimetry_enabled(true)
    set_meta("midi_arrival_planimetry_source_bounded", true)
    set_meta("midi_arrival_planimetry_source", "Paradigm UrbIS StreetSurfaces + Ortho2023")

func _build_fonsny_forecourt() -> void:
    # Keep the baseline node available for same-world deterministic A/B. Runtime
    # hides it after construction; no replacement slab is authored here.
    super._build_fonsny_forecourt()

func _build_fonsny_crossing() -> void:
    # Keep current-main crossing for same-world A/B, then add the source-derived
    # marking mesh. Runtime toggles between them without moving camera/world.
    super._build_fonsny_crossing()
    _source_crosswalk = _build_source_crosswalk()
    if _source_crosswalk != null:
        _source_crosswalk.visible = false

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

    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_white)
    const Y := 0.185
    for raw: Variant in rects:
        if typeof(raw) != TYPE_ARRAY or raw.size() != 4:
            push_error("Midi arrival planimetry: malformed source marking cell")
            return null
        var cx := float(raw[0])
        var cz := float(raw[1])
        var sx := float(raw[2])
        var sz := float(raw[3])
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
    instance.set_meta("source_rect_count", rects.size())
    instance.set_meta("source_paint_area_m2", float(render.get("paint_area_m2", 0.0)))
    instance.set_meta("source_pixel_size_m", 0.125)
    add_child(instance)
    return instance

func set_arrival_planimetry_enabled(enabled: bool) -> void:
    _arrival_planimetry_enabled = enabled
    var forecourt := get_node_or_null("FonsnyStationForecourt") as GeometryInstance3D
    if forecourt != null:
        forecourt.visible = not enabled
    for stripe_index: int in range(10):
        var stripe := get_node_or_null("Crosswalk_%02d" % stripe_index) as GeometryInstance3D
        if stripe != null:
            stripe.visible = not enabled
    var official := get_node_or_null(OFFICIAL_CROSSWALK_NAME) as GeometryInstance3D
    if official != null:
        official.visible = enabled
    set_meta("midi_arrival_planimetry_enabled", enabled)

func arrival_planimetry_enabled() -> bool:
    return _arrival_planimetry_enabled
