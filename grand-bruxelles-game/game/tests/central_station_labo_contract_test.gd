extends SceneTree

const CENTRAL_ZONE := preload("res://game/zones/central/central_station_labo.gd")
const EXPECTED_ANCHOR := Vector3(647.68, 0.0, -407.70)


func _init() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("CENTRAL_STATION_LABO_TEST_FAIL: %s" % message)
    quit(1)


func _count_children_with_prefix(parent: Node, prefix: String) -> int:
    var count := 0
    for child: Node in parent.get_children():
        if child.name.begins_with(prefix):
            count += 1
    return count


func _run() -> void:
    var zone := CENTRAL_ZONE.new()
    zone.name = "CentralStationLaboTestZone"
    get_root().add_child(zone)
    await process_frame
    await process_frame

    if zone.identity_failure():
        _fail("identity contract rejected")
        return

    var stats: Variant = zone.get("last_stats")
    if not stats is Dictionary:
        _fail("last_stats is not a Dictionary")
        return
    var stat_dict := stats as Dictionary
    if int(stat_dict.get("buildings", 0)) != 1:
        _fail("expected exactly one source-backed review building")
        return
    if int(stat_dict.get("street_surfaces", 0)) != 1:
        _fail("expected exactly one review forecourt surface")
        return
    if int(stat_dict.get("upper_bays", 0)) != 9:
        _fail("Urban 30201 invariant requires nine upper bays")
        return
    if int(stat_dict.get("entrance_columns", 0)) != 4:
        _fail("Urban 30201 invariant requires four entrance columns")
        return

    var station: Node3D = zone.station_root()
    if station == null:
        _fail("station root missing")
        return
    if station.name != "CentralStationUrban30201":
        _fail("unexpected station root name")
        return
    if int(station.get_meta("source_urban_id", -1)) != 30201:
        _fail("Urban source id metadata missing")
        return
    if str(station.get_meta("quality", "")) != "LABO_BRUT":
        _fail("Central must remain LABO_BRUT")
        return
    if bool(station.get_meta("authoritative_urbis_alignment", true)):
        _fail("review anchor must not claim authoritative UrbIS alignment")
        return
    if not bool(station.get_meta("procedural_dimensions_are_visualization_convention", false)):
        _fail("procedural dimensions must be disclosed as visualization convention")
        return
    if bool(station.get_meta("promotion_allowed", true)):
        _fail("promotion must remain blocked")
        return

    if station.get_node_or_null("MainEntranceConcaveReview/MainEntranceCanopy") == null:
        _fail("main entrance canopy missing")
        return
    if station.get_node_or_null("SignBruxellesCentral") == null or station.get_node_or_null("SignBrusselCentraal") == null:
        _fail("bilingual station signage missing")
        return

    var entrance := station.get_node_or_null("MainEntranceConcaveReview")
    if entrance == null or _count_children_with_prefix(entrance, "MainEntranceColumn_") != 4:
        _fail("four entrance columns not materialized")
        return
    var upper := station.get_node_or_null("UpperNineBayRhythm")
    if upper == null or _count_children_with_prefix(upper, "UpperBayGlass_") != 9:
        _fail("nine upper bays not materialized")
        return

    var anchor: Vector3 = zone.review_anchor()
    if anchor.distance_to(EXPECTED_ANCHOR) > 0.01:
        _fail("review anchor drifted")
        return
    if zone.get_node_or_null("CentralReviewForecourt") == null or zone.get_node_or_null("CentralReviewForecourtCollision") == null:
        _fail("review forecourt or collision missing")
        return

    print("CENTRAL_STATION_LABO_TEST_OK urban_id=30201 buildings=1 surfaces=1 bays=9 columns=4 quality=LABO_BRUT promotion=false")
    quit(0)
