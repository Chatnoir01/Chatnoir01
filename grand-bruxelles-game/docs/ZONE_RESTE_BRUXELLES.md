# Zone reste de Bruxelles

## Responsabilité de cette branche

Branche dédiée : `zone-reste-bruxelles`.

Cette branche prend en charge toute la Région de Bruxelles-Capitale qui n'est pas déjà attribuée aux deux autres chantiers actifs :

- **session principale** : corridor Gare du Midi → Lemonnier → Anneessens → Bourse → Grand-Place → Sablon, avec raccords immédiats ;
- **branche `zone-laeken-jette`** : Laeken + Jette.

Les frontières entre branches sont des coutures techniques : on peut lire/valider quelques mètres au-delà pour assurer un raccord routier, ferroviaire, terrain ou façade, mais on n'y reconstruit pas une zone concurrente.

## Communes prises en charge

La branche couvre en priorité :

1. Anderlecht ;
2. Auderghem ;
3. Berchem-Sainte-Agathe ;
4. Etterbeek ;
5. Evere ;
6. Forest ;
7. Ganshoren ;
8. Ixelles ;
9. Koekelberg ;
10. Molenbeek-Saint-Jean ;
11. Saint-Gilles hors corridor Midi déjà attribué ;
12. Saint-Josse-ten-Noode ;
13. Schaerbeek ;
14. Uccle ;
15. Watermael-Boitsfort ;
16. Woluwe-Saint-Lambert ;
17. Woluwe-Saint-Pierre.

Pour la **Ville de Bruxelles**, cette branche couvre les secteurs non attribués :

- Haren ;
- Neder-over-Heembeek ;
- quartier européen et extensions est non déjà couvertes ;
- axe Louise/Roosevelt et Bois de la Cambre relevant de la Ville ;
- parties du Pentagone hors corridor principal, uniquement après verrouillage des coutures avec la session principale.

Laeken reste explicitement hors périmètre de cette branche.

## Source de vérité

Même convention que le projet principal :

- CRS maître : **EPSG:31370 / Belgian Lambert 72** ;
- géométrie prioritaire : **UrbIS / UrbIS Landscape / WFS UrbIS** ;
- OSM : complément et contrôle, pas source métrique principale quand UrbIS existe ;
- orthophotos officielles : contrôle chaussées, trottoirs, rails, arbres, marquages et emprises ;
- LiDAR/DSM/3D officiel : hauteurs, terrain, skyline ;
- STIB/MIVB GTFS : couche sémantique transports ;
- photos : références de façades et textures uniquement selon droits/licences.

Aucune rue, bâtiment ou relief ne doit être reconstruit « au feeling ».

## Repère géométrique et monde Godot

La géométrie officielle est calculée depuis le point de contrôle Lambert72 de Bruxelles-Midi :

- `ORIGIN_E = 147868.29422791934`
- `ORIGIN_N = 169538.62414926197`

Cependant, le prototype OSM existant utilise son propre point WGS84 d'origine (`50.8419, 4.3480`). Dans ce monde déjà construit, le point Bruxelles-Midi se trouve à :

- `WORLD_ANCHOR_X = -668.5`
- `WORLD_ANCHOR_Z = 627.84`

La conversion **à utiliser pour toutes les nouvelles cellules UrbIS** est donc :

```text
Godot X = (Lambert_E - ORIGIN_E) + WORLD_ANCHOR_X
Godot Z = -(Lambert_N - ORIGIN_N) + WORLD_ANCHOR_Z
Godot Y = altitude - ORIGIN_ALTITUDE
```

Contrôle de non-régression obligatoire : le point `(ORIGIN_E, ORIGIN_N)` doit produire exactement `(-668.5, 627.84)` en X/Z dans le monde actuel.

Ce décalage est **global et unique**. Une commune ou une cellule ne reçoit jamais sa propre origine indépendante. Cette règle garantit que les cellules UrbIS, le greybox OSM actuel et le builder Midi se recollent dans le même monde.

## Découpage technique

Les données sont traitées en cellules **500 m × 500 m** par défaut, dans EPSG:31370.

Chaque cellule suit la chaîne :

```text
boundary officielle / UrbIS
        ↓
cellule Lambert72 500 m
        ↓
WFS bâtiments + voirie + rail/tram
        ↓
propriété par centroïde (coutures sans doublons)
        ↓
terrain / 3D / orthophoto de contrôle
        ↓
conversion vers coordonnées du monde Godot actuel
        ↓
runtime léger + assets de détail
        ↓
Godot
```

Les sources brutes restent hors édition. Les dérivés sont reproductibles.

### Propriété des objets aux coutures

Une requête WFS par bbox peut retourner le même bâtiment dans deux cellules adjacentes s'il coupe la limite. Pour supprimer ces doublons, la cellule propriétaire est celle dont la bbox demi-ouverte contient le centroïde du polygone :

```text
minE <= centroidE < maxE
minN <= centroidN < maxN
```

La cellule voisine peut voir l'objet dans sa source brute, mais ne le génère pas dans son runtime.

## Ordre de construction

L'ordre vise d'abord les raccords avec le monde déjà en cours, puis les grands axes structurants.

### Vague R1 — anneau central

- Saint-Gilles hors Midi ;
- Anderlecht proche Midi/Cureghem ;
- Molenbeek proche canal ;
- Ixelles nord ;
- Saint-Josse ;
- Schaerbeek sud ;
- Etterbeek / quartier européen.

### Vague R2 — ouest et nord-est

- Koekelberg ;
- Ganshoren ;
- Berchem-Sainte-Agathe ;
- Evere ;
- Schaerbeek nord ;
- Neder-over-Heembeek ;
- Haren.

### Vague R3 — sud et est

- Forest ;
- Uccle ;
- Ixelles sud ;
- Auderghem ;
- Watermael-Boitsfort ;
- Woluwe-Saint-Lambert ;
- Woluwe-Saint-Pierre ;
- Louise/Roosevelt/Bois de la Cambre.

L'ordre peut être ajusté par dépendances réseau, mais pas au prix d'une géométrie inventée.

## Critères de validation par cellule

Une cellule n'est marquée « reconstruite » que si :

- géométrie routière principale validée ;
- bâtiments de premier plan alignés sur source officielle ;
- terrain/altimétrie contrôlés quand disponibles ;
- transports structurants correctement raccordés ;
- au moins trois repères visuels réels dans les zones urbaines denses ;
- provenance et licence des assets enregistrées ;
- coutures avec cellules voisines sans trou ni double géométrie ;
- repère Godot contrôlé contre l'ancre Midi ;
- collision et navigation vérifiées ;
- budget de performance respecté ;
- test de chargement Godot réussi.

## Règle de fusion

Les changements de cette branche doivent rester localisés aux données/scènes/assets de ses zones. Les systèmes globaux ne sont modifiés qu'en cas de nécessité démontrée, avec patch séparé et test de non-régression.