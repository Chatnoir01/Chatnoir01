extends SceneTree

const BOURSE_ANCHOR := Vector2(81.54, -664.58)
const DETAIL_RADIUS_M := 180.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_FACADE_ARTICULATION_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    for _frame: int in range(5):
        await process_frame

    var city_builder := scene.get_node_or_null("BrusselsOSM")
    if city_builder == null:
        _fail("production OSM city builder missing")
        return
    var articulation := city_builder.get_node_or_null("ContextFacadeArticulation")
    if articulation == null:
        _fail("production context facades have no reusable articulation runtime")
        return
    if not articulation.has_method("facade_articulation_counts_near"):
        _fail("facade articulation runtime exposes no placement diagnostics")
        return

    var counts: Dictionary = articulation.call("facade_articulation_counts_near", BOURSE_ANCHOR, DETAIL_RADIUS_M)
    var cornices := int(counts.get("cornices", 0))
    var lintels := int(counts.get("lintels", 0))
    var sills := int(counts.get("sills", 0))
    var entries := int(counts.get("entries", 0))
    var shop_headers := int(counts.get("shop_headers", 0))

    if cornices < 12:
        _fail("Bourse context remains flat: expected >=12 source-footprint cornices, got %d" % cornices)
        return
    if lintels < 70 or sills < 70:
        _fail("Bourse context needs repeated window depth cues; lintels=%d sills=%d" % [lintels, sills])
        return
    if entries < 8:
        _fail("Bourse context lacks player-height entrance articulation; got %d" % entries)
        return
    if shop_headers < 8:
        _fail("Bourse context lacks player-height commercial frontage headers; got %d" % shop_headers)
        return

    for required_name: String in ["CorridorFacadeCornices", "CorridorFacadeLintels", "CorridorFacadeSills", "CorridorFacadeEntries", "CorridorShopHeaders"]:
        if articulation.get_node_or_null(required_name) == null:
            _fail("missing visible production detail layer %s" % required_name)
            return

    if not articulation.has_method("truth_contract"):
        _fail("art direction/source-geometry separation contract missing")
        return
    var contract: Dictionary = articulation.call("truth_contract")
    if bool(contract.get("moves_source_geometry", true)):
        _fail("facade art direction must not move source geometry")
        return
    if int(contract.get("external_assets", -1)) != 0:
        _fail("this procedural lot must not introduce untracked external assets")
        return

    print("BOURSE_FACADE_ARTICULATION_OK: cornices=%d lintels=%d sills=%d entries=%d shop_headers=%d" % [cornices, lintels, sills, entries, shop_headers])
    scene.queue_free()
    quit(0)
