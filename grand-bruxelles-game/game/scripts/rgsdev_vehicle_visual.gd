extends Node3D
class_name RgsdevVehicleVisual

const PACK_CONTRACT := "rgsdev_cc0_vehicles_v1"
const COMPACT_MAGIC := "RGV1"
const PACK_MAGIC := "RGP1"
const MAX_DECOMPRESSED_PACK_BYTES := 1024 * 1024
const MODEL_IDS := [
    "sedan", "hatchback", "suv", "van", "pickup", "muscle", "muscle_2", "roadster", "sports", "taxi", "limousine",
    "police_sedan", "police_suv", "police_muscle", "police_sports",
]
const PACK_CHUNK_PATHS := [
    "res://game/assets/vehicles/rgsdev/vehicles_00.rgvp",
    "res://game/assets/vehicles/rgsdev/vehicles_01.rgvp",
    "res://game/assets/vehicles/rgsdev/vehicles_02.rgvp",
    "res://game/assets/vehicles/rgsdev/vehicles_03.rgvp",
    "res://game/assets/vehicles/rgsdev/vehicles_04.rgvp",
    "res://game/assets/vehicles/rgsdev/vehicles_05.rgvp",
    "res://game/assets/vehicles/rgsdev/vehicles_06.rgvp",
    "res://game/assets/vehicles/rgsdev/vehicles_07.rgvp",
    "res://game/assets/vehicles/rgsdev/vehicles_08.rgvp",
    "res://game/assets/vehicles/rgsdev/vehicles_09.rgvp",
]
const CIVILIAN_MODELS := [
    "sedan", "hatchback", "suv", "van", "pickup", "muscle", "muscle_2", "roadster", "sports", "taxi", "limousine"
]
const POLICE_MODELS := ["police_sedan", "police_suv", "police_muscle", "police_sports"]
const SPECIAL_MODELS_REQUIRING_HEAVY_PHYSICS := [
    "ambulance", "bus", "firetruck", "monster_truck", "truck", "truck_with_trailer"
]
const MODEL_SCALES := {
    "sedan": Vector3(0.647, 0.721, 0.818),
    "hatchback": Vector3(0.640, 0.726, 0.803),
    "suv": Vector3(0.675, 0.749, 0.903),
    "van": Vector3(0.718, 0.812, 0.872),
    "pickup": Vector3(0.711, 0.859, 1.012),
    "muscle": Vector3(0.675, 0.733, 0.784),
    "muscle_2": Vector3(0.675, 0.733, 0.784),
    "roadster": Vector3(0.702, 0.679, 0.751),
    "sports": Vector3(0.702, 0.679, 0.751),
    "taxi": Vector3(0.647, 0.638, 0.818),
    "limousine": Vector3(0.682, 0.746, 0.615),
    "police_sedan": Vector3(0.647, 0.708, 0.818),
    "police_suv": Vector3(0.675, 0.795, 0.903),
    "police_muscle": Vector3(0.675, 0.718, 0.784),
    "police_sports": Vector3(0.702, 0.728, 0.751),
}

static var _scene_cache: Dictionary = {}
static var _model_payload_cache: Dictionary = {}
static var _pack_loaded := false

@export var model_id: String = "sedan"
@export var model_scale: Vector3 = Vector3.ONE
@export var model_rotation_degrees: Vector3 = Vector3.ZERO
@export var model_offset: Vector3 = Vector3.ZERO
@export var wheel_radius_m: float = 0.34
@export var animate_wheels: bool = true

var _instance: Node3D = null
var _wheel_nodes: Array[Node3D] = []
var _front_wheels: Array[Node3D] = []
var _wheel_base_rotation: Dictionary = {}
var _spin_angle: float = 0.0

func _ready() -> void:
    _load_model()

func configure_for_traffic(serial: int) -> void:
    model_id = CIVILIAN_MODELS[posmod(serial, CIVILIAN_MODELS.size())]

func configure_for_police(serial: int = 0) -> void:
    model_id = POLICE_MODELS[posmod(serial, POLICE_MODELS.size())]

func configure_model(new_model_id: String) -> void:
    if new_model_id in MODEL_IDS:
        model_id = new_model_id
    if is_inside_tree():
        _load_model()

func get_visual_contract() -> Dictionary:
    return {
        "quality": PACK_CONTRACT,
        "model_id": model_id,
        "source_path": "rgsdev_compact_pack:%s" % model_id,
        "license": "CC0",
        "wheel_animation": animate_wheels,
        "wheel_count": _wheel_nodes.size(),
        "road_models": MODEL_IDS.size(),
        "special_models_pending_heavy_physics": SPECIAL_MODELS_REQUIRING_HEAVY_PHYSICS.duplicate(),
    }

func instantiate_model_for_test(test_model_id: String) -> Node3D:
    return _instantiate_model(test_model_id)

func _load_model() -> void:
    if _instance != null and is_instance_valid(_instance):
        _instance.queue_free()
    _wheel_nodes.clear()
    _front_wheels.clear()
    _wheel_base_rotation.clear()
    _instance = _instantiate_model(model_id)
    if _instance == null:
        return
    _instance.name = "ImportedModel"
    var authored_scale: Vector3 = MODEL_SCALES.get(model_id, Vector3.ONE)
    _instance.scale = authored_scale * model_scale
    _instance.rotation_degrees = model_rotation_degrees
    _instance.position = model_offset
    add_child(_instance)
    _collect_wheels(_instance)
    set_meta("rgsdev_model_id", model_id)
    set_meta("rgsdev_source_path", "rgsdev_compact_pack:%s" % model_id)
    set_meta("rgsdev_license", "CC0")

func _instantiate_model(requested_model_id: String) -> Node3D:
    var safe_model_id := requested_model_id if requested_model_id in MODEL_IDS else "sedan"
    if _scene_cache.has(safe_model_id):
        var cached := _scene_cache[safe_model_id] as PackedScene
        return cached.instantiate() as Node3D
    if not _ensure_pack_loaded() or not _model_payload_cache.has(safe_model_id):
        push_error("RGSDEV compact pack does not contain model: %s" % safe_model_id)
        return null
    var raw: PackedByteArray = _model_payload_cache[safe_model_id]
    var generated := _decode_compact_scene(raw)
    if generated == null:
        push_error("RGSDEV compact model decode failed: %s" % safe_model_id)
        return null
    var packed := PackedScene.new()
    var pack_error := packed.pack(generated)
    if pack_error != OK:
        push_error("RGSDEV compact scene cache packing failed for %s: %s" % [safe_model_id, error_string(pack_error)])
        generated.free()
        return null
    _scene_cache[safe_model_id] = packed
    generated.free()
    return packed.instantiate() as Node3D

func _ensure_pack_loaded() -> bool:
    if _pack_loaded:
        return _model_payload_cache.size() == MODEL_IDS.size()
    var encoded := ""
    for path: String in PACK_CHUNK_PATHS:
        if not FileAccess.file_exists(path):
            push_error("RGSDEV compact pack chunk missing: %s" % path)
            return false
        encoded += FileAccess.get_file_as_string(path).strip_edges()
    var compressed := Marshalls.base64_to_raw(encoded)
    if compressed.is_empty():
        push_error("RGSDEV compact pack is invalid base64")
        return false
    var raw := compressed.decompress_dynamic(MAX_DECOMPRESSED_PACK_BYTES, FileAccess.COMPRESSION_ZSTD)
    if raw.is_empty():
        push_error("RGSDEV compact pack cannot be decompressed")
        return false
    var peer := StreamPeerBuffer.new()
    peer.big_endian = false
    peer.data_array = raw
    var magic_result := peer.get_data(4)
    if int(magic_result[0]) != OK or (magic_result[1] as PackedByteArray).get_string_from_ascii() != PACK_MAGIC:
        push_error("RGSDEV compact pack magic mismatch")
        return false
    var model_count := peer.get_u8()
    if model_count != MODEL_IDS.size():
        push_error("RGSDEV compact pack model count mismatch: %d" % model_count)
        return false
    _model_payload_cache.clear()
    for _index: int in range(model_count):
        var name_length := peer.get_u8()
        var name_result := peer.get_data(name_length)
        if int(name_result[0]) != OK:
            return false
        var packed_model_id := (name_result[1] as PackedByteArray).get_string_from_utf8()
        var byte_count := peer.get_u32()
        if byte_count <= 0 or byte_count > MAX_DECOMPRESSED_PACK_BYTES:
            return false
        var payload_result := peer.get_data(byte_count)
        if int(payload_result[0]) != OK:
            return false
        _model_payload_cache[packed_model_id] = payload_result[1] as PackedByteArray
    _pack_loaded = true
    return _model_payload_cache.size() == MODEL_IDS.size()

func _decode_compact_scene(raw: PackedByteArray) -> Node3D:
    var peer := StreamPeerBuffer.new()
    peer.big_endian = false
    peer.data_array = raw
    var magic_result := peer.get_data(4)
    if int(magic_result[0]) != OK or (magic_result[1] as PackedByteArray).get_string_from_ascii() != COMPACT_MAGIC:
        return null
    var root := Node3D.new()
    root.name = "RgsdevVehicleModel"
    var node_count := peer.get_u16()
    if node_count <= 0 or node_count > 64:
        root.free()
        return null
    for _node_index: int in range(node_count):
        var name_length := peer.get_u8()
        var name_result := peer.get_data(name_length)
        if int(name_result[0]) != OK:
            root.free()
            return null
        var node_name := (name_result[1] as PackedByteArray).get_string_from_utf8()
        var translation := Vector3(peer.get_float(), peer.get_float(), peer.get_float())
        var rotation := Quaternion(peer.get_float(), peer.get_float(), peer.get_float(), peer.get_float()).normalized()
        var node_scale := Vector3(peer.get_float(), peer.get_float(), peer.get_float())
        var primitive_count := peer.get_u8()
        if primitive_count <= 0 or primitive_count > 32:
            root.free()
            return null
        var array_mesh := ArrayMesh.new()
        for _primitive_index: int in range(primitive_count):
            var color := Color(float(peer.get_u8()) / 255.0, float(peer.get_u8()) / 255.0, float(peer.get_u8()) / 255.0, float(peer.get_u8()) / 255.0)
            var roughness := float(peer.get_u8()) / 255.0
            var metallic := float(peer.get_u8()) / 255.0
            var vertex_count := peer.get_u16()
            var index_count := peer.get_u16()
            if vertex_count <= 0 or index_count < 3:
                root.free()
                return null
            var minimum := Vector3(peer.get_float(), peer.get_float(), peer.get_float())
            var maximum := Vector3(peer.get_float(), peer.get_float(), peer.get_float())
            var positions := PackedVector3Array()
            positions.resize(vertex_count)
            for vertex_index: int in range(vertex_count):
                positions[vertex_index] = Vector3(
                    lerpf(minimum.x, maximum.x, float(peer.get_u16()) / 65535.0),
                    lerpf(minimum.y, maximum.y, float(peer.get_u16()) / 65535.0),
                    lerpf(minimum.z, maximum.z, float(peer.get_u16()) / 65535.0)
                )
            var indices := PackedInt32Array()
            indices.resize(index_count)
            for index: int in range(index_count):
                indices[index] = peer.get_u16()
                if indices[index] >= vertex_count:
                    root.free()
                    return null
            var material := StandardMaterial3D.new()
            material.albedo_color = color
            material.roughness = roughness
            material.metallic = metallic
            var surface := SurfaceTool.new()
            surface.begin(Mesh.PRIMITIVE_TRIANGLES)
            surface.set_material(material)
            for index: int in indices:
                surface.add_vertex(positions[index])
            surface.generate_normals()
            surface.index()
            surface.commit(array_mesh)
        var mesh_node := MeshInstance3D.new()
        mesh_node.name = node_name
        mesh_node.mesh = array_mesh
        mesh_node.position = translation
        mesh_node.quaternion = rotation
        mesh_node.scale = node_scale
        root.add_child(mesh_node)
        mesh_node.owner = root
    return root

func _collect_wheels(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Node3D:
            var spatial := child as Node3D
            var lowered := spatial.name.to_lower()
            if "wheel" in lowered:
                _wheel_nodes.append(spatial)
                _wheel_base_rotation[spatial.get_instance_id()] = spatial.rotation
                if "front" in lowered:
                    _front_wheels.append(spatial)
        _collect_wheels(child)

func _process(delta: float) -> void:
    if not animate_wheels or _wheel_nodes.is_empty():
        return
    var vehicle := get_parent()
    var forward_speed := 0.0
    if vehicle is CharacterBody3D:
        var body := vehicle as CharacterBody3D
        var forward := -body.global_transform.basis.z
        forward.y = 0.0
        if forward.length_squared() > 0.001:
            forward_speed = body.velocity.dot(forward.normalized())
    elif vehicle is RigidBody3D:
        var rigid := vehicle as RigidBody3D
        var forward := -rigid.global_transform.basis.z
        forward.y = 0.0
        if forward.length_squared() > 0.001:
            forward_speed = rigid.linear_velocity.dot(forward.normalized())
    _spin_angle = fposmod(_spin_angle + forward_speed / maxf(0.05, wheel_radius_m) * delta, TAU)
    var steering := 0.0
    if vehicle != null and vehicle.has_method("get_visual_steering_angle"):
        steering = float(vehicle.call("get_visual_steering_angle"))
    for wheel: Node3D in _wheel_nodes:
        if not is_instance_valid(wheel):
            continue
        var base: Vector3 = _wheel_base_rotation.get(wheel.get_instance_id(), wheel.rotation)
        wheel.rotation = Vector3(base.x + _spin_angle, base.y, base.z)
    for wheel: Node3D in _front_wheels:
        if is_instance_valid(wheel):
            wheel.rotation.y += steering
