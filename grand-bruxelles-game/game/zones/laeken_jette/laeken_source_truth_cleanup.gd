extends Node

## Disable legacy visual stand-ins once authoritative layers are available.
##
## Official City trees provide vegetation and the orthophoto carries the real
## pavement/road markings. The current Atomium corridor now generates lamps only,
## so cleanup hides older duplicate visual layers rather than inventing replacements.
##
## The committed 2026-08-12 UrbIS WFS slice currently returns TrainNetwork and
## TramNetwork with the same 326 source records (same INSPIRE_ID, TYPE, level,
## length and geometry; only the WFS feature id differs). The runtime therefore
## performs a complete signature comparison and hides the train ribbon only when
## the two source layers are actually identical. If a future UrbIS refresh returns
## distinct train data, the train layer remains visible automatically.

const TRAM_PATH := "res://data/urbis/laeken_jette/tram_network.game.json"
const TRAIN_PATH := "res://data/urbis/laeken_jette/train_network.game.json"

var cleanup_ready: bool = false
var hidden_legacy_approach: bool = false
var corridor_synthetic_trees: int = -1
var corridor_synthetic_dashes: int = -1
var kept_corridor_lamps: int = 0
var rail_source_checked: bool = false
var rail_source_duplicate_detected: bool = false
var duplicate_train_ribbon_hidden: bool = false
var rail_signature_matches: int = 0
var tram_source_features: int = 0
var train_source_features: int = 0


func _ready() -> void:
    call_deferred("_cleanup")


func _load_collection(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _feature_signature(feature: Dictionary) -> String:
    var properties = feature.get("properties", {})
    var geometry = feature.get("geometry", {})
    if not properties is Dictionary or not geometry is Dictionary:
        return ""
    return "%s|%s|%s|%.6f|%s" % [
        str(properties.get("INSPIRE_ID", "")),
        str(properties.get("TYPE", "")),
        str(properties.get("LVL", "")),
        float(properties.get("LENGTH", 0.0)),
        JSON.stringify(geometry),
    ]


func _signature_counts(document: Dictionary) -> Dictionary:
    var counts: Dictionary = {}
    var features = document.get("features", [])
    if not features is Array:
        return counts
    for feature in features:
        if not feature is Dictionary:
            continue
        var signature := _feature_signature(feature)
        if signature.is_empty():
            continue
        counts[signature] = int(counts.get(signature, 0)) + 1
    return counts


func _audit_and_cleanup_duplicate_rail_layer(zone: Node) -> void:
    var tram_document := _load_collection(TRAM_PATH)
    var train_document := _load_collection(TRAIN_PATH)
    var tram_features = tram_document.get("features", [])
    var train_features = train_document.get("features", [])
    tram_source_features = tram_features.size() if tram_features is Array else 0
    train_source_features = train_features.size() if train_features is Array else 0

    if tram_source_features <= 0 or train_source_features <= 0:
        rail_source_checked = true
        return

    var tram_signatures := _signature_counts(tram_document)
    var train_signatures := _signature_counts(train_document)
    for signature in tram_signatures.keys():
        rail_signature_matches += min(
            int(tram_signatures.get(signature, 0)),
            int(train_signatures.get(signature, 0))
        )

    rail_source_duplicate_detected = (
        tram_source_features == train_source_features
        and rail_signature_matches == tram_source_features
        and tram_signatures.size() == train_signatures.size()
    )

    if rail_source_duplicate_detected:
        var train_ribbon := zone.get_node_or_null("OfficialTrainNetwork") as MeshInstance3D
        if train_ribbon != null:
            train_ribbon.visible = false
            duplicate_train_ribbon_hidden = true
        else:
            # Missing legacy ribbon is also safe: no duplicate can be rendered.
            duplicate_train_ribbon_hidden = true

    rail_source_checked = true


func _cleanup() -> void:
    var zone := get_parent()

    # Both generators are deferred. Wait until the corridor has resolved its
    # official axis and produced its provisional lamp pass.
    var corridor = zone.get_node_or_null("AtomiumCorridor")
    for _frame in range(90):
        if corridor != null and float(corridor.get("official_axis_distance_m")) < INF and int(corridor.get("generated_lamps")) > 0:
            break
        await get_tree().process_frame

    # laeken_realism_pass.gd adds this root to the zone parent, not under the
    # RealismPass node itself.
    var legacy := zone.get_node_or_null("AtomiumApproachPhotoGuided") as Node3D
    if legacy != null:
        legacy.visible = false
        hidden_legacy_approach = true
    else:
        # If the legacy pass no longer creates the node in a future revision,
        # that also satisfies the source-truth policy.
        hidden_legacy_approach = true

    if corridor != null:
        corridor_synthetic_trees = int(corridor.get("generated_trees"))
        corridor_synthetic_dashes = int(corridor.get("generated_dashes"))
        kept_corridor_lamps = int(corridor.get("generated_lamps"))

    _audit_and_cleanup_duplicate_rail_layer(zone)

    cleanup_ready = (
        hidden_legacy_approach
        and corridor_synthetic_trees == 0
        and corridor_synthetic_dashes == 0
        and kept_corridor_lamps > 0
        and rail_source_checked
        and (not rail_source_duplicate_detected or duplicate_train_ribbon_hidden)
    )
    print("LAEKEN_SOURCE_TRUTH_CLEANUP_READY: legacy_hidden=%s corridor_trees=%d corridor_dashes=%d kept_lamps=%d rail_checked=%s rail_duplicate=%s duplicate_train_hidden=%s rail_signature_matches=%d tram_features=%d train_features=%d" % [
        hidden_legacy_approach,
        corridor_synthetic_trees,
        corridor_synthetic_dashes,
        kept_corridor_lamps,
        rail_source_checked,
        rail_source_duplicate_detected,
        duplicate_train_ribbon_hidden,
        rail_signature_matches,
        tram_source_features,
        train_source_features,
    ])
