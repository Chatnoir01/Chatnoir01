extends SceneTree

const ZONE_SCRIPT := "res://game/zones/midi/midi_city_machine_zone.gd"
const CATALOG := "res://data/qa/playable_zone_catalog.json"
const LABO_ZONE_ID := "midi_machine_labo"
const CANONICAL_ZONE_ID := "midi"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MIDI_CITY_MACHINE_FACADE_LABO_FAIL: %s" % message)
    quit(1)


func _catalog_zone(zone_id: String) -> Dictionary:
    var file := FileAccess.open(CATALOG, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary:
        return {}
    for raw: Variant in (parsed as Dictionary).get("zones", []):
        if raw is Dictionary and str((raw as Dictionary).get("id", "")) == zone_id:
            return (raw as Dictionary).duplicate(true)
    return {}


func _run() -> void:
    var script := load(ZONE_SCRIPT) as Script
    if script == null:
        _fail("Midi City Machine zone script could not be loaded")
        return
    var lab := script.new() as Node3D
    if lab == null:
        _fail("Midi City Machine LABO could not be instantiated")
        return
    root.add_child(lab)
    for _i: int in range(8):
        await process_frame

    var buildings := lab.get_node_or_null("MidiCityMachineBuildings") as MeshInstance3D
    if buildings == null or buildings.mesh == null:
        _fail("official Midi building mesh missing")
        return
    var stats: Variant = lab.get("last_stats")
    if not stats is Dictionary or int((stats as Dictionary).get("buildings", 0)) <= 0:
        _fail("official Midi building count missing")
        return

    var mesh_before: Mesh = buildings.mesh
    var rid_before := mesh_before.get_rid()
    var aabb_before := mesh_before.get_aabb()
    var transform_before := buildings.transform
    var surface_count_before := mesh_before.get_surface_count()
    var children_before := buildings.get_child_count()

    if not bool(lab.call("facade_enabled")):
        _fail("LABO facade must default to visible for human review")
        return
    var enhanced := buildings.material_override
    if not enhanced is ShaderMaterial:
        _fail("LABO facade did not install a shader material override")
        return
    if str((enhanced as ShaderMaterial).get_meta("material_family", "")) != "midi_city_machine_labo_facade_v1":
        _fail("unexpected LABO facade material family")
        return
    for key: String in ["geometry_changed", "semantic_windows_claimed", "semantic_doors_claimed", "building_material_identity_claimed", "jouable_authorized", "promotion_performed"]:
        if bool((enhanced as ShaderMaterial).get_meta(key, true)):
            _fail("unsafe facade claim became true: %s" % key)
            return

    lab.call("set_facade_enabled", false)
    if buildings.material_override != null:
        _fail("A/B baseline did not restore the original surface material")
        return
    lab.call("set_facade_enabled", true)
    if buildings.material_override != enhanced:
        _fail("A/B enhanced state did not restore the exact LABO material")
        return

    if buildings.mesh != mesh_before or buildings.mesh.get_rid() != rid_before:
        _fail("facade A/B replaced the UrbIS-derived mesh")
        return
    if buildings.mesh.get_aabb() != aabb_before or buildings.transform != transform_before:
        _fail("facade A/B changed building geometry bounds or transform")
        return
    if buildings.mesh.get_surface_count() != surface_count_before or buildings.get_child_count() != children_before:
        _fail("facade A/B changed surfaces or collision children")
        return

    var contract: Variant = lab.call("facade_contract")
    if not contract is Dictionary:
        _fail("facade contract missing")
        return
    var c := contract as Dictionary
    if str(c.get("scope", "")) != LABO_ZONE_ID or not bool(c.get("ab_toggle", false)):
        _fail("facade contract scope/A-B flag invalid")
        return
    for key: String in ["geometry_changed", "semantic_windows_claimed", "semantic_doors_claimed", "material_identity_claimed", "jouable_authorized", "promotion_performed"]:
        if bool(c.get(key, true)):
            _fail("unsafe runtime contract claim became true: %s" % key)
            return

    var canonical := _catalog_zone(CANONICAL_ZONE_ID)
    var review := _catalog_zone(LABO_ZONE_ID)
    if str(canonical.get("quality", "")) != "JOUABLE" or str(canonical.get("mode", "")) != "fast_travel":
        _fail("canonical Midi changed")
        return
    if str(review.get("quality", "")) != "LABO" or str(review.get("review_alias_of", "")) != CANONICAL_ZONE_ID:
        _fail("Midi City Machine review alias contract changed")
        return

    print("MIDI_CITY_MACHINE_FACADE_LABO_OK family=%s ab=true geometry_changed=false semantics_claimed=false material_identity_claimed=false promotion=false jouable=false" % str(lab.call("facade_material_family")))
    lab.queue_free()
    await process_frame
    quit(0)
