extends Node

# Shared authored Brussels overcast atmosphere preset.
# Climate context is sourced from IRM/KMI Uccle normals; all engine color,
# exposure, fog and light-energy values are authored presentation choices.

const profile_id := "brussels_uccle_overcast_authored_v1"
const source_backed_profile := true
const authored_render_values := true
const target_sun_energy := 0.54
const target_ambient_energy := 0.80
const target_fog_density := 0.0036

var profile_enabled := true
var _captured := false
var _original := {}

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _apply_when_ready() -> void:
    for _frame: int in range(8):
        await get_tree().process_frame
        if get_tree().current_scene != null:
            break
    set_profile_enabled(profile_enabled)

func set_profile_enabled(enabled: bool) -> bool:
    profile_enabled = enabled
    var scene := get_tree().current_scene
    if scene == null:
        return false
    var world_environment := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
    var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
    if world_environment == null or world_environment.environment == null or sun == null:
        return false
    var env := world_environment.environment
    var sky := env.sky
    var sky_material := sky.sky_material as ProceduralSkyMaterial if sky != null else null
    if sky_material == null:
        return false
    if not _captured:
        _original = {
            "background_energy": env.background_energy_multiplier,
            "ambient_color": env.ambient_light_color,
            "ambient_energy": env.ambient_light_energy,
            "exposure": env.tonemap_exposure,
            "brightness": env.adjustment_brightness,
            "contrast": env.adjustment_contrast,
            "saturation": env.adjustment_saturation,
            "fog_color": env.fog_light_color,
            "fog_energy": env.fog_light_energy,
            "fog_density": env.fog_density,
            "fog_sky_affect": env.fog_sky_affect,
            "sky_top": sky_material.sky_top_color,
            "sky_horizon": sky_material.sky_horizon_color,
            "ground_horizon": sky_material.ground_horizon_color,
            "sun_color": sun.light_color,
            "sun_energy": sun.light_energy,
        }
        _captured = true
    if enabled:
        _apply_overcast(env, sky_material, sun)
    else:
        _restore(env, sky_material, sun)
    set_meta("profile_id", profile_id)
    set_meta("climate_basis", "IRM/KMI Uccle 1991-2020 normals and cloudiness context")
    set_meta("authored_render_values", true)
    return true

func _apply_overcast(env: Environment, sky_material: ProceduralSkyMaterial, sun: DirectionalLight3D) -> void:
    env.background_energy_multiplier = 0.78
    env.ambient_light_color = Color(0.76, 0.79, 0.83, 1.0)
    env.ambient_light_energy = target_ambient_energy
    env.tonemap_exposure = 1.00
    env.adjustment_brightness = 1.00
    env.adjustment_contrast = 1.035
    env.adjustment_saturation = 0.89
    env.fog_light_color = Color(0.72, 0.75, 0.78, 1.0)
    env.fog_light_energy = 0.60
    env.fog_density = target_fog_density
    env.fog_sky_affect = 0.78
    sky_material.sky_top_color = Color(0.31, 0.36, 0.42, 1.0)
    sky_material.sky_horizon_color = Color(0.65, 0.67, 0.69, 1.0)
    sky_material.ground_horizon_color = Color(0.36, 0.37, 0.37, 1.0)
    sun.light_color = Color(0.88, 0.92, 0.98, 1.0)
    sun.light_energy = target_sun_energy

func _restore(env: Environment, sky_material: ProceduralSkyMaterial, sun: DirectionalLight3D) -> void:
    if not _captured:
        return
    env.background_energy_multiplier = float(_original["background_energy"])
    env.ambient_light_color = _original["ambient_color"]
    env.ambient_light_energy = float(_original["ambient_energy"])
    env.tonemap_exposure = float(_original["exposure"])
    env.adjustment_brightness = float(_original["brightness"])
    env.adjustment_contrast = float(_original["contrast"])
    env.adjustment_saturation = float(_original["saturation"])
    env.fog_light_color = _original["fog_color"]
    env.fog_light_energy = float(_original["fog_energy"])
    env.fog_density = float(_original["fog_density"])
    env.fog_sky_affect = float(_original["fog_sky_affect"])
    sky_material.sky_top_color = _original["sky_top"]
    sky_material.sky_horizon_color = _original["sky_horizon"]
    sky_material.ground_horizon_color = _original["ground_horizon"]
    sun.light_color = _original["sun_color"]
    sun.light_energy = float(_original["sun_energy"])
