extends Node3D

## Deterministic presentation environment for the source-backed stainless Atomium hero.
## The official Atomium evidence resolves a bright stainless-steel skin, but does
## not provide calibrated sky radiance, sun azimuth, exposure or weather. All
## numeric lighting/sky values here are therefore authored presentation values,
## never measured photometry or landmark geometry.
##
## Important acceptance constraint: keep the already-validated hero ambient/sun
## presentation and lower-background readability, then add the procedural sky only
## as the stainless reflection/upper-background source. This avoids turning an
## environment improvement into a terrain/background regression.

var environment_built := false
var reflection_source_is_sky := false
var ambient_preserves_baseline := false
var horizon_preserves_baseline := false
var authored_non_photometric := true
var sky_energy := 0.82
var ambient_energy := 0.62
var sun_energy := 1.25

var world_environment: WorldEnvironment
var sun: DirectionalLight3D
var sky: Sky
var sky_material: ProceduralSkyMaterial

func build() -> bool:
    if environment_built:
        return true

    var baseline_background := Color(0.62, 0.69, 0.78, 1.0)
    sky_material = ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color(0.38, 0.48, 0.62, 1.0)
    # Match both sides of the horizon to the accepted legacy background and use
    # the same energy multiplier for both hemispheres. The result is a continuous
    # deterministic horizon while still giving the stainless skin a sky radiance
    # field to reflect.
    sky_material.sky_horizon_color = baseline_background
    sky_material.ground_horizon_color = baseline_background
    sky_material.ground_bottom_color = baseline_background
    sky_material.sky_energy_multiplier = sky_energy
    sky_material.ground_energy_multiplier = sky_energy
    sky_material.use_debanding = true

    sky = Sky.new()
    sky.sky_material = sky_material
    sky.radiance_size = Sky.RADIANCE_SIZE_128

    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    # Preserve the accepted pre-lot ambient presentation exactly. The sky is a
    # reflection/background source, not a claim about measured ambient radiance.
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.88, 0.90, 0.93, 1.0)
    env.ambient_light_energy = ambient_energy
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

    world_environment = WorldEnvironment.new()
    world_environment.name = "AtomiumHeroWorldEnvironment"
    world_environment.environment = env
    add_child(world_environment)

    sun = DirectionalLight3D.new()
    sun.name = "AtomiumHeroSun"
    sun.rotation_degrees = Vector3(-46.0, -28.0, 0.0)
    sun.light_energy = sun_energy
    sun.shadow_enabled = true
    add_child(sun)

    reflection_source_is_sky = env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY
    ambient_preserves_baseline = env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR and absf(env.ambient_light_energy - 0.62) <= 0.001
    horizon_preserves_baseline = sky_material.sky_horizon_color.is_equal_approx(baseline_background) and sky_material.ground_horizon_color.is_equal_approx(baseline_background) and sky_material.ground_bottom_color.is_equal_approx(baseline_background) and absf(sky_material.ground_energy_multiplier - sky_material.sky_energy_multiplier) <= 0.001
    environment_built = reflection_source_is_sky and ambient_preserves_baseline and horizon_preserves_baseline
    if environment_built:
        print("ATOMIUM_REFLECTION_ENVIRONMENT_READY: sky_energy=%.2f ambient=%.2f sun=%.2f sky_reflection=%s baseline_ambient=%s baseline_horizon=%s authored_non_photometric=%s" % [sky_energy, ambient_energy, sun_energy, str(reflection_source_is_sky), str(ambient_preserves_baseline), str(horizon_preserves_baseline), str(authored_non_photometric)])
    return environment_built
