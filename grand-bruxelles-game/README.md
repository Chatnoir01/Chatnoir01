# Grand Bruxelles Game

Prototype de jeu d’action-aventure en monde ouvert, en vue à la troisième personne, inspiré de Bruxelles.

## Lien Web permanent

**Web Preview :**

https://htmlpreview.github.io/?https://github.com/Chatnoir01/Chatnoir01/blob/main/grand-bruxelles-game/web-preview/index.html

Cette URL reste la référence de contrôle du projet : la page `web-preview/index.html` est mise à jour au fil des grosses évolutions du prototype.

## Objectif

Reproduire progressivement une Bruxelles reconnaissable et jouable, sans copier GTA ni ses éléments protégés. Le projet vise une identité originale : circulation, piétons, conduite, exploration, missions, police, météo et cycle jour/nuit dans une ville construite à partir de données urbaines et de références visuelles légalement réutilisables.

## Vertical Slice 01

Zone pilote : **Gare du Midi → Anneessens → Bourse → Grand-Place**, avec extension possible vers Sablon / Mont des Arts.

Critère de réussite :

- apparaître dans le secteur réel de Bruxelles-Midi ;
- marcher/courir/sauter avec une caméra 3e personne ;
- entrer dans une voiture et conduire ;
- traverser plusieurs rues reconnaissables ;
- croiser du trafic et des piétons ;
- accomplir une mission simple ;
- conserver une fréquence d’image stable sur la machine cible.

## Moteur

- Godot 4.7.x stable
- GDScript pour le prototype
- rendu Forward+ pour le prototype desktop
- export Web futur en Compatibility/WebGL 2.0
- monde découpé en cellules / secteurs chargeables
- NavigationServer3D pour les piétons
- données OSM/Open Data comme aides à la reconstruction, pas comme rendu final brut

## Structure

```text
grand-bruxelles-game/
├── project.godot
├── web-preview/
│   └── index.html
├── data/
│   └── osm/
├── docs/
│   ├── GDD.md
│   ├── ROADMAP.md
│   ├── ARCHITECTURE.md
│   ├── DATA_PIPELINE.md
│   └── VERTICAL_SLICE_01.md
├── tools/
└── game/
    ├── main.tscn
    ├── scripts/
    └── tests/
```

## Principes de production

1. **Reconnaissable avant immense** : une petite zone fidèle vaut mieux qu’une carte géante vide.
2. **Gameplay avant décoration** : déplacement, conduite et streaming passent avant les détails secondaires.
3. **Landmarks à la main, masse urbaine procédurale/modulaire**.
4. **Chaque asset doit avoir une provenance et une licence traçables**.
5. **Aucun asset, logo, personnage, mission ou interface GTA n’est repris.**

## État

- [x] Vision du projet
- [x] Vertical Slice défini
- [x] Architecture initiale
- [x] Prototype joueur 3D initialisé
- [x] Tranche réelle OSM Bruxelles-Midi → centre intégrée
- [x] Véhicule jouable avec entrée/sortie
- [x] Première mission Midi → Anneessens → Bourse → Grand-Place
- [x] Mini-carte basée sur les routes OSM
- [x] Tests automatiques Godot pour scène, voiture et mission
- [x] Web Preview permanent
- [ ] Trafic
- [ ] Piétons
- [ ] Feux et intersections
- [ ] Premier landmark détaillé
- [ ] Build WebGL jouable publique
