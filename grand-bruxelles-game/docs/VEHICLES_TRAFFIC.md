# Véhicules & trafic — Grand Bruxelles Game

## Portée

Ce module est responsable de la conduite, des véhicules civils, du trafic IA, des scooters/motos, des transports STIB côté circulation, des accidents et des garages.

La géométrie routière et les contrôles de circulation ne doivent pas être reconstruits au feeling. Le trafic utilise des routes et nœuds de contrôle dérivés d'OpenStreetMap ; les surfaces/empreintes officielles UrbIS restent prioritaires pour la géométrie exacte de Bruxelles.

## État actuel

### Paquet trafic Bruxelles

`data/traffic/manifest.json` décrit un paquet trafic séparé du décor afin qu'un rafraîchissement des données routières ne puisse pas casser les bâtiments ou les rails.

Paquet actuel du corridor Midi → Anneessens → Bourse → Grand-Place : 140 ways OSM carrossables, limitations 20/30/50 km/h, sens uniques/bandes/rond-points, 180 contrôles, 19 feux, 14 cédez-le-passage, 147 passages piétons et aucun STOP dans la sélection actuelle. Chaque chunk conserve la source et la licence ODbL-1.0.

### Graphe routier et intersections

`game/scripts/traffic_road_graph.gd` transforme les voies OSM en arêtes dirigées, respecte les sens uniques et rond-points, connecte les segments par leurs coordonnées communes, évite les demi-tours immédiats et génère des itinéraires multi-rues.

Mesure runtime actuelle : 588 nœuds, 708 arêtes dirigées, 63 intersections, dont 53 intersections non signalées gérées par priorité de droite.

### Priorité de droite

`game/scripts/traffic_intersection_system.gd` arbitre les carrefours non couverts par un feu, un cédez-le-passage ou un STOP. Cette règle correspond au cadre routier belge actuellement applicable au projet ; elle devra être revue avec les règles du nouveau Code lorsqu'il entrera effectivement en vigueur.

Le système détecte les intersections, exclut les carrefours déjà contrôlés, enregistre les véhicules approchant, détecte le véhicule provenant de droite, force le véhicule non prioritaire à attendre et réserve brièvement la zone au véhicule autorisé afin d'éviter deux entrées simultanées.

### Trafic civil IA

`game/scripts/traffic_manager.gd` est le point d'entrée stable. Il charge le paquet trafic actuel, garde l'ancien runtime OSM comme fallback, fait apparaître jusqu'à 12 véhicules, recycle les véhicules éloignés, applique la circulation à droite et transmet à chaque voiture son profil de vitesse, ses contrôles et ses intersections.

Le chargement tolère les métadonnées OSM absentes ou `null`. Le bug réel `int(null)` observé en CI a été reproduit puis corrigé avant validation verte.

`game/scripts/traffic_vehicle.gd` gère accélération/freinage progressifs, courbes, freinage d'urgence, changements de limitation, feux, cédez-le-passage, passages piétons, STOP et priorité de droite.

### Feux et contrôles

`game/scripts/traffic_control_system.gd` rattache les contrôles OSM aux routes et regroupe les têtes de feux proches en carrefours. Les positions/types viennent d'OSM ; les phases rouge/orange/vert sont simulées localement avec intervalles tout-rouge et ne prétendent pas reproduire la programmation réelle des contrôleurs bruxellois.

Comportement actuel : rouge = arrêt, orange = arrêt si la distance de freinage le permet, cédez-le-passage = fort ralentissement, passage piéton = approche autour de 20 km/h, STOP = arrêt complet avec temporisation. Le cédez-le-passage ne fait pas encore une résolution complète du créneau transversal et les passages piétons ne sont pas encore couplés à un PNJ réel.

### Véhicule joueur

`game/scripts/vehicle_controller.gd` conserve l'entrée/sortie, expose la vitesse en m/s et km/h et dispose du frein à main sur `Espace`. `game/scripts/vehicle_hud.gd` affiche la vitesse et le nombre de véhicules IA actifs.

### Pipeline OSM

`tools/fetch_osm_slice.py` récupère les routes ainsi que `traffic_signals`, `stop`, `give_way`, `crossing` et `level_crossing`. `tools/transform_osm_to_game.py` produit `grand-bruxelles-osm-v3` avec sens, voies, vitesses, accès, surfaces et contrôles. `.github/workflows/grand-bruxelles-osm-traffic-preview.yml` construit un paquet OSM frais en artefact sans pousser sur `main`.

## Tests

La CI Godot 4.7.1 vérifie conversion OSM, intégrité/licence du paquet, import Godot, scène complète, véhicule joueur, graphe/sens uniques, phases de feux, priorité de droite/réservation, trafic civil multi-rues et mission Midi → Grand-Place. Le paquet actuel contient volontairement des champs OSM optionnels à `null`, donc le smoke test sert aussi de régression pour les métadonnées manquantes.

Dernière validation :

- `Grand Bruxelles traffic graph: 140 OSM ways, 588 nodes, 708 directed edges, 63 intersections, 53 right-priority, 180 controls (19 signals), 12 AI vehicles` ;
- `VEHICLE_SMOKE_OK` ;
- `TRAFFIC_GRAPH_OK` ;
- `TRAFFIC_CONTROL_OK` ;
- `TRAFFIC_SMOKE_OK` ;
- `MISSION_SMOKE_OK`.

## Étapes suivantes

1. Acceptation de créneau réelle aux cédez-le-passage.
2. Piétons réels aux traversées.
3. Densité de trafic selon heure/quartier.
4. Scooters et motos.
5. Bus et trams STIB.
6. Stationnement/livraisons.
7. Accidents/dégâts/dépanneuse/garages.
8. Modèles véhicules finaux optimisés.
