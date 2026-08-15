extends Node

const HUMANOID_VISUAL_SCRIPT := preload("res://game/scripts/humanoid_visual.gd")
const EXPECTED_AMBIENT := 20
const MAX_DISCOVERY_FRAMES := 120
const PROXY_Y_OFFSET := 0.67
const LEGACY_VISUAL_NAMES := ["Torso", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Head", "Bag"]

var _bridged_scene_ids: Dictionary = {}

func _ready() -> void:
    call_deferred("_bridge_when_ready")

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
        return {"bridged": 0, "already": 0, "legacy_hidden": 0}
    var scene_id := scene.get_instance_id()
    var urban_life := scene.get_node_or_null("MidiUrbanLife")
    if urban_life == null:
        return {"bridged": 0, "already": 0, "legacy_hidden": 0}

    var bridged := 0
    var already := 0
    var legacy_hidden := 0
    for child: Node in urban_life.get_children():
        if not child.is_in_group("ambient_pedestrian"):
            continue
        var person := child as Node3D
        if person == null:
            continue
        if person.get_node_or_null("ProfiledNpcProxy") != null:
            already += 1
            continue
        legacy_hidden += _set_legacy_visuals(person, false)
        _attach_profiled_proxy(person, _seed_for_person(person))
        bridged += 1

    if bridged + already > 0:
        _bridged_scene_ids[scene_id] = true
    print("Midi ambient NPC visual bridge: bridged=%d already=%d legacy_hidden=%d" % [bridged, already, legacy_hidden])
    return {"bridged": bridged, "already": already, "legacy_hidden": legacy_hidden}

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
        _set_legacy_visuals(person, not enabled)
    return changed

func _attach_profiled_proxy(person: Node3D, seed_value: int) -> void:
    var proxy := NpcAgent.new()
    proxy.name = "ProfiledNpcProxy"
    proxy.role = NpcBehaviorModel.Role.CIVILIAN
    proxy.variation_seed = seed_value
    proxy.process_mode = Node.PROCESS_MODE_DISABLED
    proxy.collision_layer = 0
    proxy.collision_mask = 0
    proxy.position = Vector3(0.0, PROXY_Y_OFFSET, 0.0)

    var visual := Node3D.new()
    visual.name = "VisualUpgrade"
    visual.set_script(HUMANOID_VISUAL_SCRIPT)
    proxy.add_child(visual)
    person.add_child(proxy)

func _set_legacy_visuals(person: Node3D, visible_value: bool) -> int:
    var changed := 0
    for legacy_name: String in LEGACY_VISUAL_NAMES:
        var legacy := person.get_node_or_null(legacy_name)
        if legacy is VisualInstance3D:
            var visual := legacy as VisualInstance3D
            if visual.visible != visible_value:
                visual.visible = visible_value
                changed += 1
    return changed

func _seed_for_person(person: Node3D) -> int:
    var digits := ""
    for character: String in str(person.name):
        if character >= "0" and character <= "9":
            digits += character
    var index := int(digits) if not digits.is_empty() else posmod(int(person.get_instance_id()), EXPECTED_AMBIENT)
    return 81001 + index * 97

func truth_contract() -> Dictionary:
    return {
        "movement_owner": "midi_urban_life.gd legacy ambient path remains authoritative",
        "navigation_added": false,
        "simulation_proxy_disabled": true,
        "visual_pipeline": "NpcAgent + humanoid_visual.gd profiled NPC path",
        "external_assets": 0,
    }
