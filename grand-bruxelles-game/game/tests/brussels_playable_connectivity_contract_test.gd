extends SceneTree

const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"
const CONNECTIVITY_PATH := "res://data/qa/brussels_playable_connectivity.json"
const PLANNED_CENTER_NORTH := ["rogier", "gare_du_nord"]

func _init() -> void:
    var catalog := _load_json(CATALOG_PATH)
    if catalog.is_empty():
        return
    var graph := _load_json(CONNECTIVITY_PATH)
    if graph.is_empty():
        return
    if str(graph.get("schema", "")) != "grand-bruxelles-playable-connectivity-v1":
        _fail("connectivity schema drifted")
        return

    var canonical_catalog_ids := _canonical_catalog_ids(catalog)
    if canonical_catalog_ids.is_empty():
        _fail("catalog has no canonical zones")
        return

    var nodes_result := _index_nodes(graph)
    if not bool(nodes_result.get("ok", false)):
        return
    var nodes: Dictionary = nodes_result.get("nodes", {})

    for zone_id: String in canonical_catalog_ids:
        if not nodes.has(zone_id):
            _fail("canonical catalog zone missing from connectivity graph: %s" % zone_id)
            return
        var node: Dictionary = nodes[zone_id]
        if not bool(node.get("catalog_required", false)):
            _fail("catalog zone is not marked catalog_required: %s" % zone_id)
            return
        if str(node.get("status", "")) != "LISTABLE":
            _fail("catalog zone is not LISTABLE in connectivity graph: %s" % zone_id)
            return

    for node_id: Variant in nodes.keys():
        var node: Dictionary = nodes[node_id]
        if bool(node.get("catalog_required", false)) and not canonical_catalog_ids.has(str(node_id)):
            _fail("connectivity graph claims absent catalog zone: %s" % str(node_id))
            return

    var playable_adjacency := _build_playable_adjacency(graph, nodes)
    if playable_adjacency.is_empty():
        return
    var root_id := str(graph.get("root_zone", ""))
    if not canonical_catalog_ids.has(root_id):
        _fail("root zone is not canonical/listable: %s" % root_id)
        return
    var reachable := _reachable_from(root_id, playable_adjacency)
    for zone_id: String in canonical_catalog_ids:
        if not reachable.has(zone_id):
            _fail("canonical listable zone is isolated from %s: %s" % [root_id, zone_id])
            return

    for planned_id: String in PLANNED_CENTER_NORTH:
        if not nodes.has(planned_id):
            _fail("required center-north expansion node missing: %s" % planned_id)
            return
        var planned: Dictionary = nodes[planned_id]
        if bool(planned.get("catalog_required", true)):
            _fail("unproven expansion node was promoted into catalog contract: %s" % planned_id)
            return
        if str(planned.get("status", "")) != "NON_LISTE":
            _fail("unproven expansion node must stay NON_LISTE: %s" % planned_id)
            return
        if str(planned.get("ground", "")) != "source_required":
            _fail("unproven expansion node must expose source gap: %s" % planned_id)
            return
        var blockers: Variant = planned.get("blockers", [])
        if not blockers is Array or blockers.is_empty():
            _fail("unproven expansion node has no promotion blockers: %s" % planned_id)
            return
        if reachable.has(planned_id):
            _fail("source_required expansion node incorrectly counted as playable: %s" % planned_id)
            return

    var expansion: Variant = graph.get("center_north_expansion", {})
    if not expansion is Dictionary:
        _fail("center_north_expansion contract missing")
        return
    if bool((expansion as Dictionary).get("promotion_allowed", true)):
        _fail("Rogier/Nord promotion must remain blocked before source/runtime proof")
        return
    var source_extension := float((expansion as Dictionary).get("required_source_extension_north_m", 0.0))
    if source_extension < 1700.0:
        _fail("center-north source gap unexpectedly small: %.2f m" % source_extension)
        return

    print("BRUSSELS_PLAYABLE_CONNECTIVITY_OK: canonical=%d reachable=%d root=%s planned=rogier,gare_du_nord promotion=BLOCKED source_extension_north_m=%.2f" % [canonical_catalog_ids.size(), reachable.size(), root_id, source_extension])
    quit(0)

func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        _fail("JSON file missing: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary:
        _fail("JSON file is not an object: %s" % path)
        return {}
    return parsed as Dictionary

func _canonical_catalog_ids(catalog: Dictionary) -> Array[String]:
    var result: Array[String] = []
    var zones: Variant = catalog.get("zones", [])
    if not zones is Array:
        return result
    for raw: Variant in zones:
        if not raw is Dictionary:
            continue
        var zone := raw as Dictionary
        if not str(zone.get("review_alias_of", "")).strip_edges().is_empty():
            continue
        var zone_id := str(zone.get("id", "")).strip_edges()
        if not zone_id.is_empty():
            result.append(zone_id)
    result.sort()
    return result

func _index_nodes(graph: Dictionary) -> Dictionary:
    var nodes: Dictionary = {}
    var raw_nodes: Variant = graph.get("nodes", [])
    if not raw_nodes is Array:
        _fail("connectivity nodes are not an array")
        return {"ok": false}
    for raw: Variant in raw_nodes:
        if not raw is Dictionary:
            _fail("connectivity node is not an object")
            return {"ok": false}
        var node := raw as Dictionary
        var node_id := str(node.get("id", "")).strip_edges()
        if node_id.is_empty():
            _fail("connectivity node id is empty")
            return {"ok": false}
        if nodes.has(node_id):
            _fail("duplicate connectivity node: %s" % node_id)
            return {"ok": false}
        nodes[node_id] = node
    return {"ok": true, "nodes": nodes}

func _build_playable_adjacency(graph: Dictionary, nodes: Dictionary) -> Dictionary:
    var adjacency: Dictionary = {}
    for node_id: Variant in nodes.keys():
        adjacency[str(node_id)] = []
    var seen_edges: Dictionary = {}
    var edges: Variant = graph.get("edges", [])
    if not edges is Array:
        _fail("connectivity edges are not an array")
        return {}
    for raw: Variant in edges:
        if not raw is Dictionary:
            _fail("connectivity edge is not an object")
            return {}
        var edge := raw as Dictionary
        var a := str(edge.get("a", "")).strip_edges()
        var b := str(edge.get("b", "")).strip_edges()
        if a.is_empty() or b.is_empty() or a == b:
            _fail("invalid connectivity edge: %s" % str(edge))
            return {}
        if not nodes.has(a) or not nodes.has(b):
            _fail("connectivity edge references unknown node: %s-%s" % [a, b])
            return {}
        var pair := [a, b]
        pair.sort()
        var edge_key := "%s|%s" % [pair[0], pair[1]]
        if seen_edges.has(edge_key):
            _fail("duplicate connectivity edge: %s" % edge_key)
            return {}
        seen_edges[edge_key] = true
        var status := str(edge.get("status", ""))
        var kind := str(edge.get("kind", ""))
        if status == "playable":
            if kind != "continuous_ground" and kind != "gameplay_transport":
                _fail("unknown playable edge kind: %s" % kind)
                return {}
            if kind == "continuous_ground":
                var node_a: Dictionary = nodes[a]
                var node_b: Dictionary = nodes[b]
                if str(node_a.get("ground", "")).contains("required") or str(node_b.get("ground", "")).contains("required"):
                    _fail("continuous playable edge crosses an unproven source gap: %s" % edge_key)
                    return {}
            (adjacency[a] as Array).append(b)
            (adjacency[b] as Array).append(a)
        elif status != "source_required":
            _fail("unknown edge status: %s" % status)
            return {}
    return adjacency

func _reachable_from(root_id: String, adjacency: Dictionary) -> Dictionary:
    var visited: Dictionary = {}
    var queue: Array[String] = [root_id]
    while not queue.is_empty():
        var current := queue.pop_front()
        if visited.has(current):
            continue
        visited[current] = true
        for neighbor: Variant in adjacency.get(current, []):
            var neighbor_id := str(neighbor)
            if not visited.has(neighbor_id):
                queue.append(neighbor_id)
    return visited

func _fail(message: String) -> void:
    push_error("BRUSSELS_PLAYABLE_CONNECTIVITY_FAIL: %s" % message)
    quit(1)
