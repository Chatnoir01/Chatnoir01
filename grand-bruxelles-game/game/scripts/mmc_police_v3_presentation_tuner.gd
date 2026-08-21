extends Node

const TARGET_PROFILES: Array[String] = [
    "brussels_capitale_sedan",
    "brussels_rapid_response_coupe",
]

var _attempts := 0
var _tuned_profiles: Dictionary = {}

func _ready() -> void:
    set_process(true)

func _process(_delta: float) -> void:
    _attempts += 1
    _tune_available_vehicles()
    if _tuned_profiles.size() >= TARGET_PROFILES.size() or _attempts > 240:
        set_process(false)
        if _tuned_profiles.size() >= TARGET_PROFILES.size():
            print("MMC_POLICE_V3_PRESENTATION_READY: profiles=2 lightbars=true decals=true occupants=true cabin=true")

func _tune_available_vehicles() -> void:
    for value: Node in get_tree().get_nodes_in_group("belgian_police_vehicle"):
        var vehicle := value as Node3D
        if vehicle == null:
            continue
        var holder := vehicle.get_node_or_null(NodePath("BelgianPoliceFleetVisual")) as Node3D
        if holder == null:
            continue
        var profile_id := str(holder.get_meta("police_profile_id", ""))
        if not TARGET_PROFILES.has(profile_id):
            continue
        if tune_holder(holder, profile_id):
            _tuned_profiles[profile_id] = true

func tune_holder(holder: Node3D, profile_id: String) -> bool:
    if holder == null or not TARGET_PROFILES.has(profile_id):
        return false
    var closure := holder.get_node_or_null(NodePath("PoliceBodyClosureV3")) as Node3D
    var cabin := holder.get_node_or_null(NodePath("PoliceCabinV2")) as Node3D
    var occupants := holder.get_node_or_null(NodePath("PoliceOccupantsV2")) as Node3D
    var systems := holder.get_node_or_null(NodePath("EmergencySystems")) as Node3D
    var decals := holder.get_node_or_null(NodePath("RuntimeDecals")) as Node3D
    if closure == null or cabin == null or occupants == null or systems == null or decals == null:
        return false

    var is_coupe := profile_id == "brussels_rapid_response_coupe"
    systems.position.y = -0.18
    _tune_decals(decals)
    _tune_closure(closure, is_coupe)
    _tune_cabin(cabin)
    _tune_occupants(occupants)

    holder.set_meta("v3_presentation_tuned", true)
    holder.set_meta("v3_lightbar_roof_gap_m", 0.02)
    holder.set_meta("v3_rear_chevrons_compacted", true)
    holder.set_meta("v3_right_label_orientation_fixed", true)
    holder.set_meta("v3_occupants_lowered", true)
    return true

func _tune_decals(decals: Node3D) -> void:
    var rear := decals.get_node_or_null(NodePath("RearChevrons")) as Sprite3D
    if rear != null:
        rear.pixel_size = 0.075
        rear.scale = Vector3(1.0, 0.36, 1.0)
        rear.position.y = 0.68

    for side_name: String in ["BilingualLeft", "BilingualRight"]:
        var label := decals.get_node_or_null(NodePath(side_name)) as Sprite3D
        if label != null:
            label.pixel_size = 0.00155
            label.scale = Vector3(1.0, 0.68, 1.0)

    var right_label := decals.get_node_or_null(NodePath("BilingualRight")) as Sprite3D
    if right_label != null:
        right_label.flip_h = true

    for stripe_name: String in ["StripeLeft", "StripeRight"]:
        var stripe := decals.get_node_or_null(NodePath(stripe_name)) as Sprite3D
        if stripe != null:
            stripe.pixel_size = 0.0115
            stripe.scale = Vector3(1.0, 0.52, 1.0)

func _tune_closure(closure: Node3D, is_coupe: bool) -> void:
    var roof := closure.get_node_or_null(NodePath("RoofPanel")) as MeshInstance3D
    if roof != null and roof.mesh is BoxMesh:
        var roof_mesh := roof.mesh as BoxMesh
        roof_mesh.size = Vector3(1.26 if is_coupe else 1.28, 0.06, 1.04 if is_coupe else 1.22)
        roof.position.y = 1.28 if is_coupe else 1.37

    var windshield := closure.get_node_or_null(NodePath("Windshield")) as MeshInstance3D
    if windshield != null:
        windshield.position.y = 1.10 if is_coupe else 1.13

    var rear_window := closure.get_node_or_null(NodePath("RearWindow")) as MeshInstance3D
    if rear_window != null:
        rear_window.position.y = 1.08 if is_coupe else 1.12

func _tune_cabin(cabin: Node3D) -> void:
    var dashboard := cabin.get_node_or_null(NodePath("Dashboard")) as MeshInstance3D
    if dashboard != null and dashboard.mesh is BoxMesh:
        var dash_mesh := dashboard.mesh as BoxMesh
        dash_mesh.size = Vector3(1.36, 0.13, 0.29)
        dashboard.position = Vector3(0.0, 0.82, -1.05)

    var console := cabin.get_node_or_null(NodePath("CenterConsole")) as MeshInstance3D
    if console != null and console.mesh is BoxMesh:
        var console_mesh := console.mesh as BoxMesh
        console_mesh.size = Vector3(0.16, 0.18, 0.54)
        console.position.y = 0.56

    var wheel := cabin.get_node_or_null(NodePath("SteeringWheel")) as MeshInstance3D
    if wheel != null:
        wheel.position = Vector3(-0.43, 0.88, -0.78)

func _tune_occupants(occupants: Node3D) -> void:
    for child: Node in occupants.get_children():
        var officer := child as Node3D
        if officer == null:
            continue
        officer.position.y = -0.17
        officer.set_meta("v3_seated_clearance_tuned", true)
