extends Node3D

# Prop instancer: looks for models under res://grand-bruxelles-game/assets/props/
# and instances them along simple grid or on provided Path3D nodes.

@export var props_folder: String = "res://grand-bruxelles-game/assets/props/"
@export var density_per_100m2: float = 0.2
@export var seed: int = 1337

func _ready():
    # automatic placement on startup for prototyping
    randomize()
    _instance_props()

func _instance_props():
    var dir = DirAccess.open(props_folder)
    if not dir:
        print("[props] Props folder not found: %s" % props_folder)
        return
    var rng = RandomNumberGenerator.new()
    rng.seed = seed
    var files := []
    dir.list_dir_begin(true, true)
    var fname = dir.get_next()
    while fname != "":
        if fname.to_lower().ends_with(".glb") or fname.to_lower().ends_with(".gltf"):
            files.append(props_folder + fname)
        fname = dir.get_next()
    dir.list_dir_end()
    if files.empty():
        print("[props] No GLB props found in %s — create assets or lower expectations." % props_folder)
        return
    # simple grid distribution around origin for demo
    var area_radius = 200
    var count = int((PI * area_radius * area_radius) * density_per_100m2 / 100.0)
    for i in range(count):
        var fpath = files[rng.randi_range(0, files.size() - 1)]
        var scene : PackedScene = null
        if ResourceLoader.exists(fpath):
            scene = load(fpath)
        var inst: Node3D = null
        if scene:
            inst = scene.instantiate()
        else:
            inst = MeshInstance3D.new()
            var box = BoxMesh.new()
            box.size = Vector3(0.5,1.0,0.5)
            inst.mesh = box
        inst.translation = Vector3(rng.randf_range(-area_radius, area_radius), 0.0, rng.randf_range(-area_radius, area_radius))
        add_child(inst)
    print("[props] Instanced %d props" % count)
