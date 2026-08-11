# Véhicules & trafic — Grand Bruxelles Game

## Portée

Ce module est responsable de la conduite, des véhicules civils, du trafic IA, des scooters/motos, des transports STIB côté circulation, des accidents et des garages.

La géométrie routière ne doit pas être reconstruite au feeling. Le runtime utilise les polylignes routières du jeu dérivées d'OpenStreetMap et les surfaces/empreintes officielles UrbIS restent la référence prioritaire pour la géométrie exacte de Bruxelles.

## État actuel — première tranche jouable

### Trafic civil IA

- `game/scripts/traffic_manager.gd`
  - charge `data/osm/vertical_slice_01.game.json` ;
  - sélectionne uniquement les voies marquées comme carrossables ;
  - génère des voies de circulation décalées à droite de l'axe OSM ;
  - fait apparaître jusqu'à 12 véhicules autour du joueur ;
  - recycle les véhicules lorsque leur tronçon est terminé ou trop éloigné ;
  - applique la limitation OSM lorsqu'elle est connue ;
  - utilise 30 km/h comme valeur régionale par défaut en l'absence de donnée explicite ;
  - limite les voies `living_street` et `service` à 20 km/h au maximum par défaut.

- `game/scripts/traffic_vehicle.gd`
  - suit une polyline réelle ;
  - accélère et freine progressivement ;
  - adapte sa direction aux courbes ;
  - utilise un rayon frontal pour ralentir ou s'arrêter devant un obstacle ;
  - expose la vitesse, la limitation, la rue et l'identifiant OSM pour les tests et le futur HUD.

### Métadonnées routières

`tools/transform_osm_to_game.py` produit maintenant le format `grand-bruxelles-osm-v2` et conserve :

- `oneway` : sens unique OSM normalisé (`1`, `-1`, `0`) ;
- `lanes` ;
- `lanes_forward` ;
- `lanes_backward` ;
- `maxspeed_kmh` ;
- `junction` ;
- `access` ;
- `motor_vehicle` ;
- `surface`.

Les accès `no` et `private` ne sont plus considérés comme carrossables par le trafic civil.

Le fichier runtime actuellement commité reste compatible avec l'ancien schéma. Lors du prochain rafraîchissement OSM, les nouvelles métadonnées seront injectées automatiquement sans casser le jeu.

## Tests

La CI Godot 4.7.1 vérifie désormais :

- conversion correcte des métadonnées OSM de trafic ;
- import du projet sans erreur de script ;
- chargement de la scène avec le `TrafficManager` ;
- test fumée des véhicules civils ;
- conservation du test d'entrée/sortie du véhicule joueur ;
- conservation du test de mission Midi → Grand-Place.

## Fidélité Bruxelles

La règle de vitesse utilisée quand aucune limitation explicite n'est disponible est 30 km/h, conformément au régime général de la Région de Bruxelles-Capitale. Les axes signalés à une vitesse différente devront s'appuyer sur les valeurs OSM et, quand nécessaire, sur des données officielles complémentaires.

## Étapes suivantes

1. Construire le graphe d'intersections au lieu de limiter un véhicule à un seul `way` OSM.
2. Ajouter feux rouges, priorités, cédez-le-passage et passages piétons.
3. Ajouter densité de trafic selon l'heure et le quartier.
4. Ajouter scooters et motos avec gabarits/comportements distincts.
5. Ajouter bus et trams STIB sur tracés officiels.
6. Ajouter stationnement, livraisons et véhicules arrêtés.
7. Ajouter accidents, dégâts, dépanneuse et garages.
8. Remplacer les carrosseries greybox par des modèles originaux génériques et optimisés.

## Limites connues de cette tranche

- Le trafic suit actuellement un tronçon OSM à la fois ; il ne choisit pas encore une route complète à travers plusieurs intersections.
- Le fichier OSM commité avant cette évolution ne contient pas encore `oneway`/`maxspeed_kmh`; le runtime reste donc en mode de compatibilité jusqu'au prochain refresh des données.
- Les voitures IA sont des modèles greybox procéduraux et non des véhicules finaux.
- Les feux, la STIB, les accidents et les garages ne sont pas encore activés dans cette tranche.
