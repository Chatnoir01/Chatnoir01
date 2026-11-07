extends SceneTree

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_ground_network_official_material.gd")
const COVERAGE_REGISTRY := preload("res://game/scripts/brussels_ground_network_coverage.gd")
const ROAD_RUNTIME := preload("res://game/scripts/brussels_osm_road_surface_runtime.gd")
const SIDEWALK_RUNTIME := preload("res://game/scripts/brussels_osm_sidewalk_surface_runtime.gd")
const RAIL_RUNTIME := preload("res://game/scripts/brussels_osm_rail_surface_runtime.gd")
const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"
const EXPECTED_OFFICIAL_ZONE_IDS := ["anneessens", "atomium", "bourse", "grand_place", "ixelles", "jette", "midi"]
const EXPECTED_CANONICAL_ZONE_IDS := ["anneessens", "atomium", "bourse", "central", "grand_place", "ixelles", "jette", "midi"]

func _init() -> void:
    if not _prove_catalog_coverage():
        return
    if not _prove_material_contract():
        return
    if not _prove_runtime_bindings():
        return
    print("BRUSSELS_GROUND_NETWORK_OFFICIAL_COVERAGE_OK: canonical_zones=8 official_covered=7 central=review_only_no_official_ground_claim review_aliases=1 layers=3 ixelles=road+sidewalk jette=street_surface+tram gaps=explicit geometry_changed=false")
    quit(0)

func _prove_catalog_coverage() -> bool:
    if not FileAccess.file_exists(CATALOG_PATH):
        return _fail("playable zone catalog missing")
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
    if not parsed is Dictionary:
        return _fail("playable zone catalog is not an object")
    var document := parsed as Dictionary
    if str(document.get("schema", "")) != "grand-bruxelles-playable-zone-catalog-v2":
        return _fail("playable zone catalog is not v2")
    var raw_zones: Variant = document.get("zones", [])
    if not raw_zones is Array:
        return _fail("catalog zones are not an array")
    var canonical_ids: Array[String] = []
    var review_aliases: Dictionary = {}
    var alias_rows: Dictionary = {}
    var central_row: Dictionary = {}
    for raw_zone: Variant in raw_zones as Array:
        if not raw_zone is Dictionary:
            return _fail("catalog zone row is not an object")
        var zone := raw_zone as Dictionary
        var zone_id := str(zone.get("id", ""))
        var alias_of := str(zone.get("review_alias_of", "")).strip_edges()
        if zone_id.is_empty():
            return _fail("catalog zone id is empty")
        if alias_of.is_empty():
            canonical_ids.append(zone_id)
            if zone_id == "central":
                central_row = zone
        else:
            review_aliases[zone_id] = alias_of
            alias_rows[zone_id] = zone
    canonical_ids.sort()
    if canonical_ids != EXPECTED_CANONICAL_ZONE_IDS:
        return _fail("unexpected canonical catalog zone ids: %s" % str(canonical_ids))
    if central_row.is_empty():
        return _fail("Central canonical review row missing")
    if str(central_row.get("quality", "")) != "LABO_BRUT" or str(central_row.get("mode", "")) != "script_zone":
        return _fail("Central must remain LABO_BRUT script_zone while official ground coverage is missing")
    if str(central_row.get("script", "")) != "res://game/zones/central/central_station_context_labo.gd":
        return _fail("Central contextual review runtime contract drifted")
    if review_aliases.size() != 1 or str(review_aliases.get("midi_machine_labo", "")) != "midi":
        return _fail("unexpected ground-network review aliases: %s" % str(review_aliases))
    var midi_review: Variant = alias_rows.get("midi_machine_labo", {})
    if not midi_review is Dictionary or str((midi_review as Dictionary).get("quality", "")) != "LABO":
        return _fail("Midi City Machine review alias must stay LABO")
    var registry_ids: Array[String] = COVERAGE_REGISTRY.zone_ids()
    if registry_ids != EXPECTED_OFFICIAL_ZONE_IDS:
        return _fail("official coverage registry changed unexpectedly: %s" % str(registry_ids))
    if "central" in registry_ids:
        return _fail("Central must not claim official ground coverage before regional source data is mounted")
    if "midi_machine_labo" in registry_ids:
        return _fail("review alias must not become an independent ground-network owner")
    for zone_id: String in EXPECTED_OFFICIAL_ZONE_IDS:
        for layer_id: String in COVERAGE_REGISTRY.LAYERS:
            var entry: Dictionary = COVERAGE_REGISTRY.layer(zone_id, layer_id)
            if entry.is_empty():
                return _fail("coverage entry missing: %s/%s" % [zone_id, layer_id])
            if str(entry.get("provider", "")).is_empty():
                return _fail("coverage provider missing: %s/%s" % [zone_id, layer_id])
            if str(entry.get("status", "")).is_empty():
                return _fail("coverage status missing: %s/%s" % [zone_id, layer_id])
    if str(COVERAGE_REGISTRY.layer("atomium", "roads").get("status", "")) != "data_gap_current_main":
        return _fail("Atomium road source gap must remain explicit")
    if str(COVERAGE_REGISTRY.layer("ixelles", "tram_rails").get("status", "")) != "data_gap_current_main":
        return _fail("Ixelles tram source gap must remain explicit")
    if str(COVERAGE_REGISTRY.layer("jette", "sidewalks").get("status", "")) != "data_gap_typed_semantics":
        return _fail("Jette typed-sidewalk gap must remain explicit")
    return true

func _prove_material_contract() -> bool:
    for layer_id: String in ["road", "sidewalk", "street_surface", "tram_rail"]:
        var material: StandardMaterial3D = MATERIAL_FACTORY.create_material(layer_id)
        if str(material.get_meta("material_family", "")) != MATERIAL_FACTORY.MATERIAL_FAMILY:
            return _fail("official material family mismatch: %s" % layer_id)
        if str(material.get_meta("provider", "")) != MATERIAL_FACTORY.PROVIDER_URBIS:
            return _fail("official provider mismatch: %s" % layer_id)
        if bool(material.get_meta("surface_composition_claimed", true)):
            return _fail("official material fabricated a surface-composition claim: %s" % layer_id)
        if bool(material.get_meta("exact_rgb_is_photometric_measurement", true)):
            return _fail("official material fabricated a photometric RGB claim: %s" % layer_id)
        if bool(material.get_meta("license_claimed_by_presentation_runtime", true)):
            return _fail("official presentation runtime fabricated a license claim: %s" % layer_id)
        if bool(material.get_meta("geometry_changed", true)):
            return _fail("official material claims geometry mutation: %s" % layer_id)
    return true

func _prove_runtime_bindings() -> bool:
    var ixelles_root := Node3D.new()
    ixelles_root.name = "OfficialIxellesStreetSurfaces"
    var ixelles_road := MeshInstance3D.new()
    ixelles_road.name = "StreetSurfaces_S"
    ixelles_road.transform = Transform3D(Basis.IDENTITY, Vector3(11.0, 2.0, -7.0))
    ixelles_root.add_child(ixelles_road)
    var ixelles_sidewalk := MeshInstance3D.new()
    ixelles_sidewalk.name = "StreetSurfaces_SW"
    ixelles_sidewalk.transform = Transform3D(Basis.IDENTITY, Vector3(-3.0, 0.5, 4.0))
    ixelles_root.add_child(ixelles_sidewalk)
    var road_transform := ixelles_road.transform
    var sidewalk_transform := ixelles_sidewalk.transform

    var road_runtime := ROAD_RUNTIME.new()
    road_runtime.call("_register_official_surface", ixelles_road)
    if road_runtime.official_applied_road_count() != 1:
        ixelles_root.free(); road_runtime.free(); return _fail("Ixelles official road was not registered exactly once")
    if ixelles_road.material_override == null:
        ixelles_root.free(); road_runtime.free(); return _fail("Ixelles official road did not receive presentation material")
    if str(ixelles_road.get_meta("ground_network_provider", "")) != "UrbIS":
        ixelles_root.free(); road_runtime.free(); return _fail("Ixelles official road provider metadata mismatch")
    if not ixelles_road.transform.is_equal_approx(road_transform):
        ixelles_root.free(); road_runtime.free(); return _fail("Ixelles official road transform changed")

    var sidewalk_runtime := SIDEWALK_RUNTIME.new()
    sidewalk_runtime.call("_register_official_sidewalk", ixelles_sidewalk)
    if sidewalk_runtime.official_applied_sidewalk_count() != 1:
        ixelles_root.free(); road_runtime.free(); sidewalk_runtime.free(); return _fail("Ixelles official sidewalk was not registered exactly once")
    if ixelles_sidewalk.material_override == null:
        ixelles_root.free(); road_runtime.free(); sidewalk_runtime.free(); return _fail("Ixelles official sidewalk did not receive presentation material")
    if not ixelles_sidewalk.transform.is_equal_approx(sidewalk_transform):
        ixelles_root.free(); road_runtime.free(); sidewalk_runtime.free(); return _fail("Ixelles official sidewalk transform changed")

    var jette_street := MeshInstance3D.new()
    jette_street.name = "JetteOfficialStreetSurfaces"
    jette_street.transform = Transform3D(Basis.IDENTITY, Vector3(8.0, 1.0, 9.0))
    var jette_street_transform := jette_street.transform
    road_runtime.call("_register_official_surface", jette_street)
    if road_runtime.official_applied_road_count() != 2:
        ixelles_root.free(); jette_street.free(); road_runtime.free(); sidewalk_runtime.free(); return _fail("Jette official street surface was not registered")
    sidewalk_runtime.call("_register_official_sidewalk", jette_street)
    if sidewalk_runtime.official_applied_sidewalk_count() != 1:
        ixelles_root.free(); jette_street.free(); road_runtime.free(); sidewalk_runtime.free(); return _fail("Jette untyped street bundle was incorrectly claimed as sidewalk")
    if not jette_street.transform.is_equal_approx(jette_street_transform):
        ixelles_root.free(); jette_street.free(); road_runtime.free(); sidewalk_runtime.free(); return _fail("Jette official street transform changed")

    var jette_tram := MeshInstance3D.new()
    jette_tram.name = "JetteOfficialTramNetwork"
    jette_tram.transform = Transform3D(Basis.IDENTITY, Vector3(5.0, 0.25, -2.0))
    var jette_tram_transform := jette_tram.transform
    var rail_runtime := RAIL_RUNTIME.new()
    rail_runtime.call("_register_official_rail", jette_tram)
    if rail_runtime.official_applied_rail_count() != 1:
        ixelles_root.free(); jette_street.free(); jette_tram.free(); road_runtime.free(); sidewalk_runtime.free(); rail_runtime.free(); return _fail("Jette official tram alignment was not registered")
    if jette_tram.material_override == null:
        ixelles_root.free(); jette_street.free(); jette_tram.free(); road_runtime.free(); sidewalk_runtime.free(); rail_runtime.free(); return _fail("Jette official tram alignment did not receive presentation material")
    if str(jette_tram.get_meta("ground_network_geometry_claim", "")) != "source_alignment_only_no_fabricated_dual_rail_gauge":
        ixelles_root.free(); jette_street.free(); jette_tram.free(); road_runtime.free(); sidewalk_runtime.free(); rail_runtime.free(); return _fail("Jette tram geometry claim is not conservative")
    if not jette_tram.transform.is_equal_approx(jette_tram_transform):
        ixelles_root.free(); jette_street.free(); jette_tram.free(); road_runtime.free(); sidewalk_runtime.free(); rail_runtime.free(); return _fail("Jette official tram transform changed")

    road_runtime.call("_set_material_state", false)
    sidewalk_runtime.call("_set_material_state", false)
    rail_runtime.call("_set_material_state", false)
    if ixelles_road.material_override != null or ixelles_sidewalk.material_override != null or jette_street.material_override != null or jette_tram.material_override != null:
        ixelles_root.free(); jette_street.free(); jette_tram.free(); road_runtime.free(); sidewalk_runtime.free(); rail_runtime.free(); return _fail("enhanced-off did not restore official material overrides")

    ixelles_root.free(); jette_street.free(); jette_tram.free(); road_runtime.free(); sidewalk_runtime.free(); rail_runtime.free()
    return true

func _fail(message: String) -> bool:
    push_error("BRUSSELS_GROUND_NETWORK_OFFICIAL_COVERAGE_FAIL: %s" % message)
    quit(1)
    return false