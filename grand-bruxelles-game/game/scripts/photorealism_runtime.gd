extends Node

## Renderer-aware visual profile for Grand Bruxelles.
##
## The playable Web build is GL Compatibility, so it must never enable effects
## that Godot only supports in Forward+. The shared profile therefore limits
## itself to tonemapping, restrained glow and existing atmospheric fog. A future
## desktop Forward+ build automatically gains the advanced branch below.

var _bound_scene: Node = null
var _renderer_method := ""
var _advanced_profile_active := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    call_deferred("_apply_to_current_scene")

func _process(_delta: float) -> void:
    var current := get_tree().current_scene
    if current != _bound_scene:
        _apply_to_current_scene()

func _apply_to_current_scene() -> void:
    var current := get_tree().current_scene
    if current == null:
        return
    var world_environment := current.get_node_or_null("WorldEnvironment") as WorldEnvironment
    if world_environment == null or world_environment.environment == null:
        return

    _renderer_method = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "gl_compatibility"))
    _advanced_profile_active = false
    _apply_shared_profile(world_environment.environment)
    if _renderer_method == "forward_plus":
        _apply_forward_plus_profile(world_environment)
        _advanced_profile_active = true
    else:
        # Compatibility/Web and Mobile never receive unsupported camera or
        # screen-space effects. This is deliberate, not a degraded code path.
        world_environment.camera_attributes = null

    _bound_scene = current
    print("PHOTOREALISM_PROFILE_READY: renderer=%s advanced=%s" % [_renderer_method, str(_advanced_profile_active)])

func _apply_shared_profile(environment: Environment) -> void:
    # ACES gives bright sky, glass and car highlights a more camera-like rolloff
    # than the previous Filmic profile without requiring Forward+.
    environment.tonemap_mode = Environment.TONE_MAPPER_ACES
    environment.tonemap_exposure = 1.02
    environment.adjustment_enabled = true
    environment.adjustment_brightness = 1.0
    environment.adjustment_contrast = 1.055
    environment.adjustment_saturation = 0.965

    # Compatibility has a simplified glow implementation. Keep it intentionally
    # weak: this is highlight bleed, not a videogame bloom filter.
    environment.glow_enabled = true
    environment.glow_bloom = 0.035

    # Preserve the authored Brussels overcast fog but reduce the blanket haze so
    # distant façades keep contrast. No new geometry or weather state is invented.
    if environment.fog_enabled:
        environment.fog_density = minf(environment.fog_density, 0.0022)
        environment.fog_sky_affect = minf(environment.fog_sky_affect, 0.58)

    environment.set_meta("grand_bruxelles_visual_profile", "photoreal_web_safe_v1")

func _apply_forward_plus_profile(world_environment: WorldEnvironment) -> void:
    var environment := world_environment.environment
    environment.ssr_enabled = true
    environment.ssr_max_steps = 48
    environment.ssao_enabled = true
    environment.ssao_radius = 0.85
    environment.ssao_intensity = 1.25

    var camera_attributes := CameraAttributesPractical.new()
    camera_attributes.auto_exposure_enabled = true
    camera_attributes.auto_exposure_speed = 0.65
    camera_attributes.auto_exposure_scale = 0.42
    # Very mild distance blur only; gameplay readability stays more important
    # than a cinematic effect.
    camera_attributes.dof_blur_far_enabled = true
    camera_attributes.dof_blur_far_distance = 110.0
    camera_attributes.dof_blur_far_transition = 55.0
    camera_attributes.dof_blur_amount = 0.025
    world_environment.camera_attributes = camera_attributes
    environment.set_meta("grand_bruxelles_visual_profile", "photoreal_forward_plus_v1")

func profile_state_for_test() -> Dictionary:
    return {
        "bound": _bound_scene != null,
        "renderer": _renderer_method,
        "advanced": _advanced_profile_active,
    }
