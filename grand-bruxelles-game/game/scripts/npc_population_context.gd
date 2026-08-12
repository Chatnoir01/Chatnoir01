class_name NpcPopulationContext
extends RefCounted

# Contexts describe the built environment, not demographic groups. Values are
# simulation defaults and are intentionally overridable by source-backed map data.
enum UrbanContext {
	GENERIC,
	RESIDENTIAL,
	COMMERCIAL,
	TRANSIT_STOP,
	STATION,
	PARK,
	SCHOOL,
}

func civilian_density_factor(context: UrbanContext, hour: float, weather_factor: float = 1.0) -> float:
	var h: float = fposmod(hour, 24.0)
	var factor: float = 1.0
	match context:
		UrbanContext.RESIDENTIAL:
			factor = _residential_factor(h)
		UrbanContext.COMMERCIAL:
			factor = _commercial_factor(h)
		UrbanContext.TRANSIT_STOP:
			factor = _commute_peak_factor(h, 0.72, 1.34)
		UrbanContext.STATION:
			factor = _commute_peak_factor(h, 0.82, 1.58)
		UrbanContext.PARK:
			factor = _park_factor(h)
		UrbanContext.SCHOOL:
			factor = _school_factor(h)
		_:
			factor = _daytime_factor(h)
	return clampf(factor * clampf(weather_factor, 0.35, 1.15), 0.20, 1.80)

func police_presence_factor(context: UrbanContext, hour: float, event_pressure: float = 0.0) -> float:
	var h: float = fposmod(hour, 24.0)
	var routine: float = 0.72
	match context:
		UrbanContext.STATION:
			routine = 1.10
		UrbanContext.TRANSIT_STOP:
			routine = 0.88
		UrbanContext.COMMERCIAL:
			routine = 0.92 if h >= 10.0 and h < 21.0 else 0.68
		UrbanContext.PARK:
			routine = 0.76 if h >= 7.0 and h < 22.0 else 0.60
		UrbanContext.SCHOOL:
			routine = 0.84 if h >= 7.0 and h < 18.0 else 0.58
		UrbanContext.RESIDENTIAL:
			routine = 0.62
		_:
			routine = 0.72
	# Event pressure is the only escalation input; no neighbourhood is labelled
	# intrinsically dangerous or assigned a crime stereotype.
	return clampf(routine + clampf(event_pressure, 0.0, 1.0) * 0.90, 0.45, 1.85)

func budget_for(base_budget: int, factor: float) -> int:
	if base_budget <= 0:
		return 0
	return maxi(1, int(round(float(base_budget) * clampf(factor, 0.0, 2.0))))

func _commute_peak_factor(hour: float, off_peak: float, peak: float) -> float:
	if (hour >= 7.0 and hour < 9.5) or (hour >= 16.0 and hour < 19.0):
		return peak
	if hour >= 6.0 and hour < 23.0:
		return 1.0
	return off_peak

func _residential_factor(hour: float) -> float:
	if hour >= 6.5 and hour < 9.0:
		return 1.18
	if hour >= 17.0 and hour < 21.5:
		return 1.24
	if hour >= 0.0 and hour < 5.5:
		return 0.38
	return 0.78

func _commercial_factor(hour: float) -> float:
	if hour >= 11.0 and hour < 19.0:
		return 1.38
	if hour >= 8.0 and hour < 21.5:
		return 1.02
	return 0.34

func _park_factor(hour: float) -> float:
	if hour >= 10.0 and hour < 19.5:
		return 1.16
	if hour >= 7.0 and hour < 22.0:
		return 0.72
	return 0.22

func _school_factor(hour: float) -> float:
	if (hour >= 7.5 and hour < 9.0) or (hour >= 15.0 and hour < 17.0):
		return 1.44
	if hour >= 9.0 and hour < 15.0:
		return 0.72
	return 0.26

func _daytime_factor(hour: float) -> float:
	if hour >= 7.0 and hour < 22.0:
		return 1.0
	return 0.46
