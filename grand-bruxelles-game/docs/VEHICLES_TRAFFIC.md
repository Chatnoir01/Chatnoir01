# Véhicules & trafic — Grand Bruxelles Game

## Portée

Ce module est responsable de la conduite, des véhicules civils, du trafic IA, des scooters/motos, des transports STIB côté circulation, des accidents et des garages.

La géométrie routière et les contrôles de circulation ne doivent pas être reconstruits au feeling. Le trafic utilise des routes et nœuds de contrôle dérivés d'OpenStreetMap ; les surfaces/empreintes officielles UrbIS restent prioritaires pour la géométrie exacte de Bruxelles.

## État actuel

### Paquet trafic Bruxelles

`data/traffic/manifest.json` décrit un paquet trafic séparé du décor afin qu'un rafraîchissement des données routières ne puisse pas casser les bâtiments ou les rails.

Paquet actuel du corridor Midi → Anneessens → Bourse → Grand-Place :

- 140 voies/ways OSM carrossables ;
- limitations réelles présentes à 20, 30 et 50 km/h ;
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

Sur le paquet actuel, le runtime produit 588 nœuds, 708 arêtes dirigées et 63 intersections détectées.

### Trafic civil IA

- `game/scripts/traffic_manager.gd` est l'entrée stable ;
- `game/scripts/traffic_manager_core.gd` contient l'implémentation robuste ;
- charge en priorité `data/traffic/manifest.json` et garde l'ancien runtime OSM comme fallback ;
- fait apparaître jusqu'à 12 véhicules autour du joueur ;
- recycle les véhicules terminés ou trop éloignés ;
- décale la trajectoire sur le côté droit de la chaussée ;
- applique un profil de vitesse pouvant changer en cours d'itinéraire ;
- tolère les métadonnées OSM absentes ou `null` (`lanes`, largeur, etc.) sans erreur runtime.

- `game/scripts/traffic_vehicle.gd`
  - accélération et freinage progressifs ;
  - orientation continue dans les courbes ;
  - freinage d'urgence devant obstacle ;
  - vitesse adaptée à chaque route traversée ;
  - réception des contrôles situés sur son itinéraire.

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

Les cédez-le-passage ne font pas encore une résolution complète des conflits entre flux et les passages piétons n'attendent pas encore un piéton réel : ces comportements seront raccordés à l'IA d'intersection et aux PNJ.

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
- trafic civil multi-rues avec paquet actuel ;
- conservation de la mission Midi → Grand-Place.

Le paquet actuel contient volontairement des champs OSM optionnels à `null`. Le smoke test charge directement ce paquet : il sert donc aussi de test de régression pour la tolérance aux métadonnées manquantes.

## Étapes suivantes

1. Résoudre les conflits de carrefour : priorité de droite, cédez-le-passage et réservation de zone d'intersection.
2. Ajouter la présence réelle de piétons aux passages piétons.
3. Ajouter densité de trafic selon l'heure et le quartier.
4. Ajouter scooters et motos avec gabarits/comportements distincts.
5. Ajouter bus et trams STIB sur tracés officiels.
6. Ajouter stationnement, livraisons et véhicules arrêtés.
7. Ajouter accidents, dégâts, dépanneuse et garages.
8. Remplacer les carrosseries greybox par des modèles originaux génériques et optimisés.

## Limites connues

- Les positions des feux sont réelles OSM mais leur cycle est simulé, pas synchronisé avec les contrôleurs physiques de Bruxelles.
- La priorité de droite et l'arbitrage dynamique entre véhicules à une intersection non signalée restent à implémenter.
- Le cédez-le-passage ralentit déjà, mais ne calcule pas encore l'acceptation d'un créneau selon le trafic transversal.
- Les passages piétons ralentissent le véhicule, mais n'intègrent pas encore l'état d'un PNJ traversant.
- Les voitures IA sont encore des modèles greybox procéduraux.
- Scooters, STIB, accidents et garages ne sont pas encore actifs.
