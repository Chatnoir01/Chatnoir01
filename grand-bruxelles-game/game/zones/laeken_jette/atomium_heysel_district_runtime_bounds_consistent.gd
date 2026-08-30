extends "res://game/zones/laeken_jette/atomium_heysel_district_runtime.gd"

## Keep the runtime's source-bounds acceptance identical to the compact slicer.
## A line/polygon may legitimately cross the official DTM envelope even when none
## of its source vertices lies strictly inside it. Testing only vertices dropped
## four tram/train features that cross a tile edge. The renderer still samples
## every generated ribbon corner against the official DTM and skips any segment
## that cannot be truthfully draped.
func _feature_intersects_dtm(feature: Dictionary) -> bool:
    var geometry: Variant = feature.get("geometry", {})
    if not geometry is Dictionary:
        return false
    var points := _geometry_points(geometry as Dictionary)
    if points.is_empty():
        return false

    var min_e := INF
    var min_n := INF
    var max_e := -INF
    var max_n := -INF
    for point: Vector2 in points:
        var source_point := _to_epsg31370(point)
        min_e = minf(min_e, source_point.x)
        min_n = minf(min_n, source_point.y)
        max_e = maxf(max_e, source_point.x)
        max_n = maxf(max_n, source_point.y)

    var dtm_min := source_bbox_epsg31370.position
    var dtm_max := source_bbox_epsg31370.end
    return max_e >= dtm_min.x and min_e <= dtm_max.x and max_n >= dtm_min.y and min_n <= dtm_max.y
