extends SceneTree

const SELECTOR := preload("res://game/scripts/zone_selector_runtime.gd")
const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"

func _init() -> void:
    var selector = SELECTOR.new()
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
    if not parsed is Dictionary:
        _fail("catalog JSON is not an object")
        return
    var document := parsed as Dictionary
    if str(document.get("schema", "")) != "grand-bruxelles-playable-zone-catalog-v2":
        _fail("catalog is not v2")
        return
    var model: Variant = document.get("quality_model", {})
    if not model is Dictionary:
        _fail("quality_model missing")
        return
    if bool((model as Dictionary).get("jouable_requires_human_promotion", true)):
        _fail("JOUABLE still requires pre-integration human promotion")
        return
    if bool((model as Dictionary).get("open_player_report_blocks_jouable", true)):
        _fail("open visual player reports still block JOUABLE")
        return
    if not bool((model as Dictionary).get("hard_blocker_blocks_jouable", false)):
        _fail("hard blocker promotion law missing")
        return
    if not bool((model as Dictionary).get("visual_findings_are_post_integration", false)):
        _fail("post-integration visual review law missing")
        return
    var contract: Variant = document.get("listing_contract", {})
    if not contract is Dictionary:
        _fail("listing_contract missing")
        return
    for key: String in ["requires_resources", "spawn_stable", "load_without_crash", "honest_quality"]:
        if not bool((contract as Dictionary).get(key, false)):
            _fail("listing contract gate missing: %s" % key)
            return
    var zones: Array = selector.call("parse_catalog_document", document)
    if zones.size() != 8:
        _fail("expected eight visible entries, got %d" % zones.size())
        return
    var midi := _zone_by_id(zones, "midi")
    if str(midi.get("quality", "")) != "JOUABLE" or str(midi.get("mode", "")) != "fast_travel" or str(midi.get("destination", "")) != "midi":
        _fail("Midi lost canonical JOUABLE compatibility")
        return
    var midi_machine_labo := _zone_by_id(zones, "midi_machine_labo")
    if str(midi_machine_labo.get("quality", "")) != "LABO":
        _fail("Midi City Machine candidate entry lost LABO quality")
        return
    if str(midi_machine_labo.get("review_alias_of", "")) != "midi":
        _fail("Midi City Machine candidate alias ownership missing")
        return
    if str(midi_machine_labo.get("mode", "")) != "script_zone" or str(midi_machine_labo.get("script", "")) != "res://game/zones/midi/midi_city_machine_zone.gd":
        _fail("Midi City Machine candidate runtime contract drifted")
        return
    var brut_doc := {
        "schema": "grand-bruxelles-playable-zone-catalog-v2",
        "zones": [{
            "id": "raw_lab",
            "label": "Raw Lab",
            "quality": "LABO_BRUT",
            "mode": "fast_travel",
            "destination": "midi",
            "requires": ["res://game/main.tscn"]
        }]
    }
    if (selector.call("parse_catalog_document", brut_doc) as Array).size() != 1:
        _fail("LABO_BRUT is not accepted by v2")
        return
    var invalid_doc := brut_doc.duplicate(true)
    (invalid_doc["zones"] as Array)[0]["quality"] = "MAGIC_READY"
    if not (selector.call("parse_catalog_document", invalid_doc) as Array).is_empty():
        _fail("unknown quality was accepted")
        return
    var legacy_doc := {
        "schema": "grand-bruxelles-playable-zone-catalog-v1",
        "zones": [{
            "id": "legacy",
            "label": "Legacy",
            "quality": "LABO",
            "mode": "fast_travel",
            "destination": "midi",
            "requires": ["res://game/main.tscn"]
        }]
    }
    if (selector.call("parse_catalog_document", legacy_doc) as Array).size() != 1:
        _fail("v1 backward compatibility was lost")
        return
    print("ZONE_CATALOG_V2_OK: visible=8 canonical=7 review_aliases=1 midi=JOUABLE midi_machine_labo=LABO visual_reports=SOFT hard_blockers=BLOCKING review=POST_INTEGRATION stored=JOUABLE,LABO,LABO_BRUT derived=LABO_REPORT,NON_LISTE unknown=REJECTED legacy_v1=ACCEPTED")
    selector.free()
    quit(0)

func _zone_by_id(zones: Array, zone_id: String) -> Dictionary:
    for raw: Variant in zones:
        if raw is Dictionary and str((raw as Dictionary).get("id", "")) == zone_id:
            return raw as Dictionary
    return {}

func _fail(message: String) -> void:
    push_error("ZONE_CATALOG_V2_FAIL: %s" % message)
    quit(1)
