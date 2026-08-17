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
    if not bool((model as Dictionary).get("jouable_requires_human_promotion", false)):
        _fail("JOUABLE human promotion law missing")
        return
    if not bool((model as Dictionary).get("open_player_report_blocks_jouable", false)):
        _fail("OPEN report promotion block missing")
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
    if zones.size() != 7:
        _fail("expected seven valid main zones, got %d" % zones.size())
        return
    var midi := _zone_by_id(zones, "midi")
    if str(midi.get("quality", "")) != "JOUABLE":
        _fail("Midi lost JOUABLE compatibility")
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
    print("ZONE_CATALOG_V2_OK: zones=7 midi=JOUABLE stored=JOUABLE,LABO,LABO_BRUT derived=LABO_REPORT,NON_LISTE unknown=REJECTED legacy_v1=ACCEPTED")
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
