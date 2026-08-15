extends Node

const CONTRACT_SCHEMA := "grand-bruxelles-shared-neutral-daylight-v1"

const SKY_TOP := Color(0.24, 0.34, 0.47, 1.0)
const SKY_HORIZON := Color(0.74, 0.77, 0.78, 1.0)
const GROUND_BOTTOM := Color(0.095, 0.09, 0.085, 1.0)
const GROUND_HORIZON := Color(0.42, 0.41, 0.39, 1.0)
const BACKGROUND_ENERGY := 0.90
const AMBIENT_COLOR := Color(0.76, 0.79, 0.82, 1.0)
const AMBIENT_ENERGY := 0.70
const TONEMAP_EXPOSURE := 1.06
const ADJUSTMENT_BRIGHTNESS := 1.012
const ADJUSTMENT_CONTRAST := 1.065
const ADJUSTMENT_SATURATION := 0.95
const FOG_COLOR := Color(0.74, 0.76, 0.77, 1.0)
const FOG_ENERGY := 0.56
const FOG_DENSITY := 0.0023
const FOG_SKY_AFFECT := 0.58
const SUN_ROTATION := Vector3(-44.0, -30.0, 0.0)
const SUN_COLOR := Color(1.0, 0.95, 0.86, 1.0)
const SUN_ENERGY := 1.08

var _applied_world_ids: Dictionary = {}

func _ready() -> void:
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_scan_existing")

func _on_node_added(node: Node) -> void:
    if node is WorldEnvironment:
        call_deferred("_try_apply_world", node)

func _scan_existing() -> void:
    var root_node := get_tree().root
    if root_node == null:
        return
    var candidates: Array[Node] = root_node.find_children("WorldEnvironment", "WorldEnvironment", true, false)
    for candidate: Node in candidates:
        _try_apply_world(candidate)

func _is_main_world(world: WorldEnvironment) -> bool:
    var parent := world.get_parent()
    return parent != null and parent.name == &"Main"

func _try_apply_world(node: Node) -> void:
    if not (node is WorldEnvironment):
        return
    var world := node as WorldEnvironment
    if not _is_main_world(world):
        return
    var instance_id := world.get_instance_id()
    if _applied_world_ids.has(instance_id):
        return
    var main_root := world.get_parent()
    var sun := main_root.get_node_or_null("Sun") as DirectionalLight3D
    if apply_to(world, sun):
        _applied_world_ids[instance_id] = true
        print("Grand Bruxelles shared environment: neutral daylight active across production corridor")

func apply_to(world: WorldEnvironment, sun: DirectionalLight3D) -> bool:
    if world == null or world.environment == null:
        return false
    var environment := world.environment
    environment.background_energy_multiplier = BACKGROUND_ENERGY
    environment.ambient_light_color = AMBIENT_COLOR
    environment.ambient_light_energy = AMBIENT_ENERGY
    environment.tonemap_exposure = TONEMAP_EXPOSURE
    environment.adjustment_enabled = true
    environment.adjustment_brightness = ADJUSTMENT_BRIGHTNESS
    environment.adjustment_contrast = ADJUSTMENT_CONTRAST
    environment.adjustment_saturation = ADJUSTMENT_SATURATION
    environment.fog_enabled = true
    environment.fog_light_color = FOG_COLOR
    environment.fog_light_energy = FOG_ENERGY
    environment.fog_density = FOG_DENSITY
    environment.fog_sky_affect = FOG_SKY_AFFECT

    var sky := environment.sky
    if sky != null and sky.sky_material is ProceduralSkyMaterial:
        var sky_material := sky.sky_material as ProceduralSkyMaterial
        sky_material.sky_top_color = SKY_TOP
        sky_material.sky_horizon_color = SKY_HORIZON
        sky_material.ground_bottom_color = GROUND_BOTTOM
        sky_material.ground_horizon_color = GROUND_HORIZON
        sky_material.sun_angle_max = 14.0
        sky_material.sun_curve = 0.10

    if sun != null:
        sun.rotation_degrees = SUN_ROTATION
        sun.light_color = SUN_COLOR
        sun.light_energy = SUN_ENERGY
        sun.shadow_enabled = true
        sun.directional_shadow_max_distance = 320.0
    return true

func contract() -> Dictionary:
    return {
        "schema": CONTRACT_SCHEMA,
        "scope": ["Midi", "Anneessens", "Bourse", "Grand-Place"],
        "external_assets": 0,
        "photometric_measurement": false,
        "weather_timestamp_claim": false,
        "runtime_node": "Main/WorldEnvironment + Main/Sun",
    }
