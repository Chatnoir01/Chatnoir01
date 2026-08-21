extends Node

const PAYLOAD := preload("res://game/scripts/authored_geometry_payload.gd")
const FLEET_SCRIPT := preload("res://game/scripts/belgian_police_fleet_runtime.gd")
const VEHICLE_PHYSICS_SCRIPT := preload("res://game/scripts/vehicle_physics_controller.gd")
const HOLDER_NAME := "BelgianPoliceFleetVisual"
const DRIVEABLE_NAME := "DriveablePoliceSedanV2"
const BODY_CHILDREN: Array[String] = ["LowerBody", "Hood", "Trunk", "Cabin", "FrontBumper", "RearBumper"]
const CONFIGS: Array[Dictionary] = [
    {
        "vehicle": DRIVEABLE_NAME,
        "profile": "brussels_capitale_sedan",
        "payload_dir": "res://assets/vehicles/mmc_generic_sedan/authored_lod",
        "parts": 3,
        "raw_bytes": 29489,
        "triangles": 2697,
        "vertices": 1465,
        "target_length": 4.65,
        "payload_sha256": "73c6cc1c05b667d09e277d30f8ca2046947d26a63fb6699d865aaf2ca449ad07",
        "source_interior": false,
    },
    {
        "vehicle": "AmbientTraffic_03",
        "profile": "brussels_rapid_response_coupe",
        "payload_dir": "res://assets/vehicles/mmc_generic_sport_coupe/authored_lod",
        "parts": 3,
        "raw_bytes": 23889,
        "triangles": 2121,
        "vertices": 1230,
        "target_length": 4.48,
        "payload_sha256": "438c03fb92a3b25aaaae8d8785e7743da6c2035d4ea8ca5b63faca92755f3dbf",
        "source_interior": false,
    },
]

var _installed := false
var _attempts := 0

func _ready() -> void:
    set_process(true)

func _process(_delta: float) -> void:
    if _installed:
        set_process(false)
        return
    _attempts += 1
    if _try_install():
        _installed = true
        set_process(false)
        print("MMC_POLICE_V3_READY: sedan_triangles=2697 coupe_triangles=2121 source_overlay=2 body_closures=2 project_cabins=2 officers=3 driveable_sedan=true")
    elif _attempts > 600:
        set_process(false)
        push_warning("MMC police V2: police targets were not ready after 600 frames")

func config_count() -> int:
    return CONFIGS.size()

func config_at(index: int) -> Dictionary:
    if index < 0 or index >= CONFIGS.size():
        return {}
    return CONFIGS[index].duplicate(true)

func get_contract() -> Dictionary:
    return {
        "source_derived_lod_count": 2,
        "project_cabin_count": 2,
        "project_body_closure_count": 2,
        "source_derived_detail_overlay_count": 2,
        "police_officer_count": 3,
        "driveable_police_vehicle_count": 1,
        "changes_existing_physics": false,
        "changes_existing_collision": false,
        "changes_traffic_motion": false,
        "changes_geography": false,
        "adds_driveable_police_physics": true,
        "exact_source_glb_committed": false,
    }

func spawn_driveable_sedan(scene: Node, reference: Node3D) -> RigidBody3D:
    if scene == null or reference == null:
        return null
    var existing := scene.get_node_or_null(NodePath(DRIVEABLE_NAME)) as RigidBody3D
    if existing != null:
        return existing
    var car := RigidBody3D.new()
    car.name = DRIVEABLE_NAME
    car.set_script(VEHICLE_PHYSICS_SCRIPT)
    car.add_to_group("vehicle")
    car.add_to_group("police_marked")
    car.add_to_group("belgian_police_vehicle")
    car.set_meta("replaces_static_reference", str(reference.name))
    car.set_meta("driveable_police_v2", true)

    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var shape := BoxShape3D.new()
    shape.size = Vector3(1.90, 0.90, 4.20)
    collision.shape = shape
    car.add_child(collision)

    var camera_pivot := Node3D.new()
    camera_pivot.name = "CameraPivot"
    camera_pivot.position = Vector3(0.0, 1.32, 0.15)
    camera_pivot.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
    car.add_child(camera_pivot)
    var spring_arm := SpringArm3D.new()
    spring_arm.name = "SpringArm3D"
    spring_arm.spring_length = 5.7
    spring_arm.margin = 0.18
    camera_pivot.add_child(spring_arm)
    var camera := Camera3D.new()
    camera.name = "Camera3D"
    camera.current = false
    camera.fov = 70.0
    spring_arm.add_child(camera)

    scene.add_child(car)
    var t := reference.global_transform
    t.origin.y += 0.30
    car.global_transform = t
    var fleet := FLEET_SCRIPT.new()
    if not bool(fleet.call("apply_profile_to_vehicle", car, 0)):
        car.queue_free()
        return null
    reference.visible = false
    reference.set_meta("replaced_by_driveable_police_v2", true)
    return car

func install_on_holder(holder: Node3D, config: Dictionary) -> bool:
    if holder == null:
        return false
    if str(holder.get_meta("police_profile_id", "")) != str(config.get("profile", "")):
        return false
    var existing := holder.get_node_or_null(NodePath("AuthoredSourceDerivedLOD")) as Node3D
    if existing == null:
        var authored := PAYLOAD.build_from_parts(str(config.get("payload_dir", "")), int(config.get("parts", 0)), int(config.get("raw_bytes", 0)))
        if authored == null:
            return false
        var bounds_min: Vector3 = authored.get_meta("source_bounds_min", Vector3.ZERO) as Vector3
        var bounds_max: Vector3 = authored.get_meta("source_bounds_max", Vector3.ZERO) as Vector3
        var source_size := bounds_max - bounds_min
        var source_length := maxf(source_size.x, source_size.z)
        if source_length <= 0.001:
            authored.free()
            return false
        if source_size.x > source_size.z:
            authored.rotation_degrees.y = 90.0
        var scale_value := float(config.get("target_length", 4.6)) / source_length
        authored.scale = Vector3.ONE * scale_value
        authored.position = Vector3(0.0, -bounds_min.y * scale_value, 0.0)
        authored.set_meta("payload_sha256", str(config.get("payload_sha256", "")))
        authored.set_meta("uniform_scale", scale_value)
        authored.set_meta("source_interior_retained", bool(config.get("source_interior", false)))
        holder.add_child(authored)
        if int(authored.get_meta("source_triangles", -1)) != int(config.get("triangles", -2)):
            authored.queue_free()
            return false
        if int(authored.get_meta("source_vertices", -1)) != int(config.get("vertices", -2)):
            authored.queue_free()
            return false
        existing = authored
    existing.visible = true
    for child_name: String in BODY_CHILDREN:
        var child := holder.get_node_or_null(NodePath(child_name)) as Node3D
        if child != null:
            child.visible = false
    holder.set_meta("authored_mount", "source_derived_v2_material_cabin")
    holder.set_meta("authored_source_derived_lod", true)
    holder.set_meta("authored_source_interior", false)
    holder.set_meta("authored_payload_sha256", str(config.get("payload_sha256", "")))
    holder.set_meta("authored_triangles", int(config.get("triangles", 0)))
    holder.set_meta("production_authorized_exact_third_party_geometry", false)
    if not install_body_closure(holder, config):
        return false
    if not install_cabin(holder):
        return false
    return true

func install_body_closure(holder: Node3D, config: Dictionary) -> bool:
    if holder == null:
        return false
    var existing := holder.get_node_or_null(NodePath("PoliceBodyClosureV3")) as Node3D
    if existing != null:
        existing.visible = true
        return true

    var closure := Node3D.new()
    closure.name = "PoliceBodyClosureV3"
    closure.set_meta("purpose", "fill_source_lod_decimation_gaps")
    closure.set_meta("source_lod_remains_visible", true)
    closure.set_meta("changes_collision", false)
    closure.set_meta("changes_physics", false)
    holder.add_child(closure)

    var profile_id := str(config.get("profile", ""))
    var is_coupe := "coupe" in profile_id
    var body_length := 4.08 if is_coupe else 4.24
    var body_width := 1.72 if is_coupe else 1.74
    var body_y := 0.54
    var paint := _material(Color(0.90, 0.915, 0.925, 1.0), 0.26)
    paint.metallic = 0.16
    var trim := _material(Color(0.025, 0.03, 0.035, 1.0), 0.70)
    var glass := _material(Color(0.035, 0.075, 0.105, 0.36), 0.12)
    glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    glass.cull_mode = BaseMaterial3D.CULL_DISABLED
    var headlamp := _material(Color(0.78, 0.88, 0.96, 0.90), 0.10)
    headlamp.emission_enabled = true
    headlamp.emission = Color(0.34, 0.42, 0.50, 1.0)
    headlamp.emission_energy_multiplier = 0.55
    var taillamp := _material(Color(0.66, 0.025, 0.035, 0.92), 0.18)
    taillamp.emission_enabled = true
    taillamp.emission = Color(0.26, 0.0, 0.0, 1.0)
    taillamp.emission_energy_multiplier = 0.50

    _box(closure, "ClosedLowerBody", Vector3(body_width, 0.48, body_length), Vector3(0.0, body_y, 0.0), paint)
    _box(closure, "HoodClosure", Vector3(body_width * 0.95, 0.12, 1.34 if is_coupe else 1.24), Vector3(0.0, 0.82, -1.42), paint)
    _box(closure, "TrunkClosure", Vector3(body_width * 0.94, 0.11, 0.82 if is_coupe else 1.02), Vector3(0.0, 0.81, 1.58), paint)
    _box(closure, "RoofPanel", Vector3(body_width * 0.77, 0.075, 1.22 if is_coupe else 1.48), Vector3(0.0, 1.32 if not is_coupe else 1.23, 0.10), paint)
    _box(closure, "FrontGrille", Vector3(body_width * 0.46, 0.16, 0.035), Vector3(0.0, 0.56, -body_length * 0.505), trim)
    _box(closure, "RearLowerTrim", Vector3(body_width * 0.62, 0.10, 0.035), Vector3(0.0, 0.51, body_length * 0.505), trim)
    _box(closure, "LeftRocker", Vector3(0.045, 0.10, body_length * 0.72), Vector3(-body_width * 0.505, 0.36, 0.05), trim)
    _box(closure, "RightRocker", Vector3(0.045, 0.10, body_length * 0.72), Vector3(body_width * 0.505, 0.36, 0.05), trim)

    var windshield := _box(closure, "Windshield", Vector3(body_width * 0.78, 0.47 if is_coupe else 0.52, 0.035), Vector3(0.0, 1.08, -0.72), glass)
    windshield.rotation_degrees.x = -20.0 if is_coupe else -17.0
    var rear_window := _box(closure, "RearWindow", Vector3(body_width * 0.76, 0.42 if is_coupe else 0.48, 0.035), Vector3(0.0, 1.07, 0.85), glass)
    rear_window.rotation_degrees.x = 22.0 if is_coupe else 18.0
    var side_len := 1.12 if is_coupe else 1.38
    _box(closure, "LeftSideGlass", Vector3(0.025, 0.40 if is_coupe else 0.45, side_len), Vector3(-body_width * 0.405, 1.08, 0.05), glass)
    _box(closure, "RightSideGlass", Vector3(0.025, 0.40 if is_coupe else 0.45, side_len), Vector3(body_width * 0.405, 1.08, 0.05), glass)

    var lamp_z := body_length * 0.508
    _box(closure, "HeadlampLeft", Vector3(0.42, 0.12, 0.032), Vector3(-0.53, 0.72, -lamp_z), headlamp)
    _box(closure, "HeadlampRight", Vector3(0.42, 0.12, 0.032), Vector3(0.53, 0.72, -lamp_z), headlamp)
    _box(closure, "TaillampLeft", Vector3(0.36, 0.14, 0.032), Vector3(-0.55, 0.70, lamp_z), taillamp)
    _box(closure, "TaillampRight", Vector3(0.36, 0.14, 0.032), Vector3(0.55, 0.70, lamp_z), taillamp)

    holder.set_meta("project_body_closure_v3", true)
    holder.set_meta("source_lod_detail_overlay_preserved", true)
    return true

func install_cabin(holder: Node3D) -> bool:
    if holder == null:
        return false
    if holder.get_node_or_null(NodePath("PoliceCabinV2")) != null:
        return true
    var cabin := Node3D.new()
    cabin.name = "PoliceCabinV2"
    holder.add_child(cabin)
    var upholstery := _material(Color(0.045, 0.052, 0.062, 1.0), 0.86)
    var dash := _material(Color(0.025, 0.032, 0.040, 1.0), 0.72)
    var metal := _material(Color(0.18, 0.20, 0.22, 1.0), 0.38)
    _box(cabin, "DriverSeatBottom", Vector3(0.46, 0.16, 0.48), Vector3(-0.43, 0.55, -0.10), upholstery)
    _box(cabin, "DriverSeatBack", Vector3(0.46, 0.62, 0.14), Vector3(-0.43, 0.88, 0.11), upholstery)
    _box(cabin, "PassengerSeatBottom", Vector3(0.46, 0.16, 0.48), Vector3(0.43, 0.55, -0.10), upholstery)
    _box(cabin, "PassengerSeatBack", Vector3(0.46, 0.62, 0.14), Vector3(0.43, 0.88, 0.11), upholstery)
    _box(cabin, "Dashboard", Vector3(1.45, 0.18, 0.34), Vector3(0.0, 0.86, -1.10), dash)
    _box(cabin, "CenterConsole", Vector3(0.18, 0.22, 0.62), Vector3(0.0, 0.58, -0.43), dash)
    var wheel := TorusMesh.new()
    wheel.inner_radius = 0.12
    wheel.outer_radius = 0.19
    wheel.rings = 12
    wheel.ring_segments = 8
    var wheel_node := MeshInstance3D.new()
    wheel_node.name = "SteeringWheel"
    wheel_node.mesh = wheel
    wheel_node.position = Vector3(-0.43, 0.91, -0.82)
    wheel_node.rotation_degrees.x = 66.0
    wheel_node.material_override = metal
    cabin.add_child(wheel_node)
    holder.set_meta("project_cabin_v2", true)
    return true

func install_officers(holder: Node3D, driveable: bool) -> bool:
    if holder == null:
        return false
    var existing := holder.get_node_or_null(NodePath("PoliceOccupantsV2")) as Node3D
    if existing != null:
        return true
    var occupants := Node3D.new()
    occupants.name = "PoliceOccupantsV2"
    holder.add_child(occupants)
    if driveable:
        _build_officer(occupants, "PassengerOfficer", Vector3(0.43, 0.0, -0.18))
        holder.set_meta("officer_count", 1)
        holder.set_meta("driver_seat_reserved_for_player", true)
    else:
        _build_officer(occupants, "DriverOfficer", Vector3(-0.43, 0.0, -0.18))
        _build_officer(occupants, "PassengerOfficer", Vector3(0.43, 0.0, -0.18))
        holder.set_meta("officer_count", 2)
    return true

func _build_officer(parent: Node3D, officer_name: String, seat_offset: Vector3) -> void:
    var officer := Node3D.new()
    officer.name = officer_name
    officer.position = seat_offset
    parent.add_child(officer)
    var uniform := _material(Color(0.025, 0.075, 0.16, 1.0), 0.82)
    var uniform_dark := _material(Color(0.018, 0.03, 0.065, 1.0), 0.88)
    var skin := _material(Color(0.62, 0.43, 0.31, 1.0), 0.76)
    var hi_vis := _material(Color(0.17, 0.62, 0.78, 1.0), 0.56)
    _box(officer, "Torso", Vector3(0.38, 0.46, 0.24), Vector3(0.0, 0.91, 0.02), uniform)
    _box(officer, "VestStripe", Vector3(0.385, 0.07, 0.025), Vector3(0.0, 0.96, -0.13), hi_vis)
    _box(officer, "LeftArm", Vector3(0.12, 0.40, 0.13), Vector3(-0.25, 0.88, -0.01), uniform)
    _box(officer, "RightArm", Vector3(0.12, 0.40, 0.13), Vector3(0.25, 0.88, -0.01), uniform)
    _box(officer, "LeftLeg", Vector3(0.15, 0.42, 0.17), Vector3(-0.11, 0.55, -0.18), uniform_dark)
    _box(officer, "RightLeg", Vector3(0.15, 0.42, 0.17), Vector3(0.11, 0.55, -0.18), uniform_dark)
    _sphere(officer, "Head", 0.17, Vector3(0.0, 1.29, 0.0), skin)
    _box(officer, "Cap", Vector3(0.31, 0.07, 0.25), Vector3(0.0, 1.44, -0.02), uniform_dark)
    officer.set_meta("role", "police_officer")
    officer.set_meta("pose", "seated")
    officer.set_meta("collision_free_visual", true)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness
    return mat

func _box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = node_name
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_instance.mesh = mesh
    mesh_instance.position = position
    mesh_instance.material_override = material
    parent.add_child(mesh_instance)
    return mesh_instance

func _sphere(parent: Node3D, node_name: String, radius: float, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = node_name
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh.radial_segments = 12
    mesh.rings = 6
    mesh_instance.mesh = mesh
    mesh_instance.position = position
    mesh_instance.material_override = material
    parent.add_child(mesh_instance)
    return mesh_instance

func _try_install() -> bool:
    var scene: Node = get_tree().current_scene
    if scene == null:
        return false
    var midi := scene.get_node_or_null(NodePath("MidiUrbanLife")) as Node3D
    if midi == null:
        return false
    var parked := midi.get_node_or_null(NodePath("ParkedCar_00")) as Node3D
    if parked == null:
        return false
    var driveable := spawn_driveable_sedan(scene, parked)
    if driveable == null:
        return false
    var sedan_holder := driveable.get_node_or_null(NodePath(HOLDER_NAME)) as Node3D
    if sedan_holder == null or not install_on_holder(sedan_holder, CONFIGS[0]) or not install_officers(sedan_holder, true):
        return false
    var coupe := midi.get_node_or_null(NodePath("AmbientTraffic_03")) as Node3D
    if coupe == null:
        return false
    var coupe_holder := coupe.get_node_or_null(NodePath(HOLDER_NAME)) as Node3D
    if coupe_holder == null:
        var fleet := FLEET_SCRIPT.new()
        if not bool(fleet.call("apply_profile_to_vehicle", coupe, 4)):
            return false
        coupe_holder = coupe.get_node_or_null(NodePath(HOLDER_NAME)) as Node3D
    if coupe_holder == null or not install_on_holder(coupe_holder, CONFIGS[1]) or not install_officers(coupe_holder, false):
        return false
    return true
