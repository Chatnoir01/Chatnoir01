extends Node3D

const BILINGUAL_DECAL: Texture2D = preload("res://assets/police/decals/police_bilingual_decal.png")
const BLUE_STRIPES: Texture2D = preload("res://assets/police/decals/police_blue_stripes.png")
const REAR_CHEVRONS: Texture2D = preload("res://assets/police/decals/police_rear_chevrons.png")

@export var start_active: bool = false
@export_range(0.04, 0.3, 0.005) var flash_interval: float = 0.085

@onready var left_flash_group: Node3D = $LeftFlashGroup
@onready var right_flash_group: Node3D = $RightFlashGroup

var _lights_active: bool = false
var _timer: float = 0.0
var _phase: int = 0


func _ready() -> void:
    _install_vehicle_decals()
    set_emergency_lights(start_active)


func _process(delta: float) -> void:
    if not _lights_active:
        return
    _timer += delta
    if _timer < flash_interval:
        return
    _timer = 0.0
    _phase = (_phase + 1) % 8
    _apply_flash_phase()


func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventKey):
        return
    if not event.pressed or event.echo or event.keycode != KEY_G:
        return
    var vehicle: Node = get_parent()
    if vehicle != null and vehicle.has_method("has_driver") and bool(vehicle.call("has_driver")):
        set_emergency_lights(not _lights_active)
        get_viewport().set_input_as_handled()


func set_emergency_lights(enabled: bool) -> void:
    _lights_active = enabled
    _timer = 0.0
    _phase = 0
    if enabled:
        _apply_flash_phase()
    else:
        left_flash_group.visible = false
        right_flash_group.visible = false


func are_emergency_lights_active() -> bool:
    return _lights_active


func _apply_flash_phase() -> void:
    # Double-pulse left, short gap, double-pulse right. This reads much closer
    # to a modern LED lightbar than a simple alternating on/off blink.
    match _phase:
        0, 2:
            left_flash_group.visible = true
            right_flash_group.visible = false
        1, 3, 5, 7:
            left_flash_group.visible = false
            right_flash_group.visible = false
        4, 6:
            left_flash_group.visible = false
            right_flash_group.visible = true


func _install_vehicle_decals() -> void:
    var vehicle: Node = get_parent()
    if vehicle == null:
        return

    var layer := Node3D.new()
    layer.name = "RuntimeDecals"
    vehicle.add_child.call_deferred(layer)

    if vehicle.is_in_group("police_marked"):
        # Keep markings in real-world metre ranges independent of texture resolution.
        _add_side_sprite(layer, "BilingualLeft", BILINGUAL_DECAL, Vector3(-0.984, 0.72, -0.32), 90.0, 0.0034)
        _add_side_sprite(layer, "BilingualRight", BILINGUAL_DECAL, Vector3(0.984, 0.72, -0.32), -90.0, 0.0034)
        _add_side_sprite(layer, "StripeLeft", BLUE_STRIPES, Vector3(-0.986, 0.47, 0.42), 90.0, 0.0062)
        _add_side_sprite(layer, "StripeRight", BLUE_STRIPES, Vector3(0.986, 0.47, 0.42), -90.0, 0.0062, true)
        _add_rear_sprite(layer, "RearChevrons", REAR_CHEVRONS, Vector3(0.0, 0.55, 2.306), 0.1125)
    elif vehicle.is_in_group("police_bab"):
        _add_side_sprite(layer, "BilingualLeft", BILINGUAL_DECAL, Vector3(-1.086, 1.18, -0.55), 90.0, 0.0040)
        _add_side_sprite(layer, "BilingualRight", BILINGUAL_DECAL, Vector3(1.086, 1.18, -0.55), -90.0, 0.0040)
        _add_side_sprite(layer, "StripeLeft", BLUE_STRIPES, Vector3(-1.088, 0.82, 0.48), 90.0, 0.0074)
        _add_side_sprite(layer, "StripeRight", BLUE_STRIPES, Vector3(1.088, 0.82, 0.48), -90.0, 0.0074, true)
        _add_rear_sprite(layer, "RearChevrons", REAR_CHEVRONS, Vector3(0.0, 0.86, 2.742), 0.1250)


func _make_sprite(name_value: String, texture_value: Texture2D, pixel_size_value: float) -> Sprite3D:
    var sprite := Sprite3D.new()
    sprite.name = name_value
    sprite.texture = texture_value
    sprite.pixel_size = pixel_size_value
    sprite.shaded = true
    sprite.no_depth_test = false
    return sprite


func _add_side_sprite(
    parent: Node3D,
    name_value: String,
    texture_value: Texture2D,
    position_value: Vector3,
    yaw_degrees: float,
    pixel_size_value: float,
    flip_horizontal: bool = false
) -> void:
    var sprite := _make_sprite(name_value, texture_value, pixel_size_value)
    sprite.position = position_value
    sprite.rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
    sprite.flip_h = flip_horizontal
    parent.add_child(sprite)


func _add_rear_sprite(
    parent: Node3D,
    name_value: String,
    texture_value: Texture2D,
    position_value: Vector3,
    pixel_size_value: float
) -> void:
    var sprite := _make_sprite(name_value, texture_value, pixel_size_value)
    sprite.position = position_value
    sprite.rotation_degrees = Vector3(0.0, 180.0, 0.0)
    parent.add_child(sprite)
