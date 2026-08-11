# Architecture technique — Grand Bruxelles Game

## 1. Objectifs

L’architecture doit permettre :

- un monde urbain extensible ;
- des secteurs chargeables indépendamment ;
- trafic et piétons nombreux sans simulation complète à longue distance ;
- remplacement progressif du greybox par des assets détaillés ;
- données de gameplay séparées des scènes visuelles ;
- tests isolés des systèmes critiques.

## 2. Organisation Godot

```text
game/
├── main.tscn
├── world/
│   ├── world_root.tscn
│   ├── cells/
│   ├── roads/
│   ├── buildings/
│   └── landmarks/
├── player/
├── vehicles/
├── traffic/
├── pedestrians/
├── missions/
├── ui/
├── audio/
└── scripts/
```

## 3. WorldRoot

Responsabilités :

- référence globale du monde ;
- horloge ;
- météo ;
- streaming ;
- registres des entités proches ;
- événements mondiaux.

Le WorldRoot ne doit pas contenir directement toute Bruxelles. Il orchestre des **WorldCell**.

## 4. WorldCell

Une cellule représente une petite portion urbaine.

Contenu possible :

- chaussées ;
- trottoirs ;
- bâtiments ;
- props ;
- zones de spawn ;
- NavigationRegion3D ;
- points de trafic ;
- audio zones.

États :

- unloaded ;
- preload ;
- active ;
- background ;
- unload pending.

### Distance cible initiale

Commencer avec des cellules de 150 à 300 m de côté, puis ajuster après profiling.

## 5. WorldStreamer

Le streamer maintient :

- cellule du joueur ;
- anneau proche chargé avec simulation complète ;
- anneau secondaire chargé visuellement ;
- cellules lointaines déchargées.

Le streaming doit être piloté par données et non par chemins codés en dur.

## 6. Coordonnées

Pour le premier vertical slice, garder l’origine du monde près du centre du secteur et utiliser les coordonnées 3D standards.

Si la carte dépasse ensuite plusieurs kilomètres dans toutes les directions, options :

1. découpage en zones recentrées ;
2. origin shifting ;
3. build Godot en large world coordinates seulement si les mesures montrent que c’est nécessaire.

## 7. PlayerController

Base : CharacterBody3D.

États :

- ON_FOOT ;
- ENTERING_VEHICLE ;
- IN_VEHICLE ;
- EXITING_VEHICLE ;
- DISABLED.

Le contrôleur joueur ne doit pas connaître les détails d’une voiture spécifique. Il parle à une interface de véhicule.

## 8. Véhicules

Chaque véhicule expose :

- seat transform ;
- enter/exit hooks ;
- speed ;
- throttle ;
- brake ;
- steering ;
- health/damage plus tard.

Prototype possible avec VehicleBody3D ou système custom selon les résultats de conduite. Le choix sera validé par test comparatif, pas par préférence théorique.

## 9. Trafic

Ne pas utiliser le navmesh piéton pour les voitures.

Structure :

- RoadGraph ;
- RoadSegment ;
- Lane ;
- Intersection ;
- TrafficSignal ;
- TrafficVehicleAgent.

Le réseau peut être généré partiellement depuis les données routières puis corrigé à la main.

## 10. Piétons

Navigation 3D par régions connectées.

Simulation à trois niveaux :

### Near

- modèle visible ;
- animation ;
- avoidance ;
- décisions fréquentes.

### Mid

- modèle LOD ;
- chemin simplifié ;
- décisions espacées.

### Far

- pas de Node3D individuel si possible ;
- état logique/statistique ou entité désactivée.

## 11. Entity Pooling

Pool obligatoire pour :

- trafic ;
- piétons ;
- effets ;
- petits props dynamiques ;
- projectiles éventuels.

Éviter les créations/destructions massives pendant la conduite.

## 12. MissionSystem

Mission data-driven :

```text
MissionDefinition
- id
- title
- steps[]
- rewards
- failure_conditions
```

Étapes possibles :

- GoTo ;
- Interact ;
- EnterVehicle ;
- DriveTo ;
- Wait ;
- EscapeArea ;
- Deliver.

## 13. SaveSystem

Pas nécessaire dans le tout premier prototype, mais prévoir des IDs stables dès maintenant.

Sauvegarder plus tard :

- mission progress ;
- position ;
- argent ;
- véhicules persistants ;
- options ;
- état du monde durable.

## 14. Rendering & performance

Stratégies prévues :

- LOD meshes ;
- occlusion culling dans les rues denses ;
- MultiMesh pour éléments répétés ;
- atlases/trimsheets ;
- ombres limitées par distance ;
- lights dynamiques limitées ;
- baked/static lighting étudié par zone ;
- impostors éventuels pour skyline lointaine.

## 15. Budgets provisoires par cellule active

À valider par profiling :

- 1 à 3 landmarks lourds maximum ;
- bâtiments secondaires modulaires ;
- 20 à 50 véhicules proches selon matériel ;
- 20 à 80 piétons visibles selon LOD ;
- draw calls et triangles suivis dans un fichier benchmark.

Aucun budget n’est considéré définitif sans mesure.

## 16. Sécurité / robustesse

- aucune clé API dans le dépôt ;
- données externes téléchargées par scripts hors runtime si possible ;
- validation des fichiers importés ;
- registre de licence obligatoire ;
- pas d’exécution de scripts provenant de datasets externes ;
- chemins de fichiers normalisés.

## 17. Tests

Scènes de test dédiées :

- test_player.tscn ;
- test_vehicle.tscn ;
- test_traffic_intersection.tscn ;
- test_pedestrian_density.tscn ;
- test_streaming.tscn.

Chaque bug gameplay important doit être reproductible dans une scène minimale avant correction quand c’est raisonnablement possible.
