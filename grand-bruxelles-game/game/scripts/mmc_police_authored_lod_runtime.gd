extends Node

const PAYLOAD := preload("res://game/scripts/authored_geometry_payload.gd")
const HOLDER_NAME := "BelgianPoliceFleetVisual"
const BODY_CHILDREN: Array[String] = ["LowerBody", "Hood", "Trunk", "Cabin", "FrontBumper", "RearBumper"]
const CONFIGS: Array[Dictionary] = [
    {
        "vehicle": "ParkedCar_00",
        "profile": "brussels_capitale_sedan",
        "payload_dir": "res://assets/vehicles/mmc_generic_sedan/authored_lod",
        "parts": 5,
        "raw_bytes": 26982,
        "triangles": 2443,
        "vertices": 1339,
        "target_length": 4.65,
        "payload_sha256": "6e37ef3f80e3b164e1eea538544c104f4daaaed5d1b056638de6b48fc3fde695",
    },
    {
        "vehicle": "AmbientTraffic_03",
        "profile": "brussels_rapid_response_coupe",
        "payload_dir": "res://assets/vehicles/mmc_generic_sport_coupe/authored_lod",
        "parts": 5,
        "raw_bytes": 24145,
        "triangles": 2178,
        "vertices": 1209,
        "target_length": 4.48,
        "payload_sha256": "2f93859aaa55f48590ead123224d90e9628e7952b5e0a41e37ae94ea59fad3c9",
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
        print("MMC_POLICE_AUTHORED_LOD_READY: sedan_triangles=2443 coupe_triangles=2178 renderer_only=true")
    elif _attempts > 600:
        set_process(false)
        push_warning("MMC police authored LOD overlay: police holders were not ready after 600 frames")

func config_count() -> int:
    return CONFIGS.size()

func config_at(index: int) -> Dictionary:
    if index < 0 or index >= CONFIGS.size():
        return {}
    return CONFIGS[index].duplicate(true)

func get_contract() -> Dictionary:
    return {
        "source_derived_lod_count": 2,
        "renderer_only": true,
        "changes_physics": false,
        "changes_collision": false,
        "changes_traffic_motion": false,
        "changes_geography": false,
        "exact_source_glb_committed": false,
    }

func install_on_holder(holder: Node3D, config: Dictionary) -> bool:
    if holder == null:
        return false
    if str(holder.get_meta("police_profile_id", "")) != str(config.get("profile", "")):
        return false
    var existing := holder.get_node_or_null(NodePath("AuthoredSourceDerivedLOD")) as Node3D
    if existing != null:
        existing.visible = true
        return true
    var authored := PAYLOAD.build_from_parts(
        str(config.get("payload_dir", "")),
        int(config.get("parts", 0)),
        int(config.get("raw_bytes", 0))
    )
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
    authored.set_meta("expected_triangles", int(config.get("triangles", 0)))
    authored.set_meta("expected_vertices", int(config.get("vertices", 0)))
    authored.set_meta("uniform_scale", scale_value)
    authored.set_meta("renderer_only", true)
    authored.set_meta("production_authorized_exact_third_party_geometry", false)
    holder.add_child(authored)
    if int(authored.get_meta("source_triangles", -1)) != int(config.get("triangles", -2)):
        authored.queue_free()
        return false
    if int(authored.get_meta("source_vertices", -1)) != int(config.get("vertices", -2)):
        authored.queue_free()
        return false
    for child_name: String in BODY_CHILDREN:
        var child := holder.get_node_or_null(NodePath(child_name)) as Node3D
        if child != null:
            child.visible = false
    holder.set_meta("authored_mount", "source_derived_webgl_lod")
    holder.set_meta("authored_source_derived_lod", true)
    holder.set_meta("authored_payload_sha256", str(config.get("payload_sha256", "")))
    holder.set_meta("authored_triangles", int(config.get("triangles", 0)))
    holder.set_meta("production_authorized_exact_third_party_geometry", false)
    return true

func _try_install() -> bool:
    var scene: Node = get_tree().current_scene
    if scene == null:
        return false
    var midi := scene.get_node_or_null(NodePath("MidiUrbanLife")) as Node3D
    if midi == null:
        return false
    for config: Dictionary in CONFIGS:
        var vehicle := midi.get_node_or_null(NodePath(str(config.get("vehicle", "")))) as Node3D
        if vehicle == null:
            return false
        var holder := vehicle.get_node_or_null(NodePath(HOLDER_NAME)) as Node3D
        if holder == null or not install_on_holder(holder, config):
            return false
    return true
