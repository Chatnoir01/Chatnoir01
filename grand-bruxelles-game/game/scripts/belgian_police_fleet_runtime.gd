extends Node

const POLICE_VISUALS_SCRIPT := preload("res://game/scripts/police_vehicle_visuals.gd")
const HOLDER_NAME := "BelgianPoliceFleetVisual"
const MIDI_URBAN_LIFE_PATH := NodePath("MidiUrbanLife")
const TARGET_NAMES: Array[String] = [
    "ParkedCar_00",
    "ParkedCar_03",
    "ParkedCar_06",
    "AmbientTraffic_00",
    "AmbientTraffic_03",
]

const PROFILE_IDS: Array[String] = [
    "brussels_capitale_sedan",
    "skoda_octavia_break_reference",
    "volvo_xc60_bredene_de_haan_reference",
    "lokale_politie_patrouillewagen_reference",
    "brussels_rapid_response_coupe",
]

const PROFILES: Array[Dictionary] = [
    {
        "id": "brussels_capitale_sedan",
        "display_name": "Police Bruxelles Capitale · berline",
        "shape": "sedan",
        "size": Vector3(1.84, 1.45, 4.65),
        "source_reference": "Sans+titre.zip / Ford_Mondeo_2006 / Bruxelles Capitale",
        "source_sha256": "999cb77cf6bad64c69a357df1d3a2fba4a32b01a5ee99d0f3d1df2d701dd0583",
        "authored_path": "res://assets/vehicles/mmc_generic_sedan/generic_sedan.glb",
        "authored_status": "optional_licensed_base_when_present",
    },
    {
        "id": "skoda_octavia_break_reference",
        "display_name": "Police locale · break intervention",
        "shape": "estate",
        "size": Vector3(1.83, 1.48, 4.70),
        "source_reference": "4f990d-Belgian Police Skoda Octavia VRS Break.rar",
        "source_sha256": "9a56fca40caa1143dfea810de059d5558bf2eec521bfc046483d44fe49a2985a",
        "authored_path": "",
        "authored_status": "gta_mod_reference_only",
    },
    {
        "id": "volvo_xc60_bredene_de_haan_reference",
        "display_name": "Lokale Politie · SUV",
        "shape": "suv",
        "size": Vector3(1.90, 1.67, 4.71),
        "source_reference": "Volvo XC60 Bredene-De Haan Police ELS.rar",
        "source_sha256": "f9fb467bfe9bb8115fcde34791580700a4256883bf01df2b53c7fca68d76680d",
        "authored_path": "",
        "authored_status": "gta_mod_reference_only",
    },
    {
        "id": "lokale_politie_patrouillewagen_reference",
        "display_name": "Lokale Politie · patrouille",
        "shape": "hatch",
        "size": Vector3(1.80, 1.52, 4.34),
        "source_reference": "Lokale+politie+-+patrouillewagen+4.skp",
        "source_sha256": "e29c8efd94ba0efdaf4004925789570fddfeddaf2d387e9e0ace9dee570b1cc6",
        "authored_path": "",
        "authored_status": "sketchup_reference_pending_conversion_and_license",
    },
    {
        "id": "brussels_rapid_response_coupe",
        "display_name": "Police · intervention rapide",
        "shape": "coupe",
        "size": Vector3(1.86, 1.36, 4.48),
        "source_reference": "generic_sport_coupe_car.glb / MMC Works licensed base",
        "source_sha256": "5c3d5836d19b12347d9ab8e044fe9593b15255d211282ffa374f140e58d9eabd",
        "authored_path": "res://assets/vehicles/mmc_generic_sport_coupe/generic_sport_coupe.glb",
        "authored_status": "optional_licensed_base_when_present",
    },
]

var _installed := false
var _attempts := 0
var _installed_vehicle_names: Array[String] = []

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
        print("BELGIAN_POLICE_FLEET_READY: profiles=5 installed=5 renderer_only=true traffic_motion_preserved=true")
    elif _attempts > 600:
        set_process(false)
        push_warning("Belgian police fleet: MidiUrbanLife targets were not ready after 600 frames")

func _try_install() -> bool:
    var scene: Node = get_tree().current_scene
    if scene == null:
        return false
    var midi: Node = scene.get_node_or_null(MIDI_URBAN_LIFE_PATH)
    if midi == null:
        return false
    var targets: Array[Node3D] = []
    for target_name: String in TARGET_NAMES:
        var target := midi.get_node_or_null(NodePath(target_name)) as Node3D
        if target == null:
            return false
        targets.append(target)
    for index: int in range(PROFILES.size()):
        if not apply_profile_to_vehicle(targets[index], index):
            return false
    return true

func profile_count() -> int:
    return PROFILES.size()

func profile_ids() -> Array[String]:
    return PROFILE_IDS.duplicate()

func installed_vehicle_names() -> Array[String]:
    return _installed_vehicle_names.duplicate()

func get_contract() -> Dictionary:
    return {
        "profile_count": PROFILES.size(),
        "renderer_only": true,
        "changes_physics": false,
        "changes_collision": false,
        "changes_traffic_motion": false,
        "changes_geography": false,
        "third_party_gta_geometry_committed": false,
        "reference_only_sources_fail_closed": true,
    }

func apply_profile_to_vehicle(vehicle: Node3D, profile_index: int) -> bool:
    if vehicle == null or profile_index < 0 or profile_index >= PROFILES.size():
        return false
    var profile: Dictionary = PROFILES[profile_index]
    var existing := vehicle.get_node_or_null(NodePath(HOLDER_NAME)) as Node3D
    if existing != null:
        existing.visible = true
        return true
    var holder := Node3D.new()
    holder.name = HOLDER_NAME
    holder.set_meta("police_profile_id", str(profile.get("id", "")))
    holder.set_meta("police_display_name", str(profile.get("display_name", "")))
    holder.set_meta("source_reference", str(profile.get("source_reference", "")))
    holder.set_meta("source_sha256", str(profile.get("source_sha256", "")))
    holder.set_meta("renderer_only", true)
    holder.set_meta("production_authorized_exact_third_party_geometry", false)
    holder.add_to_group("police_marked")
    var fallback := vehicle.get_node_or_null(NodePath("ProductionVisual")) as Node3D
    var authored_mounted: bool = _mount_optional_authored_base(holder, profile)
    if not authored_mounted:
        _build_procedural_reference_body(holder, profile)
    _add_belgian_livery(holder, profile)
    _add_wheels(holder, profile)
    _add_emergency_systems(holder, profile)
    vehicle.add_to_group("police_marked")
    vehicle.add_to_group("belgian_police_vehicle")
    vehicle.set_meta("police_profile_id", str(profile.get("id", "")))
    vehicle.add_child(holder)
    if fallback != null:
        fallback.visible = false
        holder.set_meta("fallback_node", fallback.name)
    if not _installed_vehicle_names.has(str(vehicle.name)):
        _installed_vehicle_names.append(str(vehicle.name))
    return true

func set_profile_visible(vehicle: Node3D, enabled: bool) -> void:
    if vehicle == null:
        return
    var holder := vehicle.get_node_or_null(NodePath(HOLDER_NAME)) as Node3D
    var fallback := vehicle.get_node_or_null(NodePath("ProductionVisual")) as Node3D
    if holder != null:
        holder.visible = enabled
    if fallback != null:
        fallback.visible = not enabled

func _mount_optional_authored_base(holder: Node3D, profile: Dictionary) -> bool:
    var path: String = str(profile.get("authored_path", ""))
    if path.is_empty() or not ResourceLoader.exists(path):
        holder.set_meta("authored_mount", "absent_fallback_reference_body")
        return false
    var packed: Resource = ResourceLoader.load(path)
    if packed == null or not packed is PackedScene:
        holder.set_meta("authored_mount", "load_failed_fallback_reference_body")
        return false
    var instance := (packed as PackedScene).instantiate() as Node3D
    if instance == null:
        holder.set_meta("authored_mount", "instantiate_failed_fallback_reference_body")
        return false
    instance.name = "AuthoredBase"
    holder.add_child(instance)
    var bounds: AABB = _mesh_bounds(instance)
    if bounds.size.length_squared() <= 0.000001:
        instance.queue_free()
        holder.set_meta("authored_mount", "bounds_failed_fallback_reference_body")
        return false
    var target_size: Vector3 = profile.get("size", Vector3(1.84, 1.45, 4.65)) as Vector3
    var long_x: bool = bounds.size.x > bounds.size.z
    if long_x:
        instance.rotation_degrees.y = 90.0
    var source_length: float = bounds.size.x if long_x else bounds.size.z
    var scale_value: float = target_size.z / maxf(source_length, 0.001)
    instance.scale = Vector3.ONE * scale_value
    instance.position = Vector3(0.0, -bounds.position.y * scale_value, 0.0)
    holder.set_meta("authored_mount", "mounted")
    holder.set_meta("authored_uniform_scale", scale_value)
    return true

func _build_procedural_reference_body(holder: Node3D, profile: Dictionary) -> void:
    var shape: String = str(profile.get("shape", "sedan"))
    var size: Vector3 = profile.get("size", Vector3(1.84, 1.45, 4.65)) as Vector3
    var body_mat: StandardMaterial3D = _material(Color(0.91, 0.92, 0.92, 1.0), 0.31, 0.18)
    var glass_mat: StandardMaterial3D = _material(Color(0.045, 0.075, 0.095, 0.90), 0.12, 0.12)
    _box(holder, "LowerBody", Vector3(size.x, 0.58, size.z), Vector3(0.0, 0.55, 0.0), body_mat)
    _box(holder, "Hood", Vector3(size.x * 0.92, 0.20, size.z * 0.23), Vector3(0.0, 0.89, -size.z * 0.34), body_mat)
    _box(holder, "Trunk", Vector3(size.x * 0.92, 0.18, size.z * 0.20), Vector3(0.0, 0.86, size.z * 0.37), body_mat)
    var cabin_size: Vector3 = Vector3(size.x * 0.82, 0.63, size.z * 0.45)
    var cabin_pos: Vector3 = Vector3(0.0, 1.11, 0.02)
    match shape:
        "estate":
            cabin_size = Vector3(size.x * 0.84, 0.67, size.z * 0.56)
            cabin_pos = Vector3(0.0, 1.13, 0.14)
        "suv":
            cabin_size = Vector3(size.x * 0.85, 0.83, size.z * 0.53)
            cabin_pos = Vector3(0.0, 1.25, 0.10)
        "hatch":
            cabin_size = Vector3(size.x * 0.83, 0.72, size.z * 0.51)
            cabin_pos = Vector3(0.0, 1.16, 0.10)
        "coupe":
            cabin_size = Vector3(size.x * 0.78, 0.54, size.z * 0.39)
            cabin_pos = Vector3(0.0, 1.05, -0.02)
        _:
            pass
    _box(holder, "Cabin", cabin_size, cabin_pos, glass_mat)
    var bumper_mat: StandardMaterial3D = _material(Color(0.035, 0.04, 0.045, 1.0), 0.64, 0.05)
    _box(holder, "FrontBumper", Vector3(size.x * 0.94, 0.16, 0.13), Vector3(0.0, 0.48, -size.z * 0.505), bumper_mat)
    _box(holder, "RearBumper", Vector3(size.x * 0.94, 0.16, 0.13), Vector3(0.0, 0.48, size.z * 0.505), bumper_mat)
    holder.set_meta("authored_mount", "procedural_reference_body")

func _add_belgian_livery(holder: Node3D, profile: Dictionary) -> void:
    var size: Vector3 = profile.get("size", Vector3(1.84, 1.45, 4.65)) as Vector3
    var blue: StandardMaterial3D = _material(Color(0.015, 0.18, 0.46, 1.0), 0.40)
    var yellow: StandardMaterial3D = _material(Color(0.88, 0.94, 0.12, 1.0), 0.44)
    var side_x: float = size.x * 0.505
    var block_length: float = size.z * 0.18
    for side: float in [-1.0, 1.0]:
        for index: int in range(4):
            var z: float = -size.z * 0.27 + float(index) * block_length
            var material: StandardMaterial3D = blue if index % 2 == 0 else yellow
            _box(holder, "Livery_%s_%d" % ["L" if side < 0.0 else "R", index], Vector3(0.025, 0.30, block_length * 0.94), Vector3(side_x * side, 0.70, z), material)
    var front_blue: StandardMaterial3D = _emissive_material(Color(0.01, 0.19, 0.88, 1.0), 1.8)
    _box(holder, "FrontBlueLeft", Vector3(0.24, 0.08, 0.035), Vector3(-0.42, 0.67, -size.z * 0.515), front_blue)
    _box(holder, "FrontBlueRight", Vector3(0.24, 0.08, 0.035), Vector3(0.42, 0.67, -size.z * 0.515), front_blue)

func _add_wheels(holder: Node3D, profile: Dictionary) -> void:
    var size: Vector3 = profile.get("size", Vector3(1.84, 1.45, 4.65)) as Vector3
    var wheel_mat: StandardMaterial3D = _material(Color(0.018, 0.02, 0.022, 1.0), 0.88)
    var rim_mat: StandardMaterial3D = _material(Color(0.34, 0.37, 0.40, 1.0), 0.32, 0.62)
    var wheel_radius: float = 0.34 if str(profile.get("shape", "")) != "suv" else 0.38
    var wheel_z: float = size.z * 0.32
    var wheel_x: float = size.x * 0.52
    for x_sign: float in [-1.0, 1.0]:
        for z_sign: float in [-1.0, 1.0]:
            var wheel := MeshInstance3D.new()
            wheel.name = "Wheel_%s_%s" % ["L" if x_sign < 0.0 else "R", "F" if z_sign < 0.0 else "R"]
            var tire := CylinderMesh.new()
            tire.top_radius = wheel_radius
            tire.bottom_radius = wheel_radius
            tire.height = 0.24
            tire.radial_segments = 18
            wheel.mesh = tire
            wheel.material_override = wheel_mat
            wheel.position = Vector3(wheel_x * x_sign, wheel_radius, wheel_z * z_sign)
            wheel.rotation_degrees = Vector3(0.0, 0.0, 90.0)
            holder.add_child(wheel)
            var rim := MeshInstance3D.new()
            rim.name = wheel.name + "_Rim"
            var rim_mesh := CylinderMesh.new()
            rim_mesh.top_radius = wheel_radius * 0.55
            rim_mesh.bottom_radius = wheel_radius * 0.55
            rim_mesh.height = 0.252
            rim_mesh.radial_segments = 14
            rim.mesh = rim_mesh
            rim.material_override = rim_mat
            rim.position = wheel.position
            rim.rotation_degrees = wheel.rotation_degrees
            holder.add_child(rim)

func _add_emergency_systems(holder: Node3D, profile: Dictionary) -> void:
    var size: Vector3 = profile.get("size", Vector3(1.84, 1.45, 4.65)) as Vector3
    var roof_y: float = size.y + 0.14
    var systems := Node3D.new()
    systems.name = "EmergencySystems"
    var left := Node3D.new()
    left.name = "LeftFlashGroup"
    systems.add_child(left)
    var right := Node3D.new()
    right.name = "RightFlashGroup"
    systems.add_child(right)
    var blue: StandardMaterial3D = _emissive_material(Color(0.015, 0.21, 1.0, 1.0), 3.2)
    var dark: StandardMaterial3D = _material(Color(0.025, 0.03, 0.035, 1.0), 0.45, 0.25)
    _box(systems, "LightbarBase", Vector3(size.x * 0.66, 0.075, 0.18), Vector3(0.0, roof_y, 0.0), dark)
    _box(left, "BlueLeft", Vector3(size.x * 0.29, 0.105, 0.19), Vector3(-size.x * 0.17, roof_y + 0.055, 0.0), blue)
    _box(right, "BlueRight", Vector3(size.x * 0.29, 0.105, 0.19), Vector3(size.x * 0.17, roof_y + 0.055, 0.0), blue)
    systems.set_script(POLICE_VISUALS_SCRIPT)
    systems.set("start_active", true)
    holder.add_child(systems)

func _mesh_bounds(root_node: Node3D) -> AABB:
    var has_bounds := false
    var result := AABB()
    var pending: Array[Node] = [root_node]
    while not pending.is_empty():
        var current: Node = pending.pop_back()
        if current is MeshInstance3D:
            var mesh_instance := current as MeshInstance3D
            if mesh_instance.mesh != null:
                var local_aabb: AABB = mesh_instance.get_aabb()
                var transform_to_root: Transform3D = root_node.global_transform.affine_inverse() * mesh_instance.global_transform
                var transformed: AABB = transform_to_root * local_aabb
                if has_bounds:
                    result = result.merge(transformed)
                else:
                    result = transformed
                    has_bounds = true
        for child: Node in current.get_children():
            pending.append(child)
    return result if has_bounds else AABB()

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material

func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
    var material: StandardMaterial3D = _material(color, 0.24, 0.05)
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = energy
    return material

func _box(parent: Node3D, name_value: String, size_value: Vector3, position_value: Vector3, material: Material) -> MeshInstance3D:
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = name_value
    var mesh := BoxMesh.new()
    mesh.size = size_value
    mesh_instance.mesh = mesh
    mesh_instance.material_override = material
    mesh_instance.position = position_value
    parent.add_child(mesh_instance)
    return mesh_instance
