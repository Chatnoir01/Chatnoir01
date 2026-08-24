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
            print("MMC_POLICE_V4_PRESENTATION_READY: profiles=2 lower_lightbars=true compact_livery=true cabin_frame=true wheel_stance=true low_lod_shards_suppressed=true")

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
    _tune_source_lod(holder)
    _tune_closure(closure, is_coupe)
    _ensure_cabin_frame(closure, is_coupe)
    _tune_wheels(holder, is_coupe)
    _tune_cabin(cabin, is_coupe)
    _tune_occupants(occupants)

    holder.set_meta("v3_presentation_tuned", true)
    holder.set_meta("v4_presentation_tuned", true)
    holder.set_meta("v4_lightbar_lowered", true)
    holder.set_meta("v4_livery_compacted", true)
    holder.set_meta("v4_closure_inset_under_source_lod", true)
    holder.set_meta("v4_cabin_frame_closed", true)
    holder.set_meta("v4_wheel_stance_corrected", true)
    holder.set_meta("v4_low_lod_shards_suppressed", true)
    holder.set_meta("v4_right_label_orientation_fixed", true)
    holder.set_meta("v4_occupants_seated_scale", 0.88)
    return true

func _paint_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.91, 0.92, 0.93, 1.0)
    mat.roughness = 0.28
    mat.metallic = 0.16
    return mat

func _trim_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.025, 0.03, 0.035, 1.0)
    mat.roughness = 0.72
    return mat

func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = node_name
    var mesh := BoxMesh.new()
    mesh.size = size
    node.mesh = mesh
    node.position = position
    node.rotation_degrees = rotation
    node.material_override = material
    parent.add_child(node)
    return node

func _tune_emergency_systems(systems: Node3D, is_coupe: bool) -> void:
    systems.position.y = -0.34 if is_coupe else -0.37
    systems.scale = Vector3(0.72, 0.50, 0.72)

func _tune_livery_blocks(holder: Node3D, is_coupe: bool) -> void:
    for side_prefix: String in ["Livery_L_", "Livery_R_"]:
        for index: int in range(4):
            var panel := holder.get_node_or_null(NodePath("%s%d" % [side_prefix, index])) as MeshInstance3D
            if panel == null or not panel.mesh is BoxMesh:
                continue
            var mesh := panel.mesh as BoxMesh
            var old_size := mesh.size
            mesh.size = Vector3(0.015, 0.15 if not is_coupe else 0.14, old_size.z * 0.68)
            panel.position.y = 0.61 if not is_coupe else 0.58
            panel.position.z *= 0.92
    for node_name: String in ["FrontBlueLeft", "FrontBlueRight"]:
        var flasher := holder.get_node_or_null(NodePath(node_name)) as MeshInstance3D
        if flasher == null or not flasher.mesh is BoxMesh:
            continue
        var mesh := flasher.mesh as BoxMesh
        mesh.size = Vector3(0.14, 0.045, 0.020)
        flasher.position.y = 0.60 if not is_coupe else 0.57

func _tune_decals(decals: Node3D) -> void:
    var rear := decals.get_node_or_null(NodePath("RearChevrons")) as Sprite3D
    if rear != null:
        rear.pixel_size = 0.045
        rear.scale = Vector3(0.82, 0.24, 1.0)
        rear.position.y = 0.59
    for side_name: String in ["BilingualLeft", "BilingualRight"]:
        var label := decals.get_node_or_null(NodePath(side_name)) as Sprite3D
        if label != null:
            label.pixel_size = 0.00092
            label.scale = Vector3(0.86, 0.50, 1.0)
            label.position.y = 0.62
    var right_label := decals.get_node_or_null(NodePath("BilingualRight")) as Sprite3D
    if right_label != null:
        right_label.flip_h = true
    for stripe_name: String in ["StripeLeft", "StripeRight"]:
        var stripe := decals.get_node_or_null(NodePath(stripe_name)) as Sprite3D
        if stripe != null:
            stripe.pixel_size = 0.0074
            stripe.scale = Vector3(0.90, 0.32, 1.0)
            stripe.position.y = 0.61

func _tune_source_lod(holder: Node3D) -> void:
    var lod := holder.get_node_or_null(NodePath("AuthoredSourceDerivedLOD")) as Node3D
    if lod == null:
        return
    var triangles := int(lod.get_meta("source_triangles", 0))
    if triangles >= 4000:
        return
    for child: Node in lod.get_children():
        var visual := child as MeshInstance3D
        if visual == null:
            continue
        var key := str(visual.name).to_lower()
        # The aggressively clustered paint/glass surfaces create long isolated
        # triangles around the roof. Keep metal/plastic authored details, but use
        # the project-owned closed shell for paint and glazing until high-LOD ships.
        if "car_paint" in key or "glass_clear" in key:
            visual.visible = false

func _set_box(node: Node3D, size: Vector3, position: Vector3) -> void:
    var mesh_instance := node as MeshInstance3D
    if mesh_instance == null or not mesh_instance.mesh is BoxMesh:
        return
    (mesh_instance.mesh as BoxMesh).size = size
    mesh_instance.position = position

func _tune_closure(closure: Node3D, is_coupe: bool) -> void:
    _set_box(closure.get_node_or_null(NodePath("ClosedLowerBody")) as Node3D, Vector3(1.64 if is_coupe else 1.66, 0.40, 4.00 if is_coupe else 4.12), Vector3(0.0, 0.51, 0.02))
    _set_box(closure.get_node_or_null(NodePath("HoodClosure")) as Node3D, Vector3(1.52 if is_coupe else 1.56, 0.085, 1.15 if is_coupe else 1.20), Vector3(0.0, 0.79, -1.43))
    _set_box(closure.get_node_or_null(NodePath("TrunkClosure")) as Node3D, Vector3(1.50 if is_coupe else 1.54, 0.085, 0.72 if is_coupe else 0.90), Vector3(0.0, 0.78, 1.57))
    _set_box(closure.get_node_or_null(NodePath("RoofPanel")) as Node3D, Vector3(1.20 if is_coupe else 1.24, 0.045, 0.98 if is_coupe else 1.12), Vector3(0.0, 1.20 if is_coupe else 1.28, 0.10))

    var windshield := closure.get_node_or_null(NodePath("Windshield")) as MeshInstance3D
    if windshield != null and windshield.mesh is BoxMesh:
        (windshield.mesh as BoxMesh).size = Vector3(1.25 if is_coupe else 1.29, 0.42 if is_coupe else 0.46, 0.026)
        windshield.position = Vector3(0.0, 1.04 if is_coupe else 1.08, -0.72)
        windshield.rotation_degrees.x = -26.0 if is_coupe else -23.0
    var rear_window := closure.get_node_or_null(NodePath("RearWindow")) as MeshInstance3D
    if rear_window != null and rear_window.mesh is BoxMesh:
        (rear_window.mesh as BoxMesh).size = Vector3(1.22 if is_coupe else 1.26, 0.38 if is_coupe else 0.42, 0.026)
        rear_window.position = Vector3(0.0, 1.02 if is_coupe else 1.06, 0.87)
        rear_window.rotation_degrees.x = 27.0 if is_coupe else 23.0
    for side_name: String in ["LeftSideGlass", "RightSideGlass"]:
        var side_glass := closure.get_node_or_null(NodePath(side_name)) as MeshInstance3D
        if side_glass == null or not side_glass.mesh is BoxMesh:
            continue
        (side_glass.mesh as BoxMesh).size = Vector3(0.020, 0.35 if is_coupe else 0.39, 1.02 if is_coupe else 1.18)
        side_glass.position.y = 1.02 if is_coupe else 1.06

func _ensure_cabin_frame(closure: Node3D, is_coupe: bool) -> void:
    var frame := closure.get_node_or_null(NodePath("V4CabinFrame")) as Node3D
    if frame != null:
        return
    frame = Node3D.new()
    frame.name = "V4CabinFrame"
    frame.set_meta("renderer_only", true)
    closure.add_child(frame)
    var paint := _paint_material()
    var trim := _trim_material()
    var side_x := 0.65 if is_coupe else 0.67
    var roof_y := 1.17 if is_coupe else 1.25
    var front_z := -0.72
    var rear_z := 0.87
    for side: float in [-1.0, 1.0]:
        _add_box(frame, "A_Pillar_%s" % ("L" if side < 0.0 else "R"), Vector3(0.070, 0.62, 0.075), Vector3(side * side_x, 1.00 if is_coupe else 1.04, front_z), paint, Vector3(-24.0 if is_coupe else -21.0, 0.0, 0.0))
        _add_box(frame, "B_Pillar_%s" % ("L" if side < 0.0 else "R"), Vector3(0.065, 0.56, 0.065), Vector3(side * side_x, 1.00 if is_coupe else 1.04, 0.10), trim)
        _add_box(frame, "C_Pillar_%s" % ("L" if side < 0.0 else "R"), Vector3(0.070, 0.58, 0.075), Vector3(side * side_x, 0.99 if is_coupe else 1.03, rear_z), paint, Vector3(25.0 if is_coupe else 21.0, 0.0, 0.0))
        _add_box(frame, "RoofRail_%s" % ("L" if side < 0.0 else "R"), Vector3(0.075, 0.055, 1.55 if is_coupe else 1.72), Vector3(side * side_x, roof_y, 0.08), paint)
        _add_box(frame, "BeltRail_%s" % ("L" if side < 0.0 else "R"), Vector3(0.060, 0.070, 1.78 if is_coupe else 1.94), Vector3(side * 0.76, 0.82, 0.08), trim)
    _add_box(frame, "FrontRoofHeader", Vector3(1.28 if is_coupe else 1.32, 0.060, 0.075), Vector3(0.0, roof_y, -0.69), paint)
    _add_box(frame, "RearRoofHeader", Vector3(1.26 if is_coupe else 1.30, 0.060, 0.075), Vector3(0.0, roof_y - 0.01, 0.84), paint)

func _tune_wheels(holder: Node3D, is_coupe: bool) -> void:
    var target_x := 0.84 if is_coupe else 0.83
    for child: Node in holder.get_children():
        var mesh_instance := child as MeshInstance3D
        if mesh_instance == null:
            continue
        var key := str(mesh_instance.name)
        if not key.begins_with("Wheel_"):
            continue
        var sign_x := -1.0 if "_L_" in key else 1.0
        mesh_instance.position.x = sign_x * target_x
        mesh_instance.scale = Vector3.ONE * (0.88 if is_coupe else 0.86)

func _tune_cabin(cabin: Node3D, is_coupe: bool) -> void:
    var dashboard := cabin.get_node_or_null(NodePath("Dashboard")) as MeshInstance3D
    if dashboard != null and dashboard.mesh is BoxMesh:
        (dashboard.mesh as BoxMesh).size = Vector3(1.18, 0.10, 0.24)
        dashboard.position = Vector3(0.0, 0.80 if not is_coupe else 0.77, -1.00)
    var console := cabin.get_node_or_null(NodePath("CenterConsole")) as MeshInstance3D
    if console != null and console.mesh is BoxMesh:
        (console.mesh as BoxMesh).size = Vector3(0.14, 0.14, 0.46)
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
            if head.mesh is SphereMesh:
                (head.mesh as SphereMesh).radial_segments = 16
                (head.mesh as SphereMesh).rings = 8
        var cap := officer.get_node_or_null(NodePath("Cap")) as MeshInstance3D
        if cap != null:
            cap.scale = Vector3(0.88, 0.72, 0.88)
        officer.set_meta("v3_seated_clearance_tuned", true)
        officer.set_meta("v4_seated_proportion_tuned", true)
