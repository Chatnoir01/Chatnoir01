extends Node

const HUMANOID_VISUAL_SCRIPT := preload("res://game/scripts/humanoid_visual.gd")
const EXPECTED_AMBIENT := 24
const TARGET_AMBIENT_DENSITY := 24
const MAX_DISCOVERY_FRAMES := 120
const PROXY_Y_OFFSET := 0.90
const LOD_SWITCH_DISTANCE_M := 90.0
const LOD_TRANSITION_MARGIN_M := 10.0
const VISUAL_PROFILE := "profiled_humanoid_v2"
const LEGACY_VISUAL_NAMES := ["Torso", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Head", "Bag"]

var _bridged_scene_ids: Dictionary = {}
var _shared_materials: Dictionary = {}
var _deduplicated_surfaces: int = 0


func _ready() -> void:
    if not get_tree().node_added.is_connected(_on_scene_node_added):
        get_tree().node_added.connect(_on_scene_node_added)
    call_deferred("_bridge_when_ready")


func _exit_tree() -> void:
    if get_tree() != null and get_tree().node_added.is_connected(_on_scene_node_added):
        get_tree().node_added.disconnect(_on_scene_node_added)


func _on_scene_node_added(node: Node) -> void:
    if node == null or node.name != "MidiUrbanLife":
        return
    # Preserve the production crowd baseline established by this existing autoload.
    # This PR changes only presentation/bridge safety; it must not regress density.
    var current_density: Variant = node.get("pedestrian_count")
    if current_density != null and int(current_density) < TARGET_AMBIENT_DENSITY:
        node.set("pedestrian_count", TARGET_AMBIENT_DENSITY)
    call_deferred("_bridge_parent_scene", node)


func _bridge_parent_scene(urban_life: Node) -> void:
    if not is_instance_valid(urban_life):
        return
    var scene := urban_life.get_parent()
    if scene != null:
        bridge_scene(scene)


func _bridge_when_ready() -> void:
    for _frame: int in range(MAX_DISCOVERY_FRAMES):
        var scene := _find_scene_with_ambient_crowd()
        if scene != null:
            bridge_scene(scene)
            return
        await get_tree().process_frame
    push_warning("Midi ambient NPC visual bridge did not find a production crowd within %d frames" % MAX_DISCOVERY_FRAMES)


func _find_scene_with_ambient_crowd() -> Node:
    var current := get_tree().current_scene
    if current != null and current.get_node_or_null("MidiUrbanLife") != null:
        return current
    for child: Node in get_tree().root.get_children():
        if child == self:
            continue
        if child.get_node_or_null("MidiUrbanLife") != null:
            return child
    return null


func bridge_scene(scene: Node) -> Dictionary:
    if scene == null:
        return _empty_bridge_stats()
    var scene_id := scene.get_instance_id()
    var urban_life := scene.get_node_or_null("MidiUrbanLife")
    if urban_life == null:
        return _empty_bridge_stats()

    var bridged := 0
    var already := 0
    var failed := 0
    var reused_before := _deduplicated_surfaces
    for child: Node in urban_life.get_children():
        if not child.is_in_group("ambient_pedestrian"):
            continue
        var person := child as Node3D
        if person == null:
            continue
        if person.get_node_or_null("ProfiledNpcProxy") != null:
            already += 1
            _configure_distance_lod(person, true)
            continue
        if _attach_profiled_proxy(person, _seed_for_person(person)):
            bridged += 1
        else:
            failed += 1

    var materials_reused := _deduplicated_surfaces - reused_before
    if bridged + already > 0:
        _bridged_scene_ids[scene_id] = true
    var lod := _lod_counts_for_scene(scene)
    print("Midi ambient NPC visual bridge: bridged=%d already=%d failed=%d materials_reused=%d cache_entries=%d lod_detailed=%d lod_legacy=%d lod_switch_m=%.1f" % [bridged, already, failed, materials_reused, _shared_materials.size(), int(lod.get("detailed_meshes", 0)), int(lod.get("legacy_visuals", 0)), LOD_SWITCH_DISTANCE_M])
    return {
        "bridged": bridged,
        "already": already,
        "failed": failed,
        "materials_reused": materials_reused,
        "material_cache_entries": _shared_materials.size(),
        "lod_detailed_meshes": int(lod.get("detailed_meshes", 0)),
        "lod_legacy_visuals": int(lod.get("legacy_visuals", 0)),
    }


func _empty_bridge_stats() -> Dictionary:
    return {
        "bridged": 0,
        "already": 0,
        "failed": 0,
        "materials_reused": 0,
        "material_cache_entries": _shared_materials.size(),
        "lod_detailed_meshes": 0,
        "lod_legacy_visuals": 0,
    }


func set_profiled_visuals_enabled(scene: Node, enabled: bool) -> int:
    if scene == null:
        return 0
    var urban_life := scene.get_node_or_null("MidiUrbanLife")
    if urban_life == null:
        return 0
    var changed := 0
    for child: Node in urban_life.get_children():
        if not child.is_in_group("ambient_pedestrian"):
            continue
        var person := child as Node3D
        if person == null:
            continue
        var proxy := person.get_node_or_null("ProfiledNpcProxy") as Node3D
        if proxy != null:
            proxy.visible = enabled
            changed += 1
        _configure_distance_lod(person, enabled)
    return changed


func _attach_profiled_proxy(person: Node3D, seed_value: int) -> bool:
    # Add the inactive NpcAgent first so its appearance contract is initialized before
    # HumanoidVisual enters the tree. This also lets the existing quality runtime see
    # the visual as a child of an npc_agent group member.
    var proxy := NpcAgent.new()
    proxy.name = "ProfiledNpcProxy"
    proxy.role = NpcBehaviorModel.Role.CIVILIAN
    proxy.variation_seed = seed_value
    proxy.active = false
    proxy.process_mode = Node.PROCESS_MODE_DISABLED
    proxy.collision_layer = 0
    proxy.collision_mask = 0
    proxy.position = Vector3(0.0, PROXY_Y_OFFSET, 0.0)
    proxy.set_meta("ambient_visual_proxy", true)
    proxy.set_meta("visual_profile", VISUAL_PROFILE)
    person.add_child(proxy)
    proxy.add_to_group("npc_agent")

    var visual := Node3D.new()
    visual.name = "VisualUpgrade"
    visual.set_script(HUMANOID_VISUAL_SCRIPT)
    proxy.add_child(visual)
    if visual.get_node_or_null("Torso") == null or visual.get_node_or_null("Head") == null:
        proxy.queue_free()
        return false

    person.set_meta("visual_profile", VISUAL_PROFILE)
    person.set_meta("shared_humanoid_pipeline", true)
    _deduplicate_proxy_materials(visual)
    _configure_distance_lod(person, true)
    return true


func _configure_distance_lod(person: Node3D, profiled_enabled: bool) -> void:
    var proxy := person.get_node_or_null("ProfiledNpcProxy") as Node3D
    if proxy != null:
        proxy.visible = profiled_enabled
        var visual := proxy.get_node_or_null("VisualUpgrade") as Node3D
        if visual != null:
            for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
                var mesh_instance := node as MeshInstance3D
                if mesh_instance == null:
                    continue
                if profiled_enabled:
                    mesh_instance.visibility_range_begin = 0.0
                    mesh_instance.visibility_range_begin_margin = 0.0
                    mesh_instance.visibility_range_end = LOD_SWITCH_DISTANCE_M
                    mesh_instance.visibility_range_end_margin = LOD_TRANSITION_MARGIN_M
                    mesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
                else:
                    mesh_instance.visibility_range_end = 0.0
                    mesh_instance.visibility_range_end_margin = 0.0
                    mesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

    # The old cuboids remain only as a cheap far-distance fallback. Near the player
    # their visibility range excludes them, so there is no double body silhouette.
    for legacy_name: String in LEGACY_VISUAL_NAMES:
        var legacy := person.get_node_or_null(legacy_name)
        if not (legacy is GeometryInstance3D):
            continue
        var visual_instance := legacy as GeometryInstance3D
        visual_instance.visible = true
        if profiled_enabled and proxy != null:
            visual_instance.visibility_range_begin = LOD_SWITCH_DISTANCE_M
            visual_instance.visibility_range_begin_margin = LOD_TRANSITION_MARGIN_M
            visual_instance.visibility_range_end = 0.0
            visual_instance.visibility_range_end_margin = 0.0
            visual_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
        else:
            visual_instance.visibility_range_begin = 0.0
            visual_instance.visibility_range_begin_margin = 0.0
            visual_instance.visibility_range_end = 0.0
            visual_instance.visibility_range_end_margin = 0.0
            visual_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


func _deduplicate_proxy_materials(root: Node) -> int:
    var replaced := 0
    for node: Node in root.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := node as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null:
            continue
        var mesh := mesh_instance.mesh
        for surface_index: int in range(mesh.get_surface_count()):
            var material := mesh.surface_get_material(surface_index) as StandardMaterial3D
            if material == null:
                continue
            var key := _material_key(material)
            var shared := _shared_materials.get(key) as StandardMaterial3D
            if shared == null:
                _shared_materials[key] = material
                continue
            if shared == material:
                continue
            mesh.surface_set_material(surface_index, shared)
            replaced += 1
    _deduplicated_surfaces += replaced
    return replaced


func _material_key(material: StandardMaterial3D) -> String:
    return "%d|%.6f|%.6f|%s|%d|%.6f" % [
        material.albedo_color.to_rgba32(),
        material.roughness,
        material.metallic,
        str(material.emission_enabled),
        material.emission.to_rgba32(),
        material.emission_energy_multiplier,
    ]


func _seed_for_person(person: Node3D) -> int:
    var digits := ""
    for character: String in str(person.name):
        if character >= "0" and character <= "9":
            digits += character
    var index := int(digits) if not digits.is_empty() else posmod(int(person.get_instance_id()), EXPECTED_AMBIENT)
    return 81001 + index * 97


func _lod_counts_for_scene(scene: Node) -> Dictionary:
    var detailed_meshes := 0
    var legacy_visuals := 0
    if scene == null:
        return {"detailed_meshes": 0, "legacy_visuals": 0}
    var urban_life := scene.get_node_or_null("MidiUrbanLife")
    if urban_life == null:
        return {"detailed_meshes": 0, "legacy_visuals": 0}
    for child: Node in urban_life.get_children():
        if not child.is_in_group("ambient_pedestrian"):
            continue
        var person := child as Node3D
        if person == null:
            continue
        var proxy := person.get_node_or_null("ProfiledNpcProxy") as Node3D
        if proxy != null:
            var visual := proxy.get_node_or_null("VisualUpgrade") as Node3D
            if visual != null:
                detailed_meshes += visual.find_children("*", "MeshInstance3D", true, false).size()
        for legacy_name: String in LEGACY_VISUAL_NAMES:
            if person.get_node_or_null(legacy_name) is GeometryInstance3D:
                legacy_visuals += 1
    return {"detailed_meshes": detailed_meshes, "legacy_visuals": legacy_visuals}


func material_cache_stats() -> Dictionary:
    return {
        "entries": _shared_materials.size(),
        "surfaces_reused": _deduplicated_surfaces,
    }


func lod_stats() -> Dictionary:
    var counts := _lod_counts_for_scene(_find_scene_with_ambient_crowd())
    counts["switch_distance_m"] = LOD_SWITCH_DISTANCE_M
    counts["transition_margin_m"] = LOD_TRANSITION_MARGIN_M
    counts["detailed_near_legacy_far"] = true
    return counts


func truth_contract() -> Dictionary:
    return {
        "movement_owner": "midi_urban_life.gd legacy ambient path remains authoritative",
        "navigation_added": false,
        "simulation_proxy_disabled": true,
        "visual_pipeline": "NpcAgent + humanoid_visual.gd profiled NPC path",
        "visual_profile": VISUAL_PROFILE,
        "quality_runtime_compatible": true,
        "profiled_proxy_y_offset_m": PROXY_Y_OFFSET,
        "material_sharing": "exact-equivalent StandardMaterial3D reuse",
        "distance_lod": "profiled meshes near / existing legacy primitives beyond 90m with 10m self-fade margin",
        "ambient_density_target": TARGET_AMBIENT_DENSITY,
        "external_assets": 0,
    }
