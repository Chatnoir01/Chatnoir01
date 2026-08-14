extends SceneTree

const SHOPFRONT_SCRIPT := preload("res://game/scripts/brussels_historic_shopfront.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_HISTORIC_SHOPFRONT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var shopfront := SHOPFRONT_SCRIPT.new()
    root.add_child(shopfront)
    await process_frame

    if not bool(shopfront.get("visual_built")):
        _fail("visual did not build")
        return
    if int(shopfront.get("glazed_bay_count")) != 3:
        _fail("expected three readable glazed bays")
        return
    if int(shopfront.get("frame_pillar_count")) != 4:
        _fail("expected four vertical frame/pillar elements")
        return
    if not bool(shopfront.get("has_marble_base")):
        _fail("source-backed marble base vocabulary missing")
        return
    if not bool(shopfront.get("has_wood_frame")):
        _fail("source-backed wood frame vocabulary missing")
        return
    if not bool(shopfront.get("has_glazing")):
        _fail("commercial glazing vocabulary missing")
        return
    if not bool(shopfront.get("has_shallow_awning")):
        _fail("Rue de la Bourse awning vocabulary missing")
        return
    if bool(shopfront.get("embeds_business_branding")):
        _fail("reusable family must not embed business branding")
        return
    if bool(shopfront.get("claims_surveyed_dimensions")):
        _fail("authored dimensions must not be presented as surveyed")
        return
    if bool(shopfront.get("claims_surveyed_mount")):
        _fail("reusable family must not claim permanent surveyed mounting")
        return

    var glass := shopfront.get_node_or_null("Glazing/GlassBay_0") as MeshInstance3D
    if glass == null or not glass.mesh is BoxMesh:
        _fail("first glazing bay missing")
        return
    var glass_material := (glass.mesh as BoxMesh).material as StandardMaterial3D
    if glass_material == null:
        _fail("glazing material missing")
        return
    if glass_material.metallic > 0.05 or glass_material.roughness > 0.25:
        _fail("glazing no longer reads as authored glass")
        return

    print("BRUSSELS_HISTORIC_SHOPFRONT_OK: bays=3 pillars=4 wood=true marble=true awning=true branded=false surveyed=false")
    quit(0)
