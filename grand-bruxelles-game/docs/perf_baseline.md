# Perf Baseline (placeholder)

Ce fichier sera rempli automatiquement après l'exécution du benchmark (`tools/bench/benchmark_perf.gd`).

Quels tests exécuter :
- Spawn 100 véhicules (param `num_vehicles`) et 200 piétons (param `num_pedestrians`).
- Warmup : 3s, mesure : 10s (configurable dans le script)
- Mesures collectées : fps moyen, min, max

Comment exécuter localement :
1. Ouvrir Godot 4.7.x
2. Charger le projet `grand-bruxelles-game/project.godot`
3. Ouvrir la scène principale (`game/main.tscn`) ou une scène de test qui contient `tools/bench/benchmark_perf.gd` instancié.
4. Appeler `start_benchmark()` (via l'inspecteur ou par script)
5. Le rapport sera écrit dans `user://perf_baseline.txt` et commité si vous le poussez manuellement.

Checklist post-benchmark :
- [ ] Copier `user://perf_baseline.txt` → `docs/perf_baseline.md`
- [ ] Annoter hotspots (scripts, draw calls, physics)
- [ ] Plan d'optimisation priorisé
