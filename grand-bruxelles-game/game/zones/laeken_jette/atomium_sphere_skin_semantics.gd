extends RefCounted

## Presentation-only cue for the Atomium stainless sphere skin.
##
## Source contract:
## - official restoration/construction evidence resolves stainless-steel skin;
## - each sphere is described as 48 large spherical triangles;
## - each large panel is composed of 15 smaller triangles with false joints;
## - exact contemporary seam coordinates are NOT source-resolved.
##
## Therefore this helper may make triangular panel semantics readable, but it must
## never claim that its UV seam placement reproduces the real facade layout.

const TEXTURE_WIDTH := 768
const TEXTURE_HEIGHT := 384
const CELL_SIZE := 64
const MAJOR_LINE_WIDTH := 2
const MINOR_LINE_WIDTH := 1

static func apply_to(material: StandardMaterial3D) -> bool:
    if material == null:
        return false
    material.albedo_texture = _build_semantics_texture()
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    material.texture_repeat = true
    material.set_meta("atomium_panel_semantics_only", true)
    material.set_meta("atomium_exact_seam_layout", false)
    material.set_meta("atomium_skin_source", "official-restoration-and-construction")
    material.set_meta("atomium_large_triangle_semantics_per_sphere", 48)
    material.set_meta("atomium_small_triangle_semantics_per_large_panel", 15)
    material.set_meta("atomium_hublot_layout_resolved", false)
    return material.albedo_texture != null

static func _build_semantics_texture() -> ImageTexture:
    var image := Image.create(TEXTURE_WIDTH, TEXTURE_HEIGHT, true, Image.FORMAT_RGBA8)
    image.fill(Color(0.985, 0.99, 1.0, 1.0))

    # Broad triangular cue. The lattice is deliberately presentation-authored:
    # it communicates the sourced triangular cladding semantics without claiming
    # a surveyed seam coordinate layout.
    var major := Color(0.66, 0.69, 0.72, 1.0)
    var minor := Color(0.81, 0.83, 0.85, 1.0)

    for y: int in range(0, TEXTURE_HEIGHT + 1, CELL_SIZE):
        _draw_wrapped_line(image, Vector2i(0, mini(y, TEXTURE_HEIGHT - 1)), Vector2i(TEXTURE_WIDTH - 1, mini(y, TEXTURE_HEIGHT - 1)), major, MAJOR_LINE_WIDTH)

    for x: int in range(0, TEXTURE_WIDTH + 1, CELL_SIZE):
        _draw_wrapped_line(image, Vector2i(mini(x, TEXTURE_WIDTH - 1), 0), Vector2i(mini(x, TEXTURE_WIDTH - 1), TEXTURE_HEIGHT - 1), minor, MINOR_LINE_WIDTH)

    for row: int in range(TEXTURE_HEIGHT / CELL_SIZE):
        var y0 := row * CELL_SIZE
        var y1 := mini(y0 + CELL_SIZE, TEXTURE_HEIGHT - 1)
        for col: int in range(TEXTURE_WIDTH / CELL_SIZE):
            var x0 := col * CELL_SIZE
            var x1 := mini(x0 + CELL_SIZE, TEXTURE_WIDTH - 1)
            if (row + col) % 2 == 0:
                _draw_wrapped_line(image, Vector2i(x0, y0), Vector2i(x1, y1), major, MAJOR_LINE_WIDTH)
                _draw_wrapped_line(image, Vector2i(x0, (y0 + y1) / 2), Vector2i((x0 + x1) / 2, y1), minor, MINOR_LINE_WIDTH)
                _draw_wrapped_line(image, Vector2i((x0 + x1) / 2, y0), Vector2i(x1, (y0 + y1) / 2), minor, MINOR_LINE_WIDTH)
            else:
                _draw_wrapped_line(image, Vector2i(x1, y0), Vector2i(x0, y1), major, MAJOR_LINE_WIDTH)
                _draw_wrapped_line(image, Vector2i(x0, (y0 + y1) / 2), Vector2i((x0 + x1) / 2, y0), minor, MINOR_LINE_WIDTH)
                _draw_wrapped_line(image, Vector2i((x0 + x1) / 2, y1), Vector2i(x1, (y0 + y1) / 2), minor, MINOR_LINE_WIDTH)

    image.generate_mipmaps()
    return ImageTexture.create_from_image(image)

static func _draw_wrapped_line(image: Image, a: Vector2i, b: Vector2i, color: Color, width: int) -> void:
    var dx := b.x - a.x
    var dy := b.y - a.y
    var steps := maxi(abs(dx), abs(dy))
    if steps <= 0:
        _stamp(image, a.x, a.y, color, width)
        return
    for i: int in range(steps + 1):
        var t := float(i) / float(steps)
        var x := int(round(lerpf(float(a.x), float(b.x), t)))
        var y := int(round(lerpf(float(a.y), float(b.y), t)))
        _stamp(image, x, y, color, width)

static func _stamp(image: Image, x: int, y: int, color: Color, width: int) -> void:
    var radius := maxi(width - 1, 0)
    for oy: int in range(-radius, radius + 1):
        for ox: int in range(-radius, radius + 1):
            var px := posmod(x + ox, TEXTURE_WIDTH)
            var py := clampi(y + oy, 0, TEXTURE_HEIGHT - 1)
            image.set_pixel(px, py, color)
