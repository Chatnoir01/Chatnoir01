# Véhicules & trafic — Grand Bruxelles Game

## Portée

Cette branche développe la circulation et les services automobiles du jeu : véhicule joueur, trafic civil IA, scooters/motos, carrefours, piétons aux traversées, stationnement, livraisons, dégâts, dépannage, garages et pipeline STIB.

La géométrie de Bruxelles n'est jamais inventée : routes et contrôles proviennent d'OpenStreetMap, tandis qu'UrbIS reste prioritaire pour la géométrie exacte lorsque disponible. Les occupations temporaires (voitures garées, livraisons, densité) sont explicitement des simulations de gameplay construites sur cette géométrie réelle.

## Réseau routier actuel

Corridor Midi → Anneessens → Bourse → Grand-Place :

- 140 ways OSM carrossables ;
- 588 nœuds de graphe ;
- 708 arêtes dirigées ;
- 63 intersections ;
- 53 intersections non signalées gérées par priorité de droite ;
- 180 contrôles OSM : 19 feux, 14 cédez-le-passage, 147 passages piétons ;
- limitations présentes à 20, 30 et 50 km/h ;
- sens uniques, bandes, rond-points et restrictions d'accès conservés ;
- source/licence ODbL-1.0 conservées dans le paquet trafic.

`traffic_road_graph.gd`, `traffic_control_system.gd` et `traffic_intersection_system.gd` assurent itinéraires multi-rues, sens uniques, absence de demi-tour immédiat, feux avec phases sûres, priorité de droite, réservation de zone de carrefour et acceptation réelle de créneau aux cédez-le-passage.

Le bug réel `lanes = null -> int(null)` détecté par la CI a été reproduit, corrigé avec conversions sûres puis couvert par régression.

## Trafic civil mixte

`traffic_manager.gd` active aujourd'hui `traffic_manager_core_v7.gd`.

Le trafic peut créer :

- voitures ;
- scooters ;
- motos.

Chaque catégorie a son propre gabarit, sa collision et son profil d'accélération/freinage/direction, tout en utilisant les mêmes règles de circulation. Le test déterministe sur 80 créations produit 39 voitures, 23 scooters et 18 motos.

La densité varie selon une horloge de simulation et la capacité réelle des routes OSM proches du joueur. Cette densité est une règle de gameplay, pas une mesure de trafic temps réel.

## Passages piétons

`traffic_crossing_system.gd` rattache les contrôles `highway=crossing` à la chaussée et calcule une trajectoire perpendiculaire à la route. Sur les données courantes :

- 124 passages sur 147 sont géométriquement raccordés de façon fiable ;
- 108 sont non signalés ;
- les 23 non raccordés restent exclus plutôt que repositionnés artificiellement.

Les voitures ne ralentissent plus à un passage vide. Un piéton en attente ou déjà engagé provoque le freinage puis l'arrêt avant la traversée ; la circulation reprend dès que le passage est libéré.

Les agents légers `traffic_crossing_pedestrian.gd` servent à rendre le comportement immédiatement jouable et testable. Leur API (`register_waiting`, `begin_crossing`, `clear_pedestrian`) est prévue pour être appelée par le système PNJ général.

## Stationnement et livraisons

`traffic_parking_model.gd` génère des emplacements de stationnement simulés le long de rues OSM compatibles. L'occupation n'est pas présentée comme une observation réelle de véhicules stationnés.

Mesure actuelle : 188 emplacements sûrs. Les candidats :

- excluent les axes `primary` ;
- gardent 8 m de marge aux extrémités des segments ;
- gardent au moins 12 m des feux, STOP, cédez-le-passage et passages piétons ;
- utilisent la largeur OSM de la chaussée pour placer le véhicule au bord de voirie.

Le runtime par défaut peut afficher jusqu'à 8 voitures garées autour du joueur.

`traffic_manager_core_v7.gd` ajoute aussi jusqu'à 2 fourgons de livraison temporaires. Chaque fourgon réserve un emplacement unique, possède une collision réelle, reste 12 à 24 secondes puis libère sa place. Une voiture garée et un fourgon ne peuvent pas utiliser le même candidat simultanément.

## Dégâts, accidents et récupération

`vehicle_damage_model.gd` est branché au véhicule joueur :

- choc inférieur à 12 km/h : pas de dégâts mécaniques ;
- choc important : dégâts carrosserie + mécanique ;
- dégâts mécaniques : baisse progressive des performances ;
- impacts sévères répétés : immobilisation ;
- réparation complète : retour à 100 %.

`vehicle_recovery_model.gd` ajoute le dépannage routier : touche `R` quand le véhicule est immobilisé, devis proportionnel aux dégâts, délai, blocage pendant l'intervention, retour au dernier emplacement sûr et réparation de dépannage partielle.

Le HUD affiche vitesse, santé, immobilisation, dépanneuse, devis et trafic mixte.

## Services automobiles OSM

Le pipeline OSM récupère uniquement les lieux explicitement balisés `shop=car_repair`, `shop=tyres` ou `amenity=car_repair`. Un simple concessionnaire n'est pas transformé en garage.

Le refresh OSM courant a trouvé exactement deux services :

- **H.R.Z Services** — garage complet — `[-1053.371, -118.477]` ;
- **Expres Pneu** — service pneus — `[-730.348, -273.968]`.

H.R.Z Services est actuellement hors des limites de la tranche jouable chargée ; il reste donc catalogué mais non interactif. Expres Pneu est dans la tranche et reste traité comme service pneus, jamais comme faux garage mécanique.

`vehicle_service_system.gd` autorise une réparation complète uniquement si un vrai garage complet est chargé, proche, que le véhicule est arrêté et endommagé. Dans la tranche actuelle, le nombre de garages complets actifs est donc volontairement **0**.

## STIB

Le pipeline GTFS STIB est prêt : téléchargement, conversion bus/tram de surface, projection dans le repère local et garde de fraîcheur. Le métro est exclu de cette branche circulation.

Les anciens endpoints publics STIB/Opendatasoft et le lien de téléchargement automatisé du nouveau portail se sont révélés indisponibles depuis GitHub au moment de la validation. L'indisponibilité distante est traitée comme advisory : le convertisseur et sa garde de fraîcheur restent testés, mais **aucune donnée STIB n'est activée comme réseau actuel tant qu'un feed officiel frais et automatisable n'est pas obtenu**.

## Validation Godot 4.7.1

La CI dédiée `Grand Bruxelles Traffic Systems` vérifie :

- passages piétons ;
- densité ;
- voitures/scooters/motos ;
- stationnement sûr ;
- livraisons et réservation/libération des places ;
- dégâts ;
- dépannage ;
- services OSM ;
- smoke test du trafic complet.

Dernier smoke test vert mesuré :

`TRAFFIC_SMOKE_OK: 140 ways, 588 nodes, 708 edges, 63 intersections (53 right-priority), 180 controls, 19 signals, 124 crossings (108 unsignalized), 4 moving, 3 pedestrians, 4/188 parked/candidates, 2 deliveries`

La CI générale Godot est également verte : import, scène complète, véhicule joueur, graphe, contrôles, trafic et mission Midi → Grand-Place.

## Suite

1. Relier les PNJ civils généraux à l'API de traversée.
2. Ajouter dégâts/immobilisation aux véhicules IA et transformer un accident en obstruction temporaire cohérente.
3. Ajouter dégagement/remorquage des véhicules IA accidentés.
4. Activer bus/trams STIB uniquement dès qu'un feed officiel frais est récupérable de façon stable.
5. Étendre la carte afin de rendre H.R.Z Services et d'autres vrais garages accessibles.
6. Remplacer progressivement les véhicules procéduraux par des modèles originaux optimisés.
