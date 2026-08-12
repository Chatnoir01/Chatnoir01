extends SceneTree

func _init() -> void:
	var context := NpcPopulationContext.new()
	var failures: Array[String] = []

	var station_peak := context.civilian_density_factor(NpcPopulationContext.UrbanContext.STATION, 8.0)
	var station_night := context.civilian_density_factor(NpcPopulationContext.UrbanContext.STATION, 2.0)
	if station_peak <= station_night:
		failures.append("station commute peak should exceed overnight density")

	var school_arrival := context.civilian_density_factor(NpcPopulationContext.UrbanContext.SCHOOL, 8.0)
	var school_night := context.civilian_density_factor(NpcPopulationContext.UrbanContext.SCHOOL, 23.0)
	if school_arrival <= school_night:
		failures.append("school arrival window should exceed late-night density")

	var dry_park := context.civilian_density_factor(NpcPopulationContext.UrbanContext.PARK, 14.0, 1.0)
	var poor_weather_park := context.civilian_density_factor(NpcPopulationContext.UrbanContext.PARK, 14.0, 0.5)
	if poor_weather_park >= dry_park:
		failures.append("weather attenuation should reduce outdoor density")

	var calm_station_police := context.police_presence_factor(NpcPopulationContext.UrbanContext.STATION, 12.0, 0.0)
	var incident_station_police := context.police_presence_factor(NpcPopulationContext.UrbanContext.STATION, 12.0, 0.8)
	if incident_station_police <= calm_station_police:
		failures.append("event pressure should raise police presence without neighbourhood stereotyping")

	if context.budget_for(48, station_peak) <= context.budget_for(48, station_night):
		failures.append("budget conversion should preserve density ordering")
	if context.budget_for(0, 1.5) != 0:
		failures.append("zero budget must remain zero")

	if failures.is_empty():
		print("NPC_POPULATION_CONTEXT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error("NPC_POPULATION_CONTEXT_FAIL: %s" % failure)
		quit(1)
