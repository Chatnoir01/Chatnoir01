extends Node3D
class_name BourseMetroIdentityRuntime

## Source-bounded bilingual public-transport identity for the seven published
## Bourse/Beurs underground-station entrance points. Published points are treated
## as anchors, not centimetre surveys; blade geometry/yaw/materials are authored.

const station_fr := "Bourse"
const station_nl := "Beurs"
const entrance_count := 7
const published_points_only := true
const claims_surveyed_sign_geometry := false
const claims_timetable_or_service := false

const source_stop_ids := [
    "0600565", "0600765", "0600365", "0600965", "0601165", "0600165", "0601265"
]

# Project-space anchors derived from the official published WGS84 points using
# the existing vertical-slice local tangent convention around [4.348, 50.8419].
const ENTRANCE_ANCHORS := [
    Vector3(48.363, 0.16, -593.558),
    Vector3(29.453, 0.16, -605.581),
    Vector3(79.292, 0.16, -640.647),
    Vector3(70.294, 0.16, -667.697),
    Vector3(81.331, 0.16, -706.659),
    Vector3(151.133, 0.16, -752.746),
    Vector3(137.215, 0.16, -767.774),
]

const STATION_CENTRE := Vector3(99.011, 0.16, -676.666)

var identity_count := 0
var visual_built := false

func _ready() -> void:
    build()

func build() -> bool:
    if visual_built:
        return true
    identity_count = 0
    for index in range(ENTRANCE_ANCHORS.size()):
        _build_identity(index, ENTRANCE_ANCHORS[index])
    visual_built = identity_count == entrance_count
    return visual_built

func _build_identity(index: int, anchor: Vector3) -> void:
    var root_node := Node3D.new()
    root_node.name = "BourseBeursEntranceIdentity_%s" % source_stop_ids[index]
    root_node.position = anchor
    root_node.set_meta("source_stop_id", source_stop_ids[index])
    root_node.set_meta("source_anchor_published", true)
    root_node.set_meta("authored_yaw", true)
    add_child(root_node)

    # Authored yaw points the readable blade face roughly toward the station
    # centre. No surveyed entrance/sign orientation is claimed.
    var target := STATION_CENTRE
    target.y = anchor.y
    if target.distance_to(anchor) > 0.1:
        root_node.look_at(target, Vector3.UP)

    var frame_mat := StandardMaterial3D.new()
    frame_mat.albedo_color = Color(0.12, 0.14, 0.17, 1.0)
    frame_mat.roughness = 0.66
    frame_mat.metallic = 0.32

    var panel_mat := StandardMaterial3D.new()
    panel_mat.albedo_color = Color(0.055, 0.17, 0.35, 1.0)
    panel_mat.roughness = 0.62
    panel_mat.metallic = 0.0

    # A compact authored identity blade. It is intentionally smaller than the
    # rejected #320 single-stop panel; broad value comes from seven real entrance
    # anchors, not from enlarging one marker.
    _box(root_node, "IdentityPost", Vector3(0.075, 2.15, 0.075), Vector3(0.0, 1.075, 0.0), frame_mat)
    _box(root_node, "IdentityBlade", Vector3(0.66, 1.18, 0.065), Vector3(0.0, 1.72, -0.012), panel_mat)

    var label := Label3D.new()
    label.name = "BourseBeursLabel"
    label.text = "BOURSE\nBEURS"
    label.position = Vector3(0.0, 1.72, -0.050)
    label.rotation_degrees.y = 180.0
    label.font_size = 72
    label.pixel_size = 0.0043
    label.modulate = Color(0.97, 0.97, 0.95, 1.0)
    label.outline_size = 4
    label.outline_modulate = Color(0.015, 0.025, 0.05, 0.94)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.no_depth_test = false
    root_node.add_child(label)

    identity_count += 1

func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = pos
    instance.material_override = material
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(instance)
    return instance
