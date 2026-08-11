# Véhicules & trafic — Grand Bruxelles Game

## Portée

Ce module est responsable de la conduite, des véhicules civils, du trafic IA, des scooters/motos, des transports STIB côté circulation, des accidents et des garages.

La géométrie routière et les contrôles de circulation ne doivent pas être reconstruits au feeling. Le trafic utilise des routes et nœuds de contrôle dérivés d'OpenStreetMap ; les surfaces/empreintes officielles UrbIS restent prioritaires pour la géométrie exacte de Bruxelles.

## État actuel

### Paquet trafic Bruxelles

`data/traffic/manifest.json` décrit un paquet trafic séparé du décor afin qu'un rafraîchissement des données routières ne puisse pas casser les bâtiments ou les rails.

Paquet actuel du corridor Midi → Anneessens → Bourse → Grand-Place :

- 140 voies/ways OSM carrossables ;
- limitations présentes à 20, 30 et 50 km/h ;
- sens uniques, nombre de bandes, rond-points et restrictions d'accès conservés ;
- 180 contrôles OSM ;
- 19 feux de circulation ;
- 14 cédez-le-passage ;
- 147 passages piétons ;
- 0 STOP dans la sélection actuelle.

Le paquet conserve `source` et `license=ODbL-1.0` dans le manifeste et dans chaque chunk.

### Graphe routier et intersections

`game/scripts/traffic_road_graph.gd` transforme les voies OSM en arêtes dirigées, respecte les sens uniques/rond-points, connecte les segments par leurs coordonnées communes, évite les demi-tours immédiats et génère des itinéraires multi-rues.

Sur le paquet actuel, le runtime produit 588 nœuds, 708 arêtes dirigées, 63 intersections et 53 intersections non signalées gérées par priorité de droite.

### Priorité de droite

`game/scripts/traffic_intersection_system.gd` arbitre les carrefours non couverts par un feu, un cédez-le-passage ou un STOP. Cette règle correspond au cadre routier belge actuellement applicable au projet ; elle devra être revue avec les règles du nouveau Code lorsqu'il entrera effectivement en vigueur.

Le système détecte les intersections, exclut les carrefours déjà contrôlés, enregistre les véhicules approchant, détecte le véhicule provenant de droite, force le véhicule non prioritaire à attendre et réserve brièvement la zone au véhicule autorisé afin d'éviter deux entrées simultanées.

### Trafic civil IA

`game/scripts/traffic_manager.gd` reste le point d'entrée stable. Il charge le paquet trafic actuel, garde l'ancien runtime OSM comme fallback, fait apparaître jusqu'à 12 véhicules, recycle les véhicules éloignés, applique la circulation à droite et transmet à chaque voiture son profil de vitesse, ses contrôles et ses intersections.

Le chargement tolère désormais les métadonnées OSM absentes ou `null` (`lanes`, largeur, etc.). Le bug réel `int(null)` observé en CI a été reproduit puis corrigé.

`game/scripts/traffic_vehicle.gd` gère accélération/freinage progressifs, courbes, freinage d'urgence, changements de limitation, feux, cédez-le-passage, passages piétons, STOP et priorité de droite.

### Feux et contrôles

`game/scripts/traffic_control_system.gd` rattache les contrôles OSM aux routes et regroupe les têtes de feux proches en carrefours. Les positions et types de contrôles viennent d'OSM ; les phases rouge/orange/vert sont simulées localement avec intervalles tout-rouge et ne prétendent pas reproduire la programmation réelle des contrôleurs de feux bruxellois.

Comportement actuel : rouge = arrêt, orange = arrêt si possible en sécurité, cédez-le-passage = fort ralentissement, passage piéton = approche autour de 20 km/h, STOP = arrêt complet avec temporisation. Le paquet actuel ne contient aucun STOP dans le corridor sélectionné.

Le cédez-le-passage ne fait pas encore une résolution complète du créneau de trafic transversal et les passages piétons n'attendent pas encore un piéton réel.

### Véhicule joueur

`game/scripts/vehicle_controller.gd` conserve l'entrée/sortie, expose la vitesse en m/s et km/h et dispose du frein à main sur `Espace`.

`game/scripts/vehicle_hud.gd` affiche la vitesse du véhicule conduit et le nombre de véhicules IA actifs. La valeur de 30 km/h n'est utilisée qu'en fallback lorsqu'aucune limitation explicite n'est disponible.

### Pipeline OSM

`tools/fetch_osm_slice.py` récupère les routes ainsi que `traffic_signals`, `stop`, `give_way`, `crossing` et `level_crossing`.

`tools/transform_osm_to_game.py` produit `grand-bruxelles-osm-v3` avec `oneway`, voies, `maxspeed_kmh`, `junction`, accès, surface et contrôles.

`.github/workflows/grand-bruxelles-osm-traffic-preview.yml` construit un paquet OSM frais en artefact sans pousser sur `main`.

## Tests

La CI Godot 4.7.1 vérifie la conversion OSM, l'intégrité/licence du paquet trafic, l'import Godot, le chargement de scène, le véhicule joueur, le graphe/sens uniques, les phases de feux, la priorité de droite/réservation de carrefour, le trafic civil multi-rues et la mission Midi → Grand-Place.

Le paquet actuel contient volontairement des champs OSM optionnels à `null` ; le smoke test le charge directement et sert donc de test de régression.

## Dernière validation mesurée

Godot 4.7.1 headless :

- `Grand Bruxelles traffic graph: 140 OSM ways, 588 nodes, 708 directed edges, 63 intersections, 53 right-priority, 180 controls (19 signals), 12 AI vehicles` ;
- `VEHICLE_SMOKE_OK` ;
- `TRAFFIC_GRAPH_OK` ;
- `TRAFFIC_CONTROL_OK` ;
- `TRAFFIC_SMOKE_OK` ;
- `MISSION_SMOKE_OK`.

## Étapes suivantes

1. Faire du cédez-le-passage une vraie acceptation de créneau selon le trafic transversal.
2. Ajouter la présence réelle de piétons aux passages piétons.
3. Ajouter densité de trafic selon l'heure et le quartier.
4. Ajouter scooters et motos avec gabarits/comportements distincts.
5. Ajouter bus et trams STIB sur tracés officiels.
6. Ajouter stationnement, livraisons et véhicules arrêtés.
7. Ajouter accidents, dégâts, dépanneuse et garages.
8. Remplacer les carrosseries greybox par des modèles originaux génériques et optimisés.

## Limites connues

- Les positions des feux sont issues d'OSM mais leur cycle est simulé.
- Le cédez-le-passage ne calcule pas encore complètement l'acceptation d'un créneau transversal.
- Les passages piétons ne sont pas encore couplés à l'état d'un PNJ traversant.
- Les véhicules IA sont encore des modèles greybox procéduraux.
- Scooters, STIB, accidents et garages ne sont pas encore actifs.
