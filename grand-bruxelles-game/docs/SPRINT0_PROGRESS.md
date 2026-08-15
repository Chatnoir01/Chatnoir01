# Sprint 0 Progress Log

Date de début : 2026-08-15
Branche : direction/visual-masterlist-start

Tâches accomplies
- [x] Création branche `direction/visual-masterlist-start`
- [x] Ajout ROADMAP_12_MONTHS.md, BACKLOG_SPRINTS.md, ONBOARDING.md
- [x] Ajout CI smoke & license check (.github/workflows/ci-build-preview.yml)
- [x] Ajout PoC shader triplanar (tools/facade_triplanar_shader.shader)
- [x] Ajout benchmark script (tools/bench/benchmark_perf.gd)
- [x] Ajout ServiceLocator prototype (game/scripts/service_locator.gd)
- [x] Ajout player_spawn.tscn placeholder (game/characters/player_spawn.tscn)
- [x] Ajout material_template.tres (game/materials/material_template.tres)
- [x] Ajout prop_instancer.gd (grand-bruxelles-game/tools/props/prop_instancer.gd)
- [x] Ajout autoload refactor plan (docs/AUTOLOAD_REFACTOR_PLAN.md)

Tâches en cours
- [ ] Import CC0 assets provisoires (player, cars, props) et intégration aux scènes
- [ ] Exécution benchmark et génération du rapport initial
- [ ] Application Material_template aux assets importés
- [ ] Configuration ReflectionProbe / SSAO de base et tests
- [ ] Instanciation initiale ~50 props via prop_instancer

Prochaines étapes (48h)
1. Importer assets provisoires CC0 et commiter
2. Exécuter benchmark, sauvegarder et commiter `docs/perf_baseline.md`
3. Pousser PR(s) vers `main` pour revue

Notes
- Si vous fournissez des GLB (player.glb, carA.glb, carB.glb, props/), uploadez-les dans `grand-bruxelles-game/assets/` et je les intégrerai immédiatement.
