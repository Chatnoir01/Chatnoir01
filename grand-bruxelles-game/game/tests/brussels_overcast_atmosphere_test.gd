extends SceneTree

const ATMOSPHERE_PATH := "res://game/scripts/brussels_overcast_atmosphere.gd"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OVERCAST_ATMOSPHERE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not ResourceLoader.exists(ATMOSPHERE_PATH):
        _fail("shared Brussels overcast runtime is missing")
        return
    var script: Script = load(ATMOSPHERE_PATH)
    var atmosphere: Node = script.new()
    root.add_child(atmosphere)
    await process_frame

    if not bool(atmosphere.get("source_backed_profile")):
        _fail("source-backed climate profile flag missing")
        return
    if str(atmosphere.get("profile_id")) != "brussels_uccle_overcast_authored_v1":
        _fail("profile identity drifted")
        return
    if not bool(atmosphere.get("authored_render_values")):
        _fail("authored render-value disclaimer missing")
        return
    if float(atmosphere.get("target_sun_energy")) >= 0.75:
        _fail("overcast sun energy is not materially softer than production clear daylight")
        return
    if float(atmosphere.get("target_ambient_energy")) <= 0.72:
        _fail("overcast ambient fill should remain broad enough to preserve facade readability")
        return
    if float(atmosphere.get("target_fog_density")) < 0.0028 or float(atmosphere.get("target_fog_density")) > 0.0055:
        _fail("fog target escaped conservative urban visibility range")
        return

    print("BRUSSELS_OVERCAST_ATMOSPHERE_OK profile=%s" % atmosphere.get("profile_id"))
    quit(0)
