# Roadmap de production

## Phase 0 — Fondation

Objectif : un projet Godot propre, versionné et mesurable.

- [x] vision / GDD ;
- [x] zone pilote ;
- [x] architecture initiale ;
- [x] politique sources/licences ;
- [x] scène de démarrage ;
- [x] contrôleur joueur prototype ;
- [ ] premier benchmark FPS ;
- [ ] convention de nommage assets ;
- [ ] CI de validation texte/imports.

**Sortie de phase** : le projet s’ouvre, lance la scène principale et permet de déplacer un personnage sur une scène test.

## Phase 1 — Greybox Bruxelles

Objectif : reproduire la géométrie urbaine essentielle sans détails.

- extraire le corridor OSM ;
- convertir les voies utiles en données de travail ;
- générer/poser chaussées et trottoirs ;
- reconstruire les îlots sous forme de volumes simples ;
- marquer les landmarks ;
- définir 5 à 8 cellules de streaming ;
- ajouter collisions ;
- tester les distances à pied et en voiture.

**Sortie de phase** : on reconnaît déjà le trajet Midi → centre par sa structure.

## Phase 2 — Character & Camera

- locomotion propre ;
- caméra orbitale avec collision ;
- saut ;
- pente/escaliers ;
- animation placeholder ;
- système d’interaction ;
- respawn debug.

**Sortie de phase** : le déplacement à pied est agréable pendant 10 minutes sans frustration majeure.

## Phase 3 — Véhicule

- véhicule prototype ;
- roues/adhérence ;
- accélération/frein ;
- entrée/sortie ;
- caméra véhicule ;
- collisions ;
- reset véhicule ;
- paramètres data-driven.

**Sortie de phase** : boucle complète marcher → entrer → conduire → sortir.

## Phase 4 — Streaming & performance

- WorldStreamer ;
- activation par cellules ;
- LOD meshes ;
- visibilité/occlusion ;
- MultiMesh pour répétitions ;
- pooling objets dynamiques ;
- benchmark CPU/GPU ;
- budgets par cellule.

**Sortie de phase** : traversée continue du corridor sans pause bloquante.

## Phase 5 — Ville vivante

### Trafic

- lanes ;
- intersections ;
- feux ;
- spawn/despawn ;
- évitement simple ;
- densité horaire.

### Piétons

- navmesh par cellule ;
- destinations ;
- spawn/despawn ;
- comportements idle/marche ;
- évitement proche ;
- LOD comportemental.

**Sortie de phase** : une rue animée avec trafic et piétons pendant une session prolongée.

## Phase 6 — Art pass Bruxelles

Priorité aux lieux iconiques :

1. Gare du Midi / parvis ;
2. Anneessens ;
3. Bourse ;
4. Grand-Place ;
5. liaison vers Sablon ou Mont des Arts.

Puis :

- kits de façades ;
- commerces fictifs inspirés du tissu réel ;
- mobilier urbain ;
- rails/tram ;
- signalisation ;
- végétation ;
- decals ;
- éclairage.

**Sortie de phase** : captures d’écran immédiatement identifiables comme Bruxelles.

## Phase 7 — Mission & gameplay systémique

- Mission 01 complète ;
- objectifs ;
- checkpoints ;
- dialogue placeholder ;
- récompense ;
- indice de vigilance ;
- réactions police V1 ;
- événement de rue simple.

**Sortie de phase** : vertical slice jouable de 10 à 20 minutes.

## Phase 8 — Polish

- animations ;
- sons ;
- UI ;
- bugs ;
- stabilité ;
- profiling ;
- options graphiques ;
- accessibilité ;
- crédits/licences.

## Backlog après Vertical Slice

- pluie ;
- cycle jour/nuit continu ;
- scooters ;
- tram ;
- intérieurs sélectionnés ;
- téléphone ;
- économie ;
- activités secondaires ;
- sauvegarde ;
- extension Marolles/Sablon ;
- extension canal / Sainte-Catherine ;
- extension Ixelles / Flagey.

## Discipline de développement

Chaque système passe par :

1. test reproductible / scène de test ;
2. implémentation minimale fonctionnelle ;
3. mesure performance ;
4. correction des cas limites ;
5. intégration dans le monde ;
6. documentation.
