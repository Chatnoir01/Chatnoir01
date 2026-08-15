extends Node

# Benchmark script to spawn vehicles and pedestrians and measure FPS
# Usage: add this Node to the main scene and call start_benchmark()

@export var num_vehicles: int = 100
@export var num_pedestrians: int = 200
@export var warmup_seconds: float = 3.0
@export var measure_seconds: float = 10.0
@export var vehicle_scene_path: String = "res://grand-bruxelles-game/game/vehicles/prototype_vehicle.tscn"
@export var pedestrian_scene_path: String = "res://grand-bruxelles-game/game/characters/pedestrian_prototype.tscn"

var _running := false
var _samples := []

func _ready():
    # allow manual start from the editor or call start_benchmark() programmatically
    pass

func start_benchmark():
    if _running:
        return
    _running = true
    _samples.clear()
    print("[benchmark] Starting warmup (%.2fs)" % warmup_seconds)
    call_deferred("_run_benchmark")

func _run_benchmark():
    # spawn assets
    _spawn_assets()
    # warmup
    var t := 0.0
    while t < warmup_seconds:
        t += Engine.get_physics_interpolation_fraction() # small wait
        yield(get_tree(), "idle_frame")
    print("[benchmark] Warmup complete — measuring for %.2fs" % measure_seconds)
    var end_time := OS.get_ticks_msec() + int(measure_seconds * 1000)
    while OS.get_ticks_msec() < end_time:
        _samples.append(Engine.get_frames_per_second())
        yield(get_tree(), "idle_frame")
    _running = false
    _report()

func _spawn_assets():
    var rng = RandomNumberGenerator.new()
    rng.randomize()
    # spawn vehicles
    var vehicle_scene: PackedScene = null
    if ResourceLoader.exists(vehicle_scene_path):
        vehicle_scene = load(vehicle_scene_path)
    for i in range(num_vehicles):
        var instance: Node3D = null
        if vehicle_scene:
            instance = vehicle_scene.instantiate()
        else:
            instance = MeshInstance3D.new()
            var box = BoxMesh.new()
            box.size = Vector3(1.8, 0.9, 4.0)
            instance.mesh = box
            var mat = StandardMaterial3D.new()
            mat.albedo_color = Color(rng.randf_range(0.1,0.9), rng.randf(), rng.randf())
            instance.material_override = mat
        instance.translation = Vector3(rng.randf_range(-200,200), 0.5, rng.randf_range(-200,200))
        get_tree().root.add_child(instance)
    # spawn pedestrians
    var ped_scene: PackedScene = null
    if ResourceLoader.exists(pedestrian_scene_path):
        ped_scene = load(pedestrian_scene_path)
    for i in range(num_pedestrians):
        var ped: Node3D = null
        if ped_scene:
            ped = ped_scene.instantiate()
        else:
            ped = MeshInstance3D.new()
            var capsule = CapsuleMesh.new()
            capsule.radius = 0.25
            capsule.height = 1.6
            ped.mesh = capsule
            var mat2 = StandardMaterial3D.new()
            mat2.albedo_color = Color(rng.randf_range(0.1,0.9), rng.randf(), rng.randf())
            ped.material_override = mat2
        ped.translation = Vector3(rng.randf_range(-200,200), 1.0, rng.randf_range(-200,200))
        get_tree().root.add_child(ped)

func _report():
    if _samples.empty():
        print("[benchmark] No samples collected")
        return
    var sum := 0.0
    for s in _samples:
        sum += s
    var avg := sum / _samples.size()
    var minv := _samples[0]
    var maxv := _samples[0]
    for s in _samples:
        minv = min(minv, s)
        maxv = max(maxv, s)
    var report := "Benchmark results:\n"
    report += " - vehicles: %d\n" % num_vehicles
    report += " - pedestrians: %d\n" % num_pedestrians
    report += " - avg_fps: %.2f\n" % avg
    report += " - min_fps: %.2f\n" % minv
    report += " - max_fps: %.2f\n" % maxv
    print(report)
    var path := "user://perf_baseline.txt"
    var file = File.new()
    if file.open(path, File.WRITE) == OK:
        file.store_string(report)
        file.close()
        print("[benchmark] Written report to %s" % path)
    else:
        print("[benchmark] Failed to write report to %s" % path)
