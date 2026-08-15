# Roadmap — 12 mois (Grand Bruxelles Game)

Objectif général
- Produire une Vertical Slice visuelle et jouable (Gare du Midi → Grand-Place) sur PC (Vulkan) en 9–12 mois, tout en gardant le Web comme preview.

Livrables principaux par trimestre

T0 (0–2 semaines) — Sprint d'initialisation
- Benchmark de base (perf spawn vehicles/peds). Script + rapport.
- Réduction autoloads (restructuration) — diminuer startup et état global.
- Branch: direction/visual-masterlist-start créée.
- Deliverable: build preview Web + rapport profil.

T1 (1–3 mois) — Fondations visuelles rapides (STRATÉGIE A)
- Remplacement des placeholders : joueur riggé GLB, 2 voitures GLB PBR.
- Template PBR material + reflection probes/SSAO config.
- 200 props instanced (lampadaires, bancs, panneaux).
- Shader façade triplanar expérimental sur bâtiments OSM extrudés.
- CI: build Web preview automatisée + licence check.
- Deliverable: Visual Vertical Slice (PC low→mid fidelity)

T2 (3–6 mois) — Pipeline et scalabilité (STRATÉGIE B)
- Pipeline Blender/BlenderGIS OSM→GLTF automatisé.
- LOD generation automatisée et integration au streaming.
- Façade system modulaire (tiles + atlas + procedural masks).
- Crowd impostors + retargeted Mixamo animations pour PNJ.
- Profiling + extraction hot paths (préparer GDNative/C# si nécessaire).
- Deliverable: zone cohérente avec landmarks, perf budgets tenus.

T3 (6–9 mois) — Polissage et landmarks
- Photogrammetry / manual modelling pour 4 landmarks (Grand-Place, Bourse, Midi, Anneessens).
- Baked lighting sur landmarks, reflection probes tighten.
- Police & IA : finalisation des comportements critiques (poursuites, patrouilles).
- Deliverable: Slice visuelle haute qualité, tests utilisateurs.

T4 (9–12 mois) — Stabilisation et pré‑release
- QA, perf tuning, retexturing, audio ambiances, localisations.
- Préparation d’une build PC (Vulkan) et une version Web réduite.
- Politique licences, manifest d’assets complet.
- Deliverable: Release candidate vertical slice.

Risques & décisions clés
- Ne pas photogrammétrier toute la ville — seulement landmarks.
- Prioriser PC Vulkan pour rendu final; garder Web pour preview.
- Refactoriser scripts monolithiques avant d'étendre la population massive.

Mesures de succès (KPIs)
- Vertical Slice livré (PC Vulkan) < 12 mois.
- FPS cible stable (60 sur target mid‑range machine) pour slice.
- Licence registry complète et CI vérifiée.

Contact & next step
- Voir BACKLOG_SPRINTS.md pour les tickets sprint par sprint
