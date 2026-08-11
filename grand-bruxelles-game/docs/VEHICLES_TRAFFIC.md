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

- `game/scripts/traffic_road_graph.gd`
  - transforme les voies OSM en arêtes dirigées ;
  - respecte `oneway=1`, `oneway=-1` et les rond-points ;
  - connecte les segments par leurs coordonnées communes ;
  - évite le demi-tour immédiat ;
  - privilégie la continuité de trajectoire tout en autorisant les changements de rue ;
  - génère des itinéraires multi-arêtes au lieu de limiter un véhicule à un seul way.

Sur le paquet actuel, le runtime produit :

- 588 nœuds ;
- 708 arêtes dirigées ;
- 63 intersections ;
- 53 intersections non signalées gérées par priorité de droite.

### Priorité de droite

`game/scripts/traffic_intersection_system.gd` arbitre les carrefours non couverts par un feu, un cédez-le-passage ou un STOP :

- détecte les intersections à partir des connexions géométriques du réseau ;
- exclut de la règle générique les carrefours ayant un contrôle OSM prioritaire proche ;
- enregistre les véhicules approchant d'un carrefour ;
- détecte un véhicule provenant de la droite relativement à la trajectoire courante ;
- force le véhicule non prioritaire à ralentir/attendre ;
- réserve brièvement la zone de carrefour au véhicule autorisé afin d'éviter deux entrées simultanées ;
- libère/expire automatiquement les réservations.

Le test synthétique vérifie aussi qu'un carrefour équipé d'un feu n'est pas simultanément traité comme priorité de droite.

### Trafic civil IA

- `game/scripts/traffic_manager.gd` reste le point d'entrée stable ;
- charge en priorité `data/traffic/manifest.json` et garde l'ancien runtime OSM comme fallback ;
- fait apparaître jusqu'à 12 véhicules autour du joueur ;
- recycle les véhicules terminés ou trop éloignés ;
- décale la trajectoire sur le côté droit de la chaussée ;
- applique un profil de vitesse pouvant changer en cours d'itinéraire ;
- tolère les métadonnées OSM absentes ou `null` (`lanes`, largeur, etc.) sans erreur runtime ;
- transmet aux véhicules les feux, contrôles et carrefours non signalés rencontrés sur leur route.

- `game/scripts/traffic_vehicle.gd`
  - accélération et freinage progressifs ;
  - orientation continue dans les courbes ;
  - freinage d'urgence devant obstacle ;
  - vitesse adaptée à chaque route traversée ;
  - respect des contrôles situés sur l'itinéraire ;
  - ralentissement et attente lorsque la priorité de droite l'exige.

### Feux et contrôles

- `game/scripts/traffic_control_system.gd`
  - rattache les contrôles OSM aux routes ;
  - regroupe les têtes de feux proches en carrefours ;
  - fournit des phases rouge/orange/vert sûres avec intervalles tout-rouge ;
  - les positions viennent d'OSM ; les phases sont simulées localement et ne prétendent pas reproduire une programmation temps réel de Bruxelles.

Comportement véhicule actuel :

- feu rouge : freinage jusqu'à l'arrêt ;
- orange : arrêt si la distance de freinage le permet, sinon poursuite ;
- cédez-le-passage : ralentissement fort avant le contrôle ;
- passage piéton : approche limitée à environ 20 km/h ;
- STOP : arrêt complet et temporisation ; le système est prêt mais le paquet actuel n'en contient aucun.

Le cédez-le-passage ne fait pas encore une résolution complète du créneau de trafic transversal et les passages piétons n'attendent pas encore un piéton réel : ces deux comportements seront raccordés aux prochaines couches IA.

### Véhicule joueur

- `game/scripts/vehicle_controller.gd`
  - entrée/sortie existante ;
  - vitesse instantanée en m/s et km/h ;
  - vitesse maximale exposée ;
  - frein à main sur `Espace`.

- `game/scripts/vehicle_hud.gd`
  - vitesse du véhicule conduit ;
  - nombre de véhicules civils IA actifs ;
  - valeur régionale de 30 km/h utilisée seulement lorsque la donnée routière ne fournit pas de limitation explicite.

### Pipeline OSM

`tools/fetch_osm_slice.py` récupère maintenant également :

- `highway=traffic_signals` ;
- `highway=stop` ;
- `highway=give_way` ;
- `highway=crossing` ;
- `railway=level_crossing`.

`tools/transform_osm_to_game.py` produit `grand-bruxelles-osm-v3` et conserve notamment :

- `oneway` ;
- `lanes`, `lanes_forward`, `lanes_backward` ;
- `maxspeed_kmh` ;
- `junction` ;
- `access`, `motor_vehicle` ;
- `surface` ;
- les contrôles de circulation et leurs positions.

`.github/workflows/grand-bruxelles-osm-traffic-preview.yml` peut construire un paquet OSM frais en artefact sans pousser sur `main`.

## Tests

La CI Godot 4.7.1 vérifie :

- conversion des métadonnées OSM et des contrôles ;
- intégrité/licence du paquet trafic actuel ;
- import du projet sans erreur de script ;
- chargement complet de la scène ;
- entrée/sortie et télémétrie du véhicule joueur ;
- graphe dirigé, intersection et sens unique synthétiques ;
- phasage de feux sans vert conflictuel dans le test synthétique ;
- arbitrage de priorité de droite et réservation de carrefour ;
- trafic civil multi-rues avec le paquet actuel ;
- conservation de la mission Midi → Grand-Place.

Le paquet actuel contient volontairement des champs OSM optionnels à `null`. Le smoke test charge directement ce paquet : il sert aussi de test de régression pour la tolérance aux métadonnées manquantes. Un échec réel `int(null)` a été reproduit par la CI puis corrigé avant validation verte.

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

- Les positions des feux sont réelles OSM mais leur cycle est simulé, pas synchronisé avec les contrôleurs physiques de Bruxelles.
- Le cédez-le-passage ralentit déjà, mais ne calcule pas encore complètement l'acceptation d'un créneau selon le trafic transversal.
- Les passages piétons ralentissent le véhicule, mais n'intègrent pas encore l'état d'un PNJ traversant.
- Les voitures IA sont encore des modèles greybox procéduraux.
- Scooters, STIB, accidents et garages ne sont pas encore actifs.
