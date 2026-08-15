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
    for _frame: int in range(3):
        await process_frame

    var city_builder := scene.get_node_or_null("BrusselsOSM")
    if city_builder == null:
        _fail("production OSM city builder missing")
        return
    if not city_builder.has_method("facade_articulation_counts_near"):
        _fail("production context facades expose no articulation diagnostics")
        return

    var counts: Dictionary = city_builder.call("facade_articulation_counts_near", BOURSE_ANCHOR, DETAIL_RADIUS_M)
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

    var details := scene.get_node_or_null("BrusselsOSM/GeneratedFacadeDetails")
    if details == null:
        _fail("production facade details root missing")
        return
    for required_name: String in ["CorridorFacadeCornices", "CorridorFacadeLintels", "CorridorFacadeSills", "CorridorFacadeEntries", "CorridorShopHeaders"]:
        if details.get_node_or_null(required_name) == null:
            _fail("missing visible production detail layer %s" % required_name)
            return

    print("BOURSE_FACADE_ARTICULATION_OK: cornices=%d lintels=%d sills=%d entries=%d shop_headers=%d" % [cornices, lintels, sills, entries, shop_headers])
    scene.queue_free()
    quit(0)
