extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OVERCAST_ATMOSPHERE_FAIL: %s" % message)
    quit(1)

func _close(a: float, b: float, epsilon: float = 0.001) -> bool:
    return absf(a - b) <= epsilon

func _run() -> void:
    var atmosphere := root.get_node_or_null("BrusselsAtmosphere")
    if atmosphere == null:
        _fail("BrusselsAtmosphere autoload missing")
        return
    if not atmosphere.has_method("set_presentation_enabled") or not atmosphere.has_method("source_basis"):
        _fail("atmosphere runtime contract incomplete")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(8):
        await process_frame

    var world_environment := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
    var sun := main.get_node_or_null("Sun") as DirectionalLight3D
    if world_environment == null or world_environment.environment == null or sun == null:
        _fail("production environment nodes missing")
        return

    var environment := world_environment.environment
    var sky := environment.sky
    var sky_material := sky.sky_material as ProceduralSkyMaterial if sky != null else null
    if sky_material == null:
        _fail("production procedural sky missing")
        return

    atmosphere.call("set_presentation_enabled", true)
    await process_frame

    if not _close(sun.light_energy, 0.42, 0.01):
        _fail("overcast sun energy not applied")
        return
    if not _close(environment.fog_density, 0.0042, 0.0002):
        _fail("overcast fog density not applied")
        return
    if not _close(environment.adjustment_saturation, 0.84, 0.01):
        _fail("overcast saturation not applied")
        return
    if sky_material.sky_top_color.b <= sky_material.sky_top_color.r:
        _fail("overcast sky must retain a cool neutral cast")
        return

    var source: Dictionary = atmosphere.call("source_basis")
    if str(source.get("authority", "")) != "IRM/KMI":
        _fail("official Belgian climate authority provenance missing")
        return
    if str(source.get("reference_period", "")) != "1991-2020":
        _fail("climate-normal reference period missing")
        return

    atmosphere.call("set_presentation_enabled", false)
    await process_frame
    if _close(sun.light_energy, 0.42, 0.01):
        _fail("presentation toggle does not restore production baseline")
        return

    atmosphere.call("set_presentation_enabled", true)
    await process_frame
    print("BRUSSELS_OVERCAST_ATMOSPHERE_OK: reusable global overcast preset source=IRM/KMI reference=1991-2020")
    quit(0)
