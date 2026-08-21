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
    if _tuned_profiles.size() >= TARGET_PROFILES.size() or _attempts > 300:
        set_process(false)
        if _tuned_profiles.size() >= TARGET_PROFILES.size():
            print("MMC_POLICE_V4_PRESENTATION_READY: profiles=2 lower_lightbars=true compact_livery=true inset_closure=true occupants=true cabin=true")

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
    _tune_emergency_systems(systems, is_coupe)
    _tune_livery_blocks(holder, is_coupe)
    _tune_decals(decals)
    _tune_closure(closure, is_coupe)
    _tune_cabin(cabin, is_coupe)
    _tune_occupants(occupants)

    holder.set_meta("v3_presentation_tuned", true)
    holder.set_meta("v4_presentation_tuned", true)
    holder.set_meta("v4_lightbar_lowered", true)
    holder.set_meta("v4_livery_compacted", true)
    holder.set_meta("v4_closure_inset_under_source_lod", true)
    holder.set_meta("v4_right_label_orientation_fixed", true)
    holder.set_meta("v4_occupants_seated_scale", 0.88)
    return true

func _tune_emergency_systems(systems: Node3D, is_coupe: bool) -> void:
    systems.position.y = -0.30 if is_coupe else -0.32
    systems.scale = Vector3(0.82, 0.58, 0.80)

func _tune_livery_blocks(holder: Node3D, is_coupe: bool) -> void:
    for side_prefix: String in ["Livery_L_", "Livery_R_"]:
        for index: int in range(4):
            var panel := holder.get_node_or_null(NodePath("%s%d" % [side_prefix, index])) as MeshInstance3D
            if panel == null or not panel.mesh is BoxMesh:
                continue
            var mesh := panel.mesh as BoxMesh
            var old_size := mesh.size
            mesh.size = Vector3(0.018, 0.18 if not is_coupe else 0.16, old_size.z * 0.74)
            panel.position.y = 0.64 if not is_coupe else 0.61
            panel.position.z *= 0.93
    for node_name: String in ["FrontBlueLeft", "FrontBlueRight"]:
        var flasher := holder.get_node_or_null(NodePath(node_name)) as MeshInstance3D
        if flasher == null or not flasher.mesh is BoxMesh:
            continue
        var mesh := flasher.mesh as BoxMesh
        mesh.size = Vector3(0.17, 0.052, 0.024)
        flasher.position.y = 0.62 if not is_coupe else 0.59

func _tune_decals(decals: Node3D) -> void:
    var rear := decals.get_node_or_null(NodePath("RearChevrons")) as Sprite3D
    if rear != null:
        rear.pixel_size = 0.052
        rear.scale = Vector3(0.88, 0.28, 1.0)
        rear.position.y = 0.61

    for side_name: String in ["BilingualLeft", "BilingualRight"]:
        var label := decals.get_node_or_null(NodePath(side_name)) as Sprite3D
        if label != null:
            label.pixel_size = 0.00108
            label.scale = Vector3(0.90, 0.56, 1.0)
            label.position.y = 0.65

    var right_label := decals.get_node_or_null(NodePath("BilingualRight")) as Sprite3D
    if right_label != null:
        right_label.flip_h = true

    for stripe_name: String in ["StripeLeft", "StripeRight"]:
        var stripe := decals.get_node_or_null(NodePath(stripe_name)) as Sprite3D
        if stripe != null:
            stripe.pixel_size = 0.0085
            stripe.scale = Vector3(0.92, 0.36, 1.0)
            stripe.position.y = 0.64

func _set_box(node: Node3D, size: Vector3, position: Vector3) -> void:
    var mesh_instance := node as MeshInstance3D
    if mesh_instance == null or not mesh_instance.mesh is BoxMesh:
        return
    (mesh_instance.mesh as BoxMesh).size = size
    mesh_instance.position = position

func _tune_closure(closure: Node3D, is_coupe: bool) -> void:
    _set_box(
        closure.get_node_or_null(NodePath("ClosedLowerBody")) as Node3D,
        Vector3(1.60 if is_coupe else 1.62, 0.34, 3.92 if is_coupe else 4.04),
        Vector3(0.0, 0.50, 0.02)
    )
    _set_box(
        closure.get_node_or_null(NodePath("HoodClosure")) as Node3D,
        Vector3(1.49 if is_coupe else 1.53, 0.075, 1.10 if is_coupe else 1.15),
        Vector3(0.0, 0.78, -1.43)
    )
    _set_box(
        closure.get_node_or_null(NodePath("TrunkClosure")) as Node3D,
        Vector3(1.48 if is_coupe else 1.52, 0.075, 0.68 if is_coupe else 0.86),
        Vector3(0.0, 0.77, 1.57)
    )
    _set_box(
        closure.get_node_or_null(NodePath("RoofPanel")) as Node3D,
        Vector3(1.13 if is_coupe else 1.18, 0.035, 0.88 if is_coupe else 1.02),
        Vector3(0.0, 1.23 if is_coupe else 1.31, 0.08)
    )

    var windshield := closure.get_node_or_null(NodePath("Windshield")) as MeshInstance3D
    if windshield != null and windshield.mesh is BoxMesh:
        (windshield.mesh as BoxMesh).size = Vector3(1.22 if is_coupe else 1.26, 0.38 if is_coupe else 0.42, 0.022)
        windshield.position = Vector3(0.0, 1.06 if is_coupe else 1.10, -0.70)
        windshield.rotation_degrees.x = -24.0 if is_coupe else -21.0

    var rear_window := closure.get_node_or_null(NodePath("RearWindow")) as MeshInstance3D
    if rear_window != null and rear_window.mesh is BoxMesh:
        (rear_window.mesh as BoxMesh).size = Vector3(1.20 if is_coupe else 1.24, 0.34 if is_coupe else 0.39, 0.022)
        rear_window.position = Vector3(0.0, 1.04 if is_coupe else 1.08, 0.86)
        rear_window.rotation_degrees.x = 25.0 if is_coupe else 21.0

    for side_name: String in ["LeftSideGlass", "RightSideGlass"]:
        var side_glass := closure.get_node_or_null(NodePath(side_name)) as MeshInstance3D
        if side_glass == null or not side_glass.mesh is BoxMesh:
            continue
        (side_glass.mesh as BoxMesh).size = Vector3(0.018, 0.33 if is_coupe else 0.37, 0.96 if is_coupe else 1.13)
        side_glass.position.y = 1.04 if is_coupe else 1.08

func _tune_cabin(cabin: Node3D, is_coupe: bool) -> void:
    var dashboard := cabin.get_node_or_null(NodePath("Dashboard")) as MeshInstance3D
    if dashboard != null and dashboard.mesh is BoxMesh:
        var dash_mesh := dashboard.mesh as BoxMesh
        dash_mesh.size = Vector3(1.18, 0.10, 0.24)
        dashboard.position = Vector3(0.0, 0.80 if not is_coupe else 0.77, -1.00)

    var console := cabin.get_node_or_null(NodePath("CenterConsole")) as MeshInstance3D
    if console != null and console.mesh is BoxMesh:
        var console_mesh := console.mesh as BoxMesh
        console_mesh.size = Vector3(0.14, 0.14, 0.46)
        console.position = Vector3(0.0, 0.54, -0.43)

    for seat_name: String in ["DriverSeatBottom", "PassengerSeatBottom"]:
        var seat := cabin.get_node_or_null(NodePath(seat_name)) as MeshInstance3D
        if seat != null and seat.mesh is BoxMesh:
            (seat.mesh as BoxMesh).size = Vector3(0.42, 0.13, 0.44)
            seat.position.y = 0.52
    for seat_name: String in ["DriverSeatBack", "PassengerSeatBack"]:
        var seat_back := cabin.get_node_or_null(NodePath(seat_name)) as MeshInstance3D
        if seat_back != null and seat_back.mesh is BoxMesh:
            (seat_back.mesh as BoxMesh).size = Vector3(0.42, 0.52, 0.12)
            seat_back.position.y = 0.82

    var wheel := cabin.get_node_or_null(NodePath("SteeringWheel")) as MeshInstance3D
    if wheel != null:
        wheel.position = Vector3(-0.43, 0.85 if not is_coupe else 0.82, -0.76)
        wheel.scale = Vector3.ONE * 0.82

func _tune_occupants(occupants: Node3D) -> void:
    for child: Node in occupants.get_children():
        var officer := child as Node3D
        if officer == null:
            continue
        officer.position.y = -0.24
        officer.scale = Vector3.ONE * 0.88
        var head := officer.get_node_or_null(NodePath("Head")) as MeshInstance3D
        if head != null:
            head.scale = Vector3.ONE * 0.92
        var cap := officer.get_node_or_null(NodePath("Cap")) as MeshInstance3D
        if cap != null:
            cap.scale = Vector3(0.88, 0.72, 0.88)
        officer.set_meta("v3_seated_clearance_tuned", true)
        officer.set_meta("v4_seated_proportion_tuned", true)
