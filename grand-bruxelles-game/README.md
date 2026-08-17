# Grand Bruxelles Game

Prototype de jeu d’action-aventure en monde ouvert, en vue à la troisième personne, inspiré de Bruxelles.

## Lien Web actuel — JOUABLE

**URL canonique Grand Bruxelles Game :**

https://chatnoir01.github.io/Chatnoir01/

Cette URL GitHub Pages est la porte d’entrée Web officielle. Elle sert directement la build Godot générée depuis `grand-bruxelles-game/web-preview/` (`index.html`, `index.js`, `index.wasm`, `index.pck`) et ne dépend pas de RawGitHack.

Le lien RawGitHack historique n’est plus la porte officielle. Il peut rester utile uniquement comme secours technique ponctuel, mais il peut être saturé ou répondre `429` et ne doit plus être communiqué comme URL joueur principale.

La build Web reste lourde : le couple `index.pck` + `index.wasm` dépasse actuellement 100 Mo avant les autres fichiers. Le workflow d’accès publie désormais la taille exacte, avertit au-delà de 90 MiB et bloque au-delà de 150 MiB. La réduction du premier téléchargement mobile est un lot ACCESS/performance séparé afin de ne pas modifier les ressources du jeu sans mesure.

La build Web comprend aussi des contrôles tactiles pour téléphone/tablette : directions, SAUT, RUN et E pour entrer/sortir du véhicule.

Sur clavier, `F5` sauvegarde la partie et `F9` la recharge. La mission crée aussi un autosave séparé après chaque checkpoint. Au prochain démarrage, cet autosave est repris automatiquement ; `N` permet alors de repartir de Bruxelles-Midi.

La première mission verse une récompense de 350 € à Grand-Place. Le portefeuille affiché sous la mini-carte est conservé par les quicksaves et autosaves.

Après cette arrivée, descendre à Grand-Place puis appuyer sur `F` lance **Retour Express**, une seconde mission vers la Bourse récompensée 120 €. Son avancement est lui aussi sauvegardé.

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
- rendu GL Compatibility pour desktop + WebGL 2.0
- export Web Godot automatisé
- publication GitHub Pages automatisée depuis le même build `web-preview/`
- monde découpé en cellules / secteurs chargeables
- NavigationServer3D prévu pour les piétons
- données OSM/Open Data comme aides à la reconstruction, pas comme rendu final brut

## Structure

```text
grand-bruxelles-game/
├── project.godot
├── export_presets.cfg
├── web-preview/
│   ├── index.html
│   ├── index.js
│   ├── index.pck
│   └── index.wasm
├── data/
│   └── osm/
├── docs/
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
- [x] Contrôles tactiles Web/mobile
- [x] Tests automatiques Godot pour scène, voiture et mission
- [x] Build Godot Web automatisée
- [x] Publication GitHub Pages intégrée au workflow Playable Link
- [x] Personnage riggé avec animations repos/marche/course
- [x] Trafic
- [x] Piétons
- [x] Feux et intersections
- [x] Premier landmark source-backed : Bourse
