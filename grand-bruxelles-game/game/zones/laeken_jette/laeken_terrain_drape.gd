extends Node

## Drape already-imported official UrbIS geometry over the official DTM tile.
## X/Z geometry is never changed. Only Y is adjusted where the DTM has a valid
## sample; features outside the 1 km terrain tile keep their existing flat Y.

var road_vertices_draped: int = 0
var building_vertices_draped: int = 0
var tram_vertices_draped: int = 0
var train_vertices_draped: int = 0
var sampled_min_y: float = INF
var sampled_max_y: float = -INF


func _ready() -> void:
    call_deferred("_apply")


func _apply() -> void:
    var zone := get_parent()
    var terrain = zone.get_node_or_null("LaekenTerrain")
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        push_warning("LaekenTerrainDrape: official DTM terrain is unavailable")
        return

    road_vertices_draped = _drape_surface(
        zone.get_node_or_null("OfficialStreetSurfaces") as MeshInstance3D,
        terrain,
        "surface",
        0.02
    )
    building_vertices_draped = _drape_surface(
        zone.get_node_or_null("OfficialBuildings") as MeshInstance3D,
        terrain,
        "preserve_height",
        0.0
    )
    tram_vertices_draped = _drape_surface(
        zone.get_node_or_null("OfficialTramNetwork") as MeshInstance3D,
        terrain,
        "surface",
        0.055
    )
    train_vertices_draped = _drape_surface(
        zone.get_node_or_null("OfficialTrainNetwork") as MeshInstance3D,
        terrain,
        "surface",
        0.07
    )

    print(
        "LAEKEN_DTM_DRAPE_READY: roads=%d buildings=%d tram=%d train=%d terrain_y=[%.2f, %.2f]" % [
            road_vertices_draped,
            building_vertices_draped,
            tram_vertices_draped,
            train_vertices_draped,
            sampled_min_y if sampled_min_y < INF else 0.0,
            sampled_max_y if sampled_max_y > -INF else 0.0,
        ]
    )


func _drape_surface(instance: MeshInstance3D, terrain: Node, mode: String, surface_offset: float) -> int:
    if instance == null or instance.mesh == null or instance.mesh.get_surface_count() == 0:
        return 0

    var source_mesh := instance.mesh
    var arrays := source_mesh.surface_get_arrays(0)
    if arrays.size() <= Mesh.ARRAY_VERTEX:
        return 0
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    if not (vertices is PackedVector3Array):
        return 0

    var source_material := source_mesh.surface_get_material(0)
    var changed := 0
    var output_vertices: PackedVector3Array = vertices
    for index in range(output_vertices.size()):
        var point := output_vertices[index]
        if not bool(terrain.call("contains_game_point", point.x, point.z)):
            continue
        var terrain_y := float(terrain.call("sample_height", point.x, point.z))
        sampled_min_y = minf(sampled_min_y, terrain_y)
        sampled_max_y = maxf(sampled_max_y, terrain_y)
        if mode == "preserve_height":
            # Buildings were authored with base at Y=0 and roof at Y=height.
            # Adding terrain elevation preserves their vertical dimensions while
            # grounding each footprint vertex on the official DTM.
            point.y += terrain_y
        else:
            point.y = terrain_y + surface_offset
        output_vertices[index] = point
        changed += 1

    if changed == 0:
        return 0

    arrays[Mesh.ARRAY_VERTEX] = output_vertices
    var rebuilt := ArrayMesh.new()
    rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    if source_material != null:
        rebuilt.surface_set_material(0, source_material)
    instance.mesh = rebuilt
    return changed
