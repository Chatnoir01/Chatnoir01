extends Node

@export var radius_m: float = 610.0

const MIDI_WORLD := Vector3(-668.5, 0.0, 627.84)
const SUPPORT_RAY_HEIGHT_M := 2.0
const SUPPORT_RAY_DEPTH_M := 2.0
const SUPPORT_RAY_MAX_HITS := 12
const BUILDING_SUPPORT_RAY_MARGIN_M := 1.0


func _ready() -> void:
    call_deferred("_apply_mask")


func _inside(position: Vector3) -> bool:
    return Vector2(position.x - MIDI_WORLD.x, position.z - MIDI_WORLD.z).length() <= radius_m


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
    var cursor: Node = node
    while cursor != null:
        if cursor == ancestor:
            return true
        cursor = cursor.get_parent()
    return false


func _authoritative_support_between(world_point: Vector3, authoritative_root: Node, ray_from_y: float, ray_to_y: float) -> bool:
    if authoritative_root == null or get_viewport() == null or get_viewport().world_3d == null:
        return false
    if ray_from_y <= ray_to_y:
        return false
    var space_state: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
    var excluded: Array[RID] = []
    var ray_from := Vector3(world_point.x, ray_from_y, world_point.z)
    var ray_to := Vector3(world_point.x, ray_to_y, world_point.z)
    for _hit_index: int in range(SUPPORT_RAY_MAX_HITS):
        var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
        query.collision_mask = 1
        query.collide_with_bodies = true
        query.collide_with_areas = false
        query.exclude = excluded
        var hit: Dictionary = space_state.intersect_ray(query)
        if hit.is_empty():
            return false
        var collider: Variant = hit.get("collider")
        if collider is Node and _is_descendant_of(collider as Node, authoritative_root):
            return true
        var hit_rid: RID = hit.get("rid", RID())
        if not hit_rid.is_valid():
            return false
        excluded.append(hit_rid)
    return false


func _authoritative_support_at(world_point: Vector3, authoritative_root: Node) -> bool:
    return _authoritative_support_between(
        world_point,
        authoritative_root,
        world_point.y + SUPPORT_RAY_HEIGHT_M,
        world_point.y - SUPPORT_RAY_DEPTH_M
    )


func _support_samples(node_3d: Node3D) -> Array[Vector3]:
    var samples: Array[Vector3] = [node_3d.global_position]
    if node_3d is CSGBox3D:
        var box := node_3d as CSGBox3D
        var size := box.size
        if size.z >= size.x:
            samples.append(box.global_transform * Vector3(0.0, 0.0, -size.z * 0.35))
            samples.append(box.global_transform * Vector3(0.0, 0.0, size.z * 0.35))
        else:
            samples.append(box.global_transform * Vector3(-size.x * 0.35, 0.0, 0.0))
            samples.append(box.global_transform * Vector3(size.x * 0.35, 0.0, 0.0))
    return samples


func _has_spatial_authoritative_support(node_3d: Node3D, authoritative_root: Node) -> bool:
    for sample: Vector3 in _support_samples(node_3d):
        if not _authoritative_support_at(sample, authoritative_root):
            return false
    return true


func _authoritative_geometry_vertical_span(authoritative_root: Node) -> Vector2:
    if authoritative_root == null:
        return Vector2.ZERO
    var min_y := INF
    var max_y := -INF
    var found := false
    var stack: Array[Node] = [authoritative_root]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is MeshInstance3D:
            var mesh_instance := node as MeshInstance3D
            if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0 and mesh_instance.is_visible_in_tree():
                var aabb := mesh_instance.get_aabb()
                for corner_index: int in range(8):
                    var local_corner := Vector3(
                        aabb.position.x + aabb.size.x * float(corner_index & 1),
                        aabb.position.y + aabb.size.y * float((corner_index >> 1) & 1),
                        aabb.position.z + aabb.size.z * float((corner_index >> 2) & 1)
                    )
                    var world_corner: Vector3 = mesh_instance.global_transform * local_corner
                    min_y = minf(min_y, world_corner.y)
                    max_y = maxf(max_y, world_corner.y)
                    found = true
        for child: Node in node.get_children():
            stack.append(child)
    if not found:
        return Vector2.ZERO
    return Vector2(min_y - BUILDING_SUPPORT_RAY_MARGIN_M, max_y + BUILDING_SUPPORT_RAY_MARGIN_M)


func _has_spatial_authoritative_building_support(node_3d: Node3D, authoritative_root: Node, vertical_span: Vector2) -> bool:
    if vertical_span.y <= vertical_span.x:
        return false
    for sample: Vector3 in _support_samples(node_3d):
        if not _authoritative_support_between(sample, authoritative_root, vertical_span.y, vertical_span.x):
            return false
    return true


func _mask_children(root: Node, authoritative_root: Node = null, require_spatial_support: bool = false) -> int:
    var hidden: int = 0
    for child: Node in root.get_children():
        if child is Node3D:
            var node_3d: Node3D = child as Node3D
            if not _inside(node_3d.global_position):
                continue
            if node_3d is GeometryInstance3D:
                if require_spatial_support and not _has_spatial_authoritative_support(node_3d, authoritative_root):
                    continue
                var geometry: GeometryInstance3D = node_3d as GeometryInstance3D
                geometry.visible = false
                hidden += 1
    return hidden


func _mask_buildings(root: Node, authoritative_root: Node) -> int:
    var vertical_span := _authoritative_geometry_vertical_span(authoritative_root)
    if vertical_span.y <= vertical_span.x:
        return 0
    var hidden := 0
    for child: Node in root.get_children():
        if child is not Node3D:
            continue
        var node_3d := child as Node3D
        if not _inside(node_3d.global_position):
            continue
        if node_3d is not GeometryInstance3D:
            continue
        if not _has_spatial_authoritative_building_support(node_3d, authoritative_root, vertical_span):
            continue
        var geometry := node_3d as GeometryInstance3D
        geometry.visible = false
        hidden += 1
    return hidden


func _mask_facade_details(root: Node, authoritative_root: Node) -> int:
    var vertical_span := _authoritative_geometry_vertical_span(authoritative_root)
    if vertical_span.y <= vertical_span.x:
        return 0
    var hidden := 0
    var stack: Array[Node] = []
    for child: Node in root.get_children():
        stack.append(child)
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is Node3D:
            var node_3d := node as Node3D
            if node_3d is GeometryInstance3D and _inside(node_3d.global_position):
                if _has_spatial_authoritative_building_support(node_3d, authoritative_root, vertical_span):
                    var geometry := node_3d as GeometryInstance3D
                    geometry.visible = false
                    hidden += 1
        for child: Node in node.get_children():
            stack.append(child)
    return hidden


func _has_materialized_geometry(root: Node) -> bool:
    if root == null:
        return false
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is MeshInstance3D:
            var mesh_instance := node as MeshInstance3D
            if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0 and mesh_instance.is_visible_in_tree():
                return true
        for child: Node in node.get_children():
            stack.append(child)
    return false


func _apply_mask() -> void:
    var osm: Node = get_node_or_null("../BrusselsOSM")
    if osm == null:
        return

    var urbis: Node = get_node_or_null("../UrbISMidiExact")
    var street_surfaces: Node = null
    var exact_buildings: Node = null
    var streets_ready := false
    var buildings_ready := false
    if urbis != null:
        street_surfaces = urbis.get_node_or_null("UrbISStreetSurfaces")
        exact_buildings = urbis.get_node_or_null("UrbISExactBuildings")
        streets_ready = _has_materialized_geometry(street_surfaces)
        buildings_ready = _has_materialized_geometry(exact_buildings)

    var hidden: int = 0
    var roads: Node = osm.get_node_or_null("GeneratedRoads")
    if roads != null and streets_ready:
        hidden += _mask_children(roads, street_surfaces, true)

    var buildings: Node = osm.get_node_or_null("GeneratedBuildings")
    if buildings != null and buildings_ready:
        hidden += _mask_buildings(buildings, exact_buildings)

    # These procedural facade instances only belonged to the old Midi OSM
    # massing. Preserve them as fallback wherever no concrete authoritative
    # UrbIS building replacement exists at the same spatial support samples.
    if buildings_ready:
        var details: Node = osm.get_node_or_null("GeneratedFacadeDetails")
        if details != null:
            _mask_facade_details(details, exact_buildings)

    print(
        "Grand Bruxelles UrbIS mask: %d approximate OSM geometry nodes hidden near Midi with spatial official support (streets_ready=%s buildings_ready=%s)" %
        [hidden, str(streets_ready), str(buildings_ready)]
    )
