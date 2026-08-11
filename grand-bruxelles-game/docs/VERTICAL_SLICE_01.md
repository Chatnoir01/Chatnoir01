# Vertical Slice 01 — Midi → Grand-Place

## Objectif

Créer un morceau de jeu assez complet pour prouver simultanément :

- Bruxelles reconnaissable ;
- exploration à pied ;
- conduite ;
- trafic ;
- piétons ;
- streaming ;
- mission ;
- performance.

## Limites spatiales

### Axe principal

1. Gare du Midi
2. boulevard du Midi / secteur Porte de Hal selon raccord
3. Anneessens
4. boulevard Maurice Lemonnier
5. Bourse
6. centre piétonnier
7. Grand-Place

### Largeur de jeu

Ne pas construire seulement une route centrale. Prévoir plusieurs rues adjacentes permettant :

- détour ;
- poursuite ;
- choix d’itinéraire ;
- exploration ;
- masquage du streaming.

## Découpage initial en cellules

### Cell A — Midi

Contenu :

- sortie/parvis ;
- gare en landmark de fond et façades jouables proches ;
- taxis/bus/voitures fictifs ;
- forte densité piétonne.

### Cell B — Midi Nord

- axes routiers ;
- façades mixtes ;
- premier test de trafic ;
- zone tutoriel conduite.

### Cell C — Anneessens

- place ;
- station ;
- rues transversales ;
- densité urbaine élevée.

### Cell D — Lemonnier

- corridor ;
- rails/tram si retenus pour le slice ;
- commerces fictifs ;
- intersections.

### Cell E — Bourse

- landmark prioritaire ;
- grand espace piéton ;
- densité PNJ ;
- transition circulation → centre piéton.

### Cell F — Grand-Place

- landmark cluster ;
- rues étroites ;
- forte occlusion ;
- priorité fidélité visuelle.

## Mission de validation

### « Traversée »

**Étape 1** — Spawn près du Midi.

**Étape 2** — Rejoindre un véhicule de test.

**Étape 3** — Conduire vers Anneessens.

**Étape 4** — Stationner / sortir du véhicule.

**Étape 5** — Marcher jusqu’à un contact fictif.

**Étape 6** — Récupérer un objet de mission.

**Étape 7** — Rejoindre la Bourse par un itinéraire libre.

**Étape 8** — Fin de mission sur la zone Grand-Place.

Cette mission est volontairement simple : elle sert à tester toute la chaîne technique.

## Landmarks — ordre de production

### L0 — Blockout

Tous les landmarks sont d’abord représentés par un volume de silhouette.

### L1 — Priorité maximale

1. Bourse
2. Grand-Place — ensemble principal
3. Gare du Midi — silhouette et parvis

### L2 — Contexte

- Anneessens ;
- façades du boulevard Lemonnier ;
- principaux carrefours ;
- monuments visibles depuis l’axe.

## Photos requises

Pour chaque cellule :

- vue longitudinale de rue ;
- vues des intersections ;
- rez-de-chaussée ;
- corniches / hauteurs ;
- mobilier ;
- chaussée / trottoirs ;
- signalisation ;
- vues de nuit si possible.

## Données à collecter

- polygones bâtiments ;
- voirie ;
- sens de circulation ;
- emprises piétonnes ;
- rails ;
- espaces verts ;
- points d’intérêt ;
- topographie si utile.

## Budget art initial

### Landmark LOD0

Seulement visible à proximité.

### Landmark LOD1

Silhouette + grands volumes.

### Landmark LOD2

Volume simplifié pour skyline.

### Bâtiments ordinaires

Kit de modules répétés avec variation de matériaux et dimensions.

## Critères de reconnaissance

Test utilisateur rapide : montrer une capture sans texte pendant 5 secondes.

La zone est considérée suffisamment reconnaissable si une majorité de testeurs connaissant Bruxelles identifient :

- Bruxelles ;
- et idéalement le quartier ou landmark.

## Critères techniques de sortie

- aucun trou majeur de collision sur l’axe principal ;
- aucun chargement bloquant visible lors d’une traversée normale ;
- véhicule contrôlable ;
- joueur stable sur pentes/escaliers prévus ;
- trafic capable de franchir au moins 3 intersections ;
- piétons capables de traverser plusieurs régions de navigation ;
- mission complète sans soft-lock ;
- registre de licence à jour ;
- métriques FPS/CPU/GPU enregistrées.
