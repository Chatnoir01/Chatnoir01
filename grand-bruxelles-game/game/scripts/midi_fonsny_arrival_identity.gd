extends "res://game/scripts/midi_hero_zone_materials.gd"

# Source-backed street-level arrival articulation for the Avenue Fonsny access porch.
# The heritage inventory documents three long bays with concrete cross framing,
# glass blocks and polygonal porch columns. This wrapper preserves the existing
# authored entrance envelope and #323 material family. All frame thicknesses and
# exact offsets below are presentation values, not surveyed dimensions.

const FRAME_FACE_X := -14.49
const FRAME_DEPTH := 0.06
const VERTICAL_FRAME_WIDTH := 0.18
const HORIZONTAL_FRAME_HEIGHT := 0.16
const ENTRANCE_SPAN_Z := 18.8
const ENTRANCE_GLAZING_HEIGHT := 3.65

func _build_station_entrance() -> void:
    super._build_station_entrance()
    var entrance := get_node_or_null("MidiMainEntranceFonsny") as Node3D
    if entrance == null:
        return

    var arrival_frame := Node3D.new()
    arrival_frame.name = "FonsnyThreeBayArrivalFrame"
    entrance.add_child(arrival_frame)

    # Three long bays: two dividers across the existing 18.8 m authored glazing
    # plane. No new entrance width or height is introduced.
    var bay_step := ENTRANCE_SPAN_Z / 3.0
    for divider_index: int in [1, 2]:
        var z := -ENTRANCE_SPAN_Z * 0.5 + bay_step * float(divider_index)
        var divider := _add_box(
            arrival_frame,
            "BayDivider_%d" % divider_index,
            Vector3(FRAME_DEPTH, ENTRANCE_GLAZING_HEIGHT, VERTICAL_FRAME_WIDTH),
            Vector3(FRAME_FACE_X, 2.15, z),
            _concrete
        )
        divider.set_meta("source_fact", "three_long_bays_with_concrete_cross_framing")
        divider.set_meta("authored_dimensions", true)

    # One quiet cross rail gives each documented long bay a concrete cross-frame
    # reading without the repeated projecting caps/shadows rejected in #326.
    var rail := _add_box(
        arrival_frame,
        "BayCrossRail",
        Vector3(FRAME_DEPTH, HORIZONTAL_FRAME_HEIGHT, ENTRANCE_SPAN_Z),
        Vector3(FRAME_FACE_X, 2.15, 0.0),
        _concrete
    )
    rail.set_meta("source_fact", "concrete_cross_framing")
    rail.set_meta("authored_dimensions", true)

    # Preserve the existing column geometry; only align its material identity
    # with the documented porch composition. No radius/height/position changes.
    for child in entrance.get_children():
        if child is MeshInstance3D and child.name == "EntranceColumn":
            var column := child as MeshInstance3D
            if column.mesh != null:
                column.mesh.material = _concrete
                column.set_meta("source_fact", "polygonal_columns_support_access_porch")
                column.set_meta("geometry_unchanged", true)
