extends SceneTree

const REVEAL_SCRIPT := preload("res://game/scripts/bourse_front_wall_reveal.gd")

func _fail(message: String) -> void:
    push_error("BOURSE_FRONT_DEPTH_GUARD_FAIL: %s" % message)
    quit(1)

func _initialize() -> void:
    var reveal := REVEAL_SCRIPT.new()
    if reveal == null:
        _fail("front reveal script did not instantiate")
        return
    var plane := Vector2.ZERO
    var toward_camera := Vector2(0.0, -1.0)
    var tangent := Vector2(1.0, 0.0)
    var behind_selected: bool = reveal._is_front_facing_triangle(
        Vector3(-1.0, 0.5, 4.0), Vector3(1.0, 0.5, 4.0), Vector3(-1.0, 2.5, 4.0),
        plane, toward_camera, tangent, -10.0, 10.0, 0.0, 5.0)
    if behind_selected:
        _fail("aligned wall behind the authoritative facade plane was selected for deletion")
        return
    var front_selected: bool = reveal._is_front_facing_triangle(
        Vector3(-1.0, 0.5, -0.2), Vector3(1.0, 0.5, -0.2), Vector3(-1.0, 2.5, -0.2),
        plane, toward_camera, tangent, -10.0, 10.0, 0.0, 5.0)
    if not front_selected:
        _fail("camera-side occluding wall stopped matching the existing reveal contract")
        return
    reveal.free()
    print("BOURSE_FRONT_DEPTH_GUARD_OK")
    quit(0)
