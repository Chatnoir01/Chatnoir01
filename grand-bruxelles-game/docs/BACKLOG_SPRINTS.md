# Backlog & Sprints — Phase initiale (Sprint 0 → Sprint 6)

Sprint 0 (7–14 jours) — Chauffe / quick wins
1. Benchmark de perf (script spawn 100 véhicules, 200 PNJ) — `tools/bench/benchmark_perf.gd` (créé). Résultat attendu: rapport `docs/perf_baseline.md`.
2. Réduire autoloads (documenter, déplacer 8 autoloads non critiques) — commit de refactor `direction/autoload-refactor`.
3. Remplacer Player placeholder par GLB riggé — importer `assets/characters/player_base.glb` (CC0 ou fourni) et hook animations.
4. Remplacer 2 voitures prototypes par GLB PBR (low poly) et appliquer `Material_template`.
5. Ajouter 50 props instanced (lampadaire, banc, corbeille) — assets CC0.
6. CI minimal : action qui valide `assets/LICENSE_REGISTRY.tsv` existence et exécute smoke build Web.

Sprint 1 (2 semaines)
1. Template PBR material (albedo/normal/roughness) et application aux roads & façades prioritaires.
2. ReflectionProbe(s) + SSAO configuration in WorldEnvironment.
3. Façade triplanar shader PoC + apply to a selection of OSM buildings.
4. Add impostor crowd prototype (billboard sprites) for sidewalks.

Sprint 2 (2–4 semaines)
1. Pipeline BlenderGIS import script: OSM→GLTF exporter (tools/blender_scripts/osm_import.py).
2. LOD generation script (Blender headless) + integration to streaming manager.
3. Automate LOD manifest per asset.
4. Start retargeting pipeline: Mixamo → Godot glTF.

Sprint 3 (4 semaines)
1. Procedural façade system: module to assemble façade tiles + UV atlas.
2. Apply decals and dirt layers on roads / façades.
3. Improve traffic manager hot loops; create micro‑benchmarks.

Sprint 4 (6–8 semaines)
1. Photogrammetry for 2 landmarks (collect photos, Meshroom pipeline, retopo in Blender).
2. Bake textures and normals; integrate into Godot GLTF.
3. Optimize streaming collision consistency.

Sprint 5 (8–12 semaines)
1. Full polish of slice: lighting, audio ambiances, particle systems for street atmospheres.
2. QA pass and perf tuning.
3. Release candidate build (PC Vulkan) + Web preview.

Tickets (format prêt à ouvrir)
- [TICKET] Perf: benchmark spawn script + baseline report
- [TICKET] Tech: autoload refactor (list autoloads → move to services)
- [TICKET] Art: import player GLB + setup animation tree
- [TICKET] Art: import 2 car models GLB + materials
- [TICKET] Tech: create PBR material template and apply
- [TICKET] Tech: add ReflectionProbes + configure WorldEnvironment
- [TICKET] Tech: facade triplanar shader PoC
- [TICKET] Art: add 200 street props instanced
- [TICKET] CI: add workflow license check + smokebuild

Pour créer ces tickets automatiquement (je peux ouvrir les Issues/PRs si vous confirmez).
