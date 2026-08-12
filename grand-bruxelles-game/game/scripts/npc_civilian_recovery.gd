extends RefCounted
class_name NpcCivilianRecovery

var _seed: int = 1
var _started_at: float = 0.0
var _severity: float = 0.0
var _settle_seconds: float = 1.0
var _recovery_seconds: float = 4.0
var _active: bool = false

func configure(seed_value: int) -> void:
	_seed = seed_value if seed_value != 0 else 1
	_active = false

func begin_recovery(normalized_severity: float, started_at_seconds: float, context: String = "street") -> Dictionary:
	_severity = clampf(normalized_severity, 0.0, 1.0)
	_started_at = started_at_seconds
	var rng := RandomNumberGenerator.new()
	rng.seed = _mixed_seed(context)

	var context_settle_bias := 0.0
	match context:
		"transit_hub":
			context_settle_bias = 0.35
		"commercial_street":
			context_settle_bias = 0.15
		"residential_street":
			context_settle_bias = 0.45

	_settle_seconds = clampf(1.15 + _severity * 2.35 + context_settle_bias + rng.randf_range(0.0, 1.85), 1.0, 7.0)
	_recovery_seconds = clampf(4.2 + _severity * 8.8 + rng.randf_range(0.0, 4.6), 4.0, 22.0)
	_active = true
	return plan()

func plan() -> Dictionary:
	return {
		"settle_seconds": _settle_seconds,
		"recovery_seconds": _recovery_seconds,
		"severity": _severity,
	}

func sample(now_seconds: float, threat_active: bool) -> Dictionary:
	if not _active:
		return {
			"alertness": 0.0,
			"movement_scale": 1.0,
			"resume_routine": true,
			"progress": 1.0,
		}

	var elapsed := maxf(0.0, now_seconds - _started_at)
	if threat_active:
		# Ongoing danger cancels any snap-back toward routine. The caller can
		# continue sampling until the scene is genuinely calm.
		return {
			"alertness": maxf(0.7, _severity),
			"movement_scale": 0.35,
			"resume_routine": false,
			"progress": 0.0,
		}

	if elapsed < _settle_seconds:
		return {
			"alertness": lerpf(0.55, 0.9, _severity),
			"movement_scale": 0.42,
			"resume_routine": false,
			"progress": 0.0,
		}

	var progress := clampf((elapsed - _settle_seconds) / maxf(_recovery_seconds, 0.001), 0.0, 1.0)
	var smooth_progress := progress * progress * (3.0 - 2.0 * progress)
	var alertness := lerpf(lerpf(0.48, 0.82, _severity), 0.04, smooth_progress)
	var movement_scale := lerpf(0.48, 1.0, smooth_progress)
	var finished := progress >= 1.0
	if finished:
		_active = false
	return {
		"alertness": alertness,
		"movement_scale": movement_scale,
		"resume_routine": finished,
		"progress": progress,
	}

func is_active() -> bool:
	return _active

func _mixed_seed(context: String) -> int:
	var mixed: int = _seed * 1103515245 + _stable_hash(context) * 31 + 12345
	mixed = mixed ^ (mixed >> 16)
	return absi(mixed) + 1

func _stable_hash(value: String) -> int:
	var result: int = 2166136261
	for index in value.length():
		result = result ^ value.unicode_at(index)
		result = result * 16777619
	return result
