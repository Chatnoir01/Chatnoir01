# Reconstruction technique — Bruxelles-Midi

## Objectif

Passer du greybox OSM actuel à une reconstruction métrique reconnaissable de Bruxelles-Midi, puis prolonger vers Lemonnier, Anneessens, Bourse et Grand-Place.

Critère principal : une capture sans HUD ni texte doit être identifiable comme Bruxelles par sa géométrie, ses axes, ses rails, ses volumes, ses matériaux et ses repères urbains.

## 1. Source de vérité géométrique

### A. UrbIS Landscape — PRIORITÉ 0

Dataset officiel Paradigm, anciennement `UrbIS - ADM 3D V2 Beta`.

Il combine :
- les constructions 3D ;
- le modèle numérique de terrain ;
- un modèle tridimensionnel du sol et du bâti de la Région de Bruxelles-Capitale.

Identifiant : `713171e6-65e3-11ef-b378-010101010000`
Mise à jour annoncée : mensuelle.

Usage jeu :
- terrain/pentes réels ;
- volumes et hauteurs de bâtiments ;
- contrôle de l'altimétrie des rues ;
- remplacement progressif des extrusions OSM génériques.

### B. UrbIS Parcels and Buildings — PRIORITÉ 0

Identifiant : `2cf42541-1813-11ef-8a81-00090ffe0001`
CRS documenté : `EPSG:31370` (Belgian Lambert 72).

Classes utiles :
- bâtiments 2D ;
- adresses ;
- parcelles cadastrales.

Les classes bâtiments/adresses sont annoncées CC0 ; la classe parcellaire conserve la licence SPF Finances.

Usage jeu :
- empreintes exactes ;
- alignements de façades ;
- séparation des îlots ;
- contrôle des bâtiments 3D ;
- rattachement adresse ↔ bâtiment.

### C. UrbIS Transport networks — PRIORITÉ 0

Identifiant : `af847c40-848b-11ee-9a1f-00090ffe0001`

Classes :
- axes de rues ;
- intersections ;
- réseau ferroviaire/tram.

Le jeu de données intègre notamment des informations attributaires de Bruxelles Mobilité.

Usage jeu :
- axes officiels ;
- carrefours ;
- tram/train ;
- validation de l'OSM ;
- génération des splines de conduite/IA.

### D. UrbIS Digital Surface Model — PRIORITÉ 1

Identifiant : `8c2d921e-6a53-11ed-bfb5-010101010000`

Raster de surface contenant les objets naturels et bâtis.

Usage jeu :
- contrôle des hauteurs ;
- détection arbres/toitures/ouvrages ;
- validation du skyline ;
- contrôle ponctuel de la 3D UrbIS.

### E. Orthophotos officielles — PRIORITÉ 0

Sources :
- service Ortho Paradigm/Bruxelles ;
- couverture nationale NGI harmonisée à partir des régions.

La couverture nationale récente annonce une résolution de 12,5 cm en Flandre et à Bruxelles.

Usage jeu :
- largeur réelle de chaussée ;
- trottoirs ;
- îlots ;
- rails ;
- marquages ;
- arbres ;
- emprises d'arrêts ;
- vérification des cours et toitures.

Ne pas utiliser automatiquement comme texture de production : d'abord vérifier licence et millésime par couche.

## 2. Transport public

### STIB/MIVB GTFS

À intégrer pour :
- géolocalisation des arrêts ;
- tracé des lignes ;
- séquence des arrêts ;
- noms officiels.

Le GTFS ne remplace pas UrbIS pour la géométrie fine des rails : il sert surtout de couche sémantique et de validation réseau.

## 3. Sources visuelles

### Niveau A — production possible après contrôle licence
- photos personnelles du projet ;
- Wikimedia Commons fichier par fichier ;
- images CC0 / CC BY compatibles avec notre registre de licences ;
- éventuelles photos officielles réutilisables avec licence explicite.

### Niveau B — référence seulement
- Mapillary et autres vues contributives selon conditions applicables ;
- articles de presse ;
- photos trouvées sur le Web ;
- captures/cartes de services commerciaux.

Les sources niveau B servent à comprendre :
- proportions ;
- matériaux ;
- signalétique ;
- mobilier ;
- état des façades ;
- perspective depuis le piéton.

Elles ne doivent pas être redistribuées comme textures/assets sans droit explicite.

## 4. Système de coordonnées maître

### CRS de travail

Utiliser `EPSG:31370` comme CRS maître pour les vecteurs UrbIS du vertical slice, car le dataset officiel bâtiments/parcelles est publié dans ce CRS.

Toutes les autres sources doivent être reprojetées vers EPSG:31370 avant génération jeu.

### Origine locale Godot

Point de contrôle actuel Gare du Midi :
- WGS84 approx : lat `50.83626`, lon `4.33849`
- Lambert 72 approx : E `147868.294`, N `169538.624`

Transformation jeu :

```text
Godot X = Lambert_E - ORIGIN_E
Godot Z = -(Lambert_N - ORIGIN_N)
Godot Y = altitude - ORIGIN_ALTITUDE
```

Le signe négatif sur Z garde le nord vers -Z comme dans le prototype actuel.

Contrôles calculés depuis les points de référence existants :

| Point | E Lambert72 | N Lambert72 | X local | Z local |
|---|---:|---:|---:|---:|
| Gare du Midi | 147868.294 | 169538.624 | 0.000 | 0.000 |
| Anneessens | 148265.856 | 170382.797 | 397.562 | -844.173 |
| Bourse | 148620.234 | 170829.882 | 751.939 | -1291.258 |
| Grand-Place | 148858.110 | 170700.537 | 989.815 | -1161.913 |

Ces points sont des ancres de contrôle, pas des substituts aux géométries officielles.

## 5. Découpage du secteur Midi

### Cellule M00 — Gare du Midi / Place Horta
Priorité maximale.

À reconstruire précisément :
- volume de la gare ;
- entrées et auvents ;
- façades basses de gare ;
- tours visibles ;
- Place Horta ;
- accès métro/prémétro ;
- voies/rails visibles ;
- mobilier majeur ;
- traversées piétonnes.

### Cellule M01 — Avenue Fonsny
- largeur de boulevard ;
- rails de tram ;
- quais/arrêts ;
- alignement d'immeubles ;
- arbres ;
- câbles/caténaires ;
- marquages ;
- façades de premier plan.

### Cellule M02 — Jamar / Esplanade / axes adjacents
- grands carrefours ;
- flux routiers ;
- rampes/variations de niveau ;
- volumes de bureaux/hôtels ;
- signalétique.

### Cellule C00 — Lemonnier
Premier raccord vers le centre.

### Cellule C01 — Anneessens
Zone de validation visuelle : façades continues, entrée de station, commerces, trottoirs, piste cyclable et mobilier.

## 6. Matrice de précision

### Hero assets — précision forte
Objectif : erreur horizontale < 0,5 m quand les données le permettent.

- Gare du Midi ;
- Place Horta ;
- carrefours principaux ;
- entrées de station ;
- façades dominantes ;
- rails et quais visibles.

### Bâtiments de premier plan
- empreinte officielle ;
- hauteur issue UrbIS 3D/DSM ;
- façade reconstruite depuis photos ;
- fenêtres/portes modulaires adaptées au bâtiment réel.

### Bâtiments de fond
- empreinte officielle ;
- hauteur réelle ou proche ;
- façade procédurale contrôlée ;
- toit simplifié ;
- LOD agressif à distance.

## 7. Pipeline données → Blender/Godot

```text
UrbIS / orthophoto / STIB / photos
            ↓
         QGIS/PROJ
            ↓
      EPSG:31370 maître
            ↓
  découpe bbox/cellule 250–500 m
            ↓
   GeoPackage/GeoJSON nettoyé
            ↓
 conversion coordonnées locales
            ↓
  Blender (hero/detail) + génération
            ↓
   glTF/GLB + données gameplay
            ↓
            Godot
```

### Règles
- conserver une copie brute de chaque source ;
- ne jamais éditer la source brute ;
- produire une couche `processed` reproductible ;
- enregistrer date, licence, URL et hash ;
- distinguer `reference_only` de `production_allowed`.

## 8. Dossier source cible

```text
data/sources/midi/
  manifest.json
  control_points_lambert72.json
  raw/
    urbis_landscape/
    urbis_buildings/
    urbis_transport/
    dsm/
    ortho/
    stib/
  processed/
    terrain/
    buildings/
    roads/
    rails/
    sidewalks/
    landmarks/
refs/midi/
  gare_du_midi/
    aerial/
    street/
    facade/
    roof/
    materials/
    signage/
    furniture/
  place_horta/
  avenue_fonsny/
  boulevard_jamar/
  lemmonier/
  anneessens/
```

## 9. Inventaire photo par lieu

Pour chaque hero zone, viser au minimum :
- 4 vues cardinales/obliques générales ;
- 2 vues depuis chaque carrefour important ;
- 1 vue de chaque façade hero ;
- détails de rez-de-chaussée ;
- détails fenêtres/corniches ;
- trottoir + bordure + chaussée ;
- rails/caténaires ;
- mobilier ;
- signalétique ;
- vue nocturne si utile ;
- vue aérienne/orthophoto.

Chaque référence doit être enregistrée avec :
`id, place, source_url, author, license, capture_date, view_direction, subject, allowed_use, notes`.

## 10. Ordre de reconstruction le plus rapide

1. importer UrbIS Landscape pour Midi ;
2. recaler tous les systèmes sur EPSG:31370 ;
3. générer terrain réel ;
4. remplacer les bâtiments OSM par les bâtiments UrbIS ;
5. remplacer axes routiers/rails par UrbIS Transport ;
6. projeter orthophoto temporaire uniquement comme couche de QA dans Blender/QGIS ;
7. reconstruire Gare du Midi + Place Horta ;
8. reconstruire Avenue Fonsny ;
9. ajouter trottoirs/marquages/caténaires ;
10. comparer capture jeu ↔ références réelles ;
11. seulement ensuite étendre vers Lemonnier/Anneessens.

## 11. Gate qualité avant extension

On ne passe pas à la cellule suivante tant que :
- position bâtiments/rails cohérente avec orthophoto ;
- terrain/pente cohérents ;
- skyline principal reconnaissable ;
- au moins 3 repères de Midi identifiables sans HUD ;
- routes praticables sans géométrie cassée ;
- aucune texture externe non tracée dans le registre de licences.
