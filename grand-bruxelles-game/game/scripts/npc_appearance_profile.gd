class_name NpcAppearanceProfile
extends RefCounted

enum AgeBand {
	YOUNG_ADULT,
	ADULT,
	MATURE_ADULT,
	OLDER_ADULT,
}

enum WeatherContext {
	MILD,
	COOL,
	RAIN,
	COLD,
}

var age_band: AgeBand = AgeBand.ADULT
var stature_scale: float = 1.0
var shoulder_scale: float = 1.0
var clothing_base: StringName = &"casual"
var outer_layer: StringName = &"none"
var headwear: StringName = &"none"
var footwear: StringName = &"everyday"
var palette_family: StringName = &"neutral"

func configure(seed_value: int, role: NpcBehaviorModel.Role, weather: WeatherContext = WeatherContext.MILD) -> void:
	age_band = AgeBand(_index(seed_value, 13, 4))
	stature_scale = lerpf(0.92, 1.08, _unit(seed_value, 19))
	shoulder_scale = lerpf(0.92, 1.07, _unit(seed_value, 23))
	palette_family = _pick_palette(seed_value)
	footwear = _pick_footwear(seed_value)

	if role == NpcBehaviorModel.Role.POLICE:
		clothing_base = &"police_uniform"
		outer_layer = _police_outer_layer(weather)
		headwear = &"none"
		return

	clothing_base = _pick_civilian_base(seed_value)
	outer_layer = _pick_outer_layer(seed_value, weather)
	headwear = _pick_headwear(seed_value, weather)

func as_dictionary() -> Dictionary:
	return {
		"age_band": age_band,
		"stature_scale": stature_scale,
		"shoulder_scale": shoulder_scale,
		"clothing_base": clothing_base,
		"outer_layer": outer_layer,
		"headwear": headwear,
		"footwear": footwear,
		"palette_family": palette_family,
	}

func _pick_civilian_base(seed_value: int) -> StringName:
	var options: Array[StringName] = [
		&"casual",
		&"smart_casual",
		&"workwear",
		&"sport_casual",
		&"layered_casual",
	]
	return options[_index(seed_value, 31, options.size())]

func _pick_outer_layer(seed_value: int, weather: WeatherContext) -> StringName:
	var options: Array[StringName]
	match weather:
		WeatherContext.COLD:
			options = [&"winter_coat", &"puffer", &"wool_coat", &"parka"]
		WeatherContext.RAIN:
			options = [&"rain_jacket", &"hooded_coat", &"light_coat", &"waterproof_shell"]
		WeatherContext.COOL:
			options = [&"light_jacket", &"overshirt", &"coat", &"cardigan"]
		_:
			options = [&"none", &"light_jacket", &"overshirt", &"cardigan"]
	return options[_index(seed_value, 37, options.size())]

func _pick_headwear(seed_value: int, weather: WeatherContext) -> StringName:
	# Most civilians have no headwear; cold/rain contexts increase practical variants.
	var roll: float = _unit(seed_value, 41)
	if weather == WeatherContext.COLD and roll > 0.62:
		return &"beanie"
	if weather == WeatherContext.RAIN and roll > 0.78:
		return &"hood_up"
	if roll > 0.88:
		return &"cap"
	return &"none"

func _pick_footwear(seed_value: int) -> StringName:
	var options: Array[StringName] = [&"everyday", &"trainer", &"boot", &"smart"]
	return options[_index(seed_value, 47, options.size())]

func _pick_palette(seed_value: int) -> StringName:
	var options: Array[StringName] = [&"neutral", &"earth", &"muted_cool", &"muted_warm", &"dark"]
	return options[_index(seed_value, 53, options.size())]

func _police_outer_layer(weather: WeatherContext) -> StringName:
	match weather:
		WeatherContext.COLD:
			return &"police_cold_layer"
		WeatherContext.RAIN:
			return &"police_rain_layer"
		WeatherContext.COOL:
			return &"police_jacket"
		_:
			return &"police_standard"

func _index(seed_value: int, salt: int, size: int) -> int:
	return absi(seed_value * 1103515245 + salt * 12345) % size

func _unit(seed_value: int, salt: int) -> float:
	return float(_index(seed_value, salt, 10000)) / 9999.0
