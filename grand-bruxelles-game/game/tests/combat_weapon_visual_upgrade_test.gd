extends SceneTree

const VISUAL_RUNTIME := preload("res://game/scripts/combat_weapon_visual_upgrade_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_WEAPON_VISUAL_UPGRADE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := VISUAL_RUNTIME.new()
    root.add_child(runtime)

    var expectations: Dictionary = {
        &"bx9": 7,
        &"cbr4": 10,
        &"sct8": 8,
    }
    for raw_weapon_id: Variant in expectations.keys():
        var weapon_id := StringName(raw_weapon_id)
        var holder := Node3D.new()
        holder.name = "CombatWeaponVisual_%s" % String(weapon_id)
        root.add_child(holder)
        var base_receiver := MeshInstance3D.new()
        base_receiver.name = "LegacyReceiver"
        holder.add_child(base_receiver)

        var built := int(runtime.call("upgrade_weapon_visual", holder, weapon_id))
        if built < int(expectations[weapon_id]):
            _fail("%s built only %d detail parts" % [weapon_id, built]); return
        if String(holder.get_meta("visual_upgrade_signature", "")) != VISUAL_RUNTIME.SIGNATURE:
            _fail("%s visual signature missing" % weapon_id); return
        if int(holder.get_meta("visual_upgrade_part_count", 0)) != built:
            _fail("%s part-count metadata drifted" % weapon_id); return
        var sway_root := holder.get_node_or_null(VISUAL_RUNTIME.SWAY_ROOT_NAME) as Node3D
        if sway_root == null:
            _fail("%s sway root missing" % weapon_id); return
        if sway_root.get_node_or_null("LegacyReceiver") == null:
            _fail("%s legacy receiver was not preserved under sway root" % weapon_id); return
        if sway_root.get_child_count() < built + 1:
            _fail("%s visible child count smaller than recipe" % weapon_id); return
        holder.queue_free()

    var unknown_holder := Node3D.new()
    root.add_child(unknown_holder)
    if int(runtime.call("upgrade_weapon_visual", unknown_holder, &"unknown")) != 0:
        _fail("unknown weapon unexpectedly produced a visual recipe"); return

    print("COMBAT_WEAPON_VISUAL_UPGRADE_OK: compact/carbine/scatter detail recipes + sway root green")
    quit(0)
