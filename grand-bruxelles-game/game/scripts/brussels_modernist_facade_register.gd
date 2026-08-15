extends RefCounted

# Reusable lightweight façade cadence for documented Brussels modernist frontage.
# It never invents openings: every instance is derived from an existing window
# MeshInstance3D supplied by the owning source-backed façade reconstruction.

const SUNSHADE_PROJECTION_M := 0.42
const SUNSHADE_THICKNESS_M := 0.09
const FRAME_RAIL_THICKNESS_M := 0.055
const TRANSOM_THICKNESS_M := 0.07
const SPANDREL_RELIEF_DEPTH_M := 0.08
const SPANDREL_RELIEF_HEIGHT_M := 0.16

static func decorate(block: Node3D, aluminium: Material, brick_relief: Material, add_projecting_spandrels: bool) -> Dictionary:
    var windows: Array[MeshInstance3D] = []
    for child in block.get_children():
        if child is MeshInstance3D and String(child.name).begins_with("Window_"):
            windows.append(child as MeshInstance3D)
    if windows.is_empty():
        return {"windows": 0, "sunshades": 0, "transoms": 0, "vertical_frames": 0, "bottom_rails": 0, "spandrels": 0}

    var first_box := windows[0].mesh as BoxMesh
    if first_box == null:
        return {"windows": 0, "sunshades": 0, "transoms": 0, "vertical_frames": 0, "bottom_rails": 0, "spandrels": 0}

    var root := Node3D.new()
    root.name = "ModernistFacadeRegister"
    root.set_meta("source_geometry_unchanged", true)
    root.set_meta("authored_dimensions_not_measured", true)
    root.set_meta("source_fact", "aluminium frames + fixed lower pane + top-hung transom + sunshade")
    block.add_child(root)

    var sunshade_positions: Array[Vector3] = []
    var transom_positions: Array[Vector3] = []
    var vertical_frame_positions: Array[Vector3] = []
    var bottom_rail_positions: Array[Vector3] = []
    var spandrel_positions: Array[Vector3] = []
    for window in windows:
        var box := window.mesh as BoxMesh
        if box == null:
            continue
        var depth := box.size.z
        var facade_x := window.position.x + 0.13
        sunshade_positions.append(Vector3(
            facade_x + SUNSHADE_PROJECTION_M * 0.5,
            window.position.y + box.size.y * 0.5 + 0.12,
            window.position.z
        ))
        transom_positions.append(Vector3(
            facade_x + 0.02,
            window.position.y + box.size.y * 0.22,
            window.position.z
        ))
        var jamb_offset := maxf(0.0, depth * 0.5 - FRAME_RAIL_THICKNESS_M * 0.5)
        vertical_frame_positions.append(Vector3(facade_x + 0.02, window.position.y, window.position.z - jamb_offset))
        vertical_frame_positions.append(Vector3(facade_x + 0.02, window.position.y, window.position.z + jamb_offset))
        bottom_rail_positions.append(Vector3(
            facade_x + 0.02,
            window.position.y - box.size.y * 0.5 + FRAME_RAIL_THICKNESS_M * 0.5,
            window.position.z
        ))
        if add_projecting_spandrels:
            spandrel_positions.append(Vector3(
                facade_x + SPANDREL_RELIEF_DEPTH_M * 0.5,
                window.position.y - box.size.y * 0.5 - 0.24,
                window.position.z
            ))

    var window_depth := first_box.size.z
    _add_multimesh(
        root,
        "Sunshades",
        Vector3(SUNSHADE_PROJECTION_M, SUNSHADE_THICKNESS_M, window_depth + 0.12),
        sunshade_positions,
        aluminium
    )
    _add_multimesh(
        root,
        "Transoms",
        Vector3(0.15, TRANSOM_THICKNESS_M, window_depth),
        transom_positions,
        aluminium
    )
    _add_multimesh(
        root,
        "VerticalFrames",
        Vector3(0.15, first_box.size.y, FRAME_RAIL_THICKNESS_M),
        vertical_frame_positions,
        aluminium
    )
    _add_multimesh(
        root,
        "BottomRails",
        Vector3(0.15, FRAME_RAIL_THICKNESS_M, window_depth),
        bottom_rail_positions,
        aluminium
    )
    if add_projecting_spandrels:
        _add_multimesh(
            root,
            "ProjectingBrickSpandrels",
            Vector3(SPANDREL_RELIEF_DEPTH_M, SPANDREL_RELIEF_HEIGHT_M, window_depth * 0.88),
            spandrel_positions,
            brick_relief
        )

    root.set_meta("window_count", windows.size())
    root.set_meta("sunshade_projection_m_authored", SUNSHADE_PROJECTION_M)
    root.set_meta("frame_rail_thickness_m_authored", FRAME_RAIL_THICKNESS_M)
    root.set_meta("transom_thickness_m_authored", TRANSOM_THICKNESS_M)
    root.set_meta("spandrel_relief_depth_m_authored", SPANDREL_RELIEF_DEPTH_M)
    return {
        "windows": windows.size(),
        "sunshades": sunshade_positions.size(),
        "transoms": transom_positions.size(),
        "vertical_frames": vertical_frame_positions.size(),
        "bottom_rails": bottom_rail_positions.size(),
        "spandrels": spandrel_positions.size()
    }

static func _add_multimesh(parent: Node3D, node_name: String, size: Vector3, positions: Array[Vector3], material: Material) -> MultiMeshInstance3D:
    var box := BoxMesh.new()
    box.size = size
    box.material = material
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.mesh = box
    multi.instance_count = positions.size()
    for index: int in range(positions.size()):
        multi.set_instance_transform(index, Transform3D(Basis.IDENTITY, positions[index]))
    var instance := MultiMeshInstance3D.new()
    instance.name = node_name
    instance.multimesh = multi
    parent.add_child(instance)
    return instance
