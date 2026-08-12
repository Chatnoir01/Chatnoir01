extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	var a := NpcAppearanceProfile.new()
	var b := NpcAppearanceProfile.new()
	a.configure(1234, NpcBehaviorModel.Role.CIVILIAN, NpcAppearanceProfile.WeatherContext.RAIN)
	b.configure(1234, NpcBehaviorModel.Role.CIVILIAN, NpcAppearanceProfile.WeatherContext.RAIN)
	if a.as_dictionary() != b.as_dictionary():
		failures.append("same seed and context must be deterministic")

	var unique_profiles := {}
	for seed in range(20, 40):
		var profile := NpcAppearanceProfile.new()
		profile.configure(seed, NpcBehaviorModel.Role.CIVILIAN, NpcAppearanceProfile.WeatherContext.COOL)
		var key := "%s|%s|%s|%s|%.3f" % [profile.clothing_base, profile.outer_layer, profile.footwear, profile.palette_family, profile.stature_scale]
		unique_profiles[key] = true
	if unique_profiles.size() < 8:
		failures.append("appearance generator should produce substantial variation across seeds")

	var police := NpcAppearanceProfile.new()
	police.configure(77, NpcBehaviorModel.Role.POLICE, NpcAppearanceProfile.WeatherContext.COLD)
	if police.clothing_base != &"police_uniform":
		failures.append("police role must keep police uniform base")
	if police.outer_layer != &"police_cold_layer":
		failures.append("police cold-weather layer should be context appropriate")

	var civilian_cold := NpcAppearanceProfile.new()
	civilian_cold.configure(77, NpcBehaviorModel.Role.CIVILIAN, NpcAppearanceProfile.WeatherContext.COLD)
	if civilian_cold.outer_layer == &"none":
		failures.append("cold-weather civilian profile should always carry an outer layer")
	if civilian_cold.stature_scale < 0.92 or civilian_cold.stature_scale > 1.08:
		failures.append("stature variation is outside plausible bounded range")

	if failures.is_empty():
		print("NPC_APPEARANCE_PROFILE_OK")
		quit(0)
	else:
		for failure in failures:
			push_error("NPC_APPEARANCE_PROFILE_FAIL: %s" % failure)
		quit(1)
