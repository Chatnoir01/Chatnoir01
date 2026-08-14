extends SceneTree

const AWNING_SCRIPT := preload("res://game/scripts/brussels_historic_terrace_awning.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_HISTORIC_TERRACE_AWNING_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var awning := AWNING_SCRIPT.new()
    root.add_child(awning)
    await process_frame

    if not bool(awning.get("visual_built")):
        _fail("visual did not build")
        return
    if not bool(awning.get("source_confirms_green_metal_structure")):
        _fail("source-backed green metal structure contract missing")
        return
    if bool(awning.get("claims_surveyed_dimensions")):
        _fail("reusable family must not claim surveyed dimensions")
        return
    if bool(awning.get("embeds_source_branding")):
        _fail("reusable family must not embed historic brand lettering")
        return
    if int(awning.get("bay_count")) != 3:
        _fail("expected three readable awning bays")
        return
    if int(awning.get("roof_panel_count")) < 9:
        _fail("awning roof needs enough panel rhythm to read at street scale")
        return
    if int(awning.get("support_count")) < 4:
        _fail("awning support rhythm missing")
        return

    var roof := awning.get_node_or_null("RoofPanels") as Node3D
    var frame := awning.get_node_or_null("GreenMetalFrame") as Node3D
    if roof == null or frame == null:
        _fail("roof/frame groups missing")
        return

    print("BRUSSELS_HISTORIC_TERRACE_AWNING_OK: bays=%d roof_panels=%d supports=%d source_green_metal=true branding=false surveyed_dimensions=false" % [int(awning.get("bay_count")), int(awning.get("roof_panel_count")), int(awning.get("support_count"))])
    quit(0)
