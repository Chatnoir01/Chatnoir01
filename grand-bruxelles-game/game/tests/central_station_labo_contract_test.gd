extends SceneTree

const CENTRAL_ZONE := preload("res://game/zones/central/central_station_context_labo.gd")
const EXPECTED_ANCHOR := Vector3(647.68, 0.0, -407.70)

func _init() -> void: call_deferred("_run")
func _fail(message: String) -> void: push_error("CENTRAL_STATION_LABO_TEST_FAIL: %s" % message); quit(1)
func _count_children_with_prefix(parent: Node, prefix: String) -> int:
    var count := 0
    for child: Node in parent.get_children():
        if child.name.begins_with(prefix): count += 1
    return count

func _run() -> void:
    var zone := CENTRAL_ZONE.new(); zone.name = "CentralStationLaboTestZone"; get_root().add_child(zone); await process_frame; await process_frame
    if zone.identity_failure(): _fail("identity contract rejected"); return
    var stats: Variant = zone.get("last_stats")
    if not stats is Dictionary: _fail("last_stats is not a Dictionary"); return
    var stat_dict := stats as Dictionary
    if int(stat_dict.get("buildings", 0)) != 1 or int(stat_dict.get("street_surfaces", 0)) != 1: _fail("review building/surface contract drifted"); return
    if int(stat_dict.get("upper_bays", 0)) != 9 or int(stat_dict.get("entrance_columns", 0)) != 4: _fail("Urban 30201 bay/column invariant drifted"); return
    var station: Node3D = zone.station_root()
    if station == null or station.name != "CentralStationUrban30201": _fail("station root missing"); return
    if int(station.get_meta("source_urban_id", -1)) != 30201 or str(station.get_meta("quality", "")) != "LABO_BRUT": _fail("source/quality metadata missing"); return
    if bool(station.get_meta("authoritative_urbis_alignment", true)) or bool(station.get_meta("promotion_allowed", true)): _fail("truth contract drifted"); return
    if not bool(station.get_meta("procedural_dimensions_are_visualization_convention", false)): _fail("procedural disclosure missing"); return
    var entrance := station.get_node_or_null("MainEntranceConcaveReview")
    if entrance == null or entrance.get_node_or_null("MainEntranceCanopy") == null or _count_children_with_prefix(entrance, "MainEntranceColumn_") != 4: _fail("entrance identity incomplete"); return
    if _count_children_with_prefix(entrance, "EntranceDoorGlass_") != 5: _fail("entrance doors missing"); return
    if station.get_node_or_null("SignBruxellesCentral") == null or station.get_node_or_null("SignBrusselCentraal") == null: _fail("bilingual station signage missing"); return
    var upper := station.get_node_or_null("UpperNineBayRhythm")
    if upper == null or _count_children_with_prefix(upper, "UpperBayGlass_") != 9 or _count_children_with_prefix(upper, "RecessedTrumeau_") != 10: _fail("upper facade articulation incomplete"); return
    if station.get_node_or_null("BoulevardImperatriceThreeSidedBowWindowReview") == null: _fail("boulevard bow-window reading missing"); return
    if station.get_node_or_null("RoofSetback") == null or _count_children_with_prefix(station, "RoofVent_") != 5: _fail("roof silhouette details missing"); return
    var station_depth := station.get_node_or_null("CentralStationReviewDepth")
    if station_depth == null or station_depth.get_node_or_null("EntranceTransomGlass") == null: _fail("street-level station depth layer missing"); return
    if _count_children_with_prefix(station_depth, "UpperBaySill_") != 9 or _count_children_with_prefix(station_depth, "EntranceStep_") != 3: _fail("station depth articulation incomplete"); return
    if zone.review_anchor().distance_to(EXPECTED_ANCHOR) > 0.01: _fail("review anchor drifted"); return
    if zone.get_node_or_null("CentralReviewForecourt") == null or zone.get_node_or_null("CentralReviewForecourtCollision") == null: _fail("review forecourt or collision missing"); return
    if _count_children_with_prefix(zone, "CentralReviewBollard_") != 8 or _count_children_with_prefix(zone, "CentralReviewLamp_") != 2: _fail("street-scale frontage furniture missing"); return
    var context := zone.get_node_or_null("CentralProceduralStreetContext")
    if context == null: _fail("procedural street context missing"); return
    if bool(context.get_meta("authoritative", true)) or bool(context.get_meta("source_geometry", true)): _fail("procedural context fabricated authority"); return
    if int(zone.get_meta("central_context_block_masses", 0)) != 7 or int(zone.get_meta("central_context_road_segments", 0)) != 3: _fail("context block/road count drifted"); return
    if int(zone.get_meta("central_context_storefront_groups", 0)) != 7 or int(zone.get_meta("central_context_tree_count", 0)) != 6: _fail("street-level context richness drifted"); return
    for road_name: String in ["ReviewRoad_CarrefourEurope", "ReviewRoad_Impératrice", "ReviewRoad_Putterie"]:
        if context.get_node_or_null(road_name) == null: _fail("review road missing: %s" % road_name); return
    for block_name: String in ["WestBlockNorth", "WestBlockSouth", "EastBlockNorth", "EastBlockSouth", "ForecourtOppositeWest", "ForecourtOppositeCenter", "ForecourtOppositeEast"]:
        var block := context.get_node_or_null(block_name)
        if block == null or block.get_node_or_null("Massing") == null or block.get_node_or_null("GroundCornice") == null: _fail("context block detail missing: %s" % block_name); return
    if _count_children_with_prefix(context, "ContextTree_") != 6 or _count_children_with_prefix(context, "ContextBenchSeat_") != 4: _fail("context furniture/trees missing"); return
    if _count_children_with_prefix(context, "ReviewCrosswalk_") != 8 or _count_children_with_prefix(context, "ReviewFrontLaneDash_") != 10: _fail("street markings incomplete"); return
    print("CENTRAL_STATION_LABO_TEST_OK urban_id=30201 buildings=1 surfaces=1 bays=9 columns=4 doors=5 blocks=7 roads=3 storefront_groups=7 trees=6 quality=LABO_BRUT authoritative=false promotion=false")
    quit(0)
