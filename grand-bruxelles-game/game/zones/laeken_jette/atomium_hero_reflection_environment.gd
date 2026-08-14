extends Node3D

## Deterministic presentation environment for the source-backed stainless Atomium hero.
## The official Atomium evidence resolves a bright stainless-steel skin, but does
## not provide calibrated sky radiance, sun azimuth, exposure or weather. All
## numeric lighting/sky values here are therefore authored presentation values,
## never measured photometry or landmark geometry.

var environment_built := false
var reflection_source_is_sky := false
var authored_non_photometric := true
var sky_energy := 0.82
var ambient_energy := 0.58
var sun_energy := 1.18

var world_environment: WorldEnvironment
var sun: DirectionalLight3D
var sky: Sky
var sky_material: ProceduralSkyMaterial

func build() -> bool:
    if environment_built:
        return true

    sky_material = ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color(0.38, 0.48, 0.62, 1.0)
    sky_material.sky_horizon_color = Color(0.72, 0.76, 0.80, 1.0)
    sky_material.ground_horizon_color = Color(0.48, 0.49, 0.47, 1.0)
    sky_material.ground_bottom_color = Color(0.20, 0.21, 0.20, 1.0)
    sky_material.sky_energy_multiplier = sky_energy
    sky_material.ground_energy_multiplier = 0.56
    sky_material.use_debanding = true

    sky = Sky.new()
    sky.sky_material = sky_material
    sky.radiance_size = Sky.RADIANCE_SIZE_128

    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = ambient_energy
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

    world_environment = WorldEnvironment.new()
    world_environment.name = "AtomiumHeroWorldEnvironment"
    world_environment.environment = env
    add_child(world_environment)

    sun = DirectionalLight3D.new()
    sun.name = "AtomiumHeroSun"
    sun.rotation_degrees = Vector3(-46.0, -28.0, 0.0)
    sun.light_color = Color(1.0, 0.97, 0.92, 1.0)
    sun.light_energy = sun_energy
    sun.shadow_enabled = true
    add_child(sun)

    reflection_source_is_sky = env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY
    environment_built = reflection_source_is_sky
    if environment_built:
        print("ATOMIUM_REFLECTION_ENVIRONMENT_READY: sky_energy=%.2f ambient=%.2f sun=%.2f authored_non_photometric=%s" % [sky_energy, ambient_energy, sun_energy, str(authored_non_photometric)])
    return environment_built
