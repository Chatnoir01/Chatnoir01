# GDD — Grand Bruxelles Game

## 1. Pitch

**Grand Bruxelles Game** est un jeu d’action-aventure urbain en monde ouvert, en vue à la troisième personne, qui reconstruit progressivement Bruxelles comme un espace vivant : rues, quartiers, bâtiments emblématiques, mobilité, météo, activités et population simulée.

Le jeu n’est pas une copie de GTA. Il emprunte au genre open world ses principes de liberté, conduite et exploration, mais construit sa propre identité, ses propres systèmes, son propre ton et ses propres personnages.

## 2. Fantaisie joueur

Le joueur doit ressentir :

- « je reconnais Bruxelles » ;
- « cette ville fonctionne même quand je ne fais rien » ;
- « je peux choisir comment me déplacer et quoi faire » ;
- « chaque quartier a une ambiance différente ».

## 3. Piliers

### 3.1 Bruxelles reconnaissable

Fidélité prioritaire sur :

- tracé des rues principales ;
- volumes des îlots ;
- silhouettes urbaines ;
- monuments ;
- matériaux typiques : brique, pierre, pavés, rails, façades mitoyennes ;
- signalétique et mobilier inspirés de Bruxelles sans reproduire illégalement des éléments protégés.

### 3.2 Liberté de déplacement

- marche ;
- course ;
- saut ;
- conduite ;
- entrée/sortie de véhicule ;
- déplacements rapides possibles plus tard via transports.

### 3.3 Ville vivante

- circulation routière ;
- piétons ;
- comportements contextuels ;
- densité différente selon l’heure et le quartier ;
- événements simples en bord de rue.

### 3.4 Missions locales

Les missions doivent exploiter Bruxelles : livraisons, courses, rendez-vous, exploration, récupération, assistance, poursuite ou infiltration légère, sans reprendre de missions d’une licence existante.

## 4. Caméra et contrôles

Vue 3e personne avec caméra orbitale :

- stick/souris = orientation caméra ;
- ZQSD/WASD = déplacement ;
- Shift = course ;
- Espace = saut ;
- E = interaction ;
- F = entrer/sortir d’un véhicule ;
- Échap = pause.

Le déplacement doit rester précis dans les rues étroites et confortable sur de longues distances.

## 5. Monde

### Vertical Slice 01

**Gare du Midi → Anneessens → Bourse → Grand-Place**.

Objectif spatial : environ 1 à 2 km de corridor urbain jouable, avec les rues adjacentes nécessaires pour donner une sensation de réseau et non de simple couloir.

### Extensions futures

- Marolles / Sablon ;
- Sainte-Catherine / canal ;
- quartier européen / Cinquantenaire ;
- Flagey / Ixelles ;
- Laeken / Atomium ;
- Jette ;
- Schaerbeek ;
- Anderlecht ;
- Saint-Gilles ;
- Uccle et zones vertes.

## 6. Personnage

Prototype : personnage neutre sans identité narrative définitive.

Systèmes V1 :

- CharacterBody3D ;
- accélération/décélération ;
- gravité ;
- saut ;
- caméra 3e personne ;
- interaction par raycast ;
- état à pied / en véhicule.

Plus tard : animations, inventaire léger, téléphone, argent, réputation, tenue.

## 7. Véhicules

V1 : une voiture.

Exigences :

- accélération/freinage ;
- direction progressive ;
- marche arrière ;
- collisions ;
- caméra véhicule ;
- entrée/sortie ;
- respawn debug.

V2 : plusieurs catégories de véhicules avec paramètres de masse, grip, puissance et freinage.

## 8. Trafic

Architecture prévue :

- graphe de voies routières séparé du navmesh piéton ;
- splines/waypoints par voie ;
- feux et intersections pilotés par états ;
- pooling des véhicules ;
- simulation complète proche du joueur, simulation simplifiée loin du joueur.

## 9. Piétons

- NavigationServer3D / NavigationRegion3D par secteur ;
- agents avec destinations locales ;
- profils de marche ;
- évitement limité aux agents proches ;
- pooling ;
- LOD de simulation comportementale.

## 10. Police / niveau d’alerte

Pas de copie du système d’étoiles GTA.

Système original proposé : **Indice de vigilance**.

Niveaux :

- calme ;
- signalé ;
- recherché localement ;
- intervention renforcée ;
- verrouillage de secteur.

Chaque niveau modifie les réactions des unités, pas seulement leur quantité.

## 11. Missions du Vertical Slice

### Mission 01 — Première course

- départ Gare du Midi ;
- rejoindre un contact à Anneessens ;
- récupérer un petit colis fictif ;
- livrer près de la Bourse ;
- retour libre.

Cette mission teste déplacement à pied, véhicule, checkpoints, UI et streaming.

### Mission 02 — Détour

Une rue est bloquée par un événement dynamique. Le joueur doit choisir un autre itinéraire. Test du réseau routier et du guidage.

## 12. Cycle jour/nuit

V1 :

- soleil directionnel ;
- environnement dynamique ;
- 4 états test : matin, midi, soir, nuit.

V2 : cycle continu et météo.

## 13. Audio

Priorités :

- ambiance de circulation ;
- tram/rail dans les zones concernées ;
- foule ;
- pluie ;
- réverbération légère par zone ;
- musique originale uniquement.

## 14. UX / HUD

HUD minimal :

- objectif actuel ;
- distance ;
- mini-indicateur directionnel ;
- vitesse véhicule ;
- indice de vigilance ;
- interaction contextuelle.

Pas d’interface copiée d’un autre jeu.

## 15. Direction artistique

**Semi-réaliste crédible**.

But : reconnaissance forte de Bruxelles sans exiger un photoréalisme coûteux sur chaque façade.

- landmarks : haute fidélité ;
- bâtiments secondaires : kits modulaires ;
- végétation : bibliothèque commune ;
- matériaux : atlases et trimsheets ;
- éclairage : ambiance européenne, météo souvent diffuse, nuits urbaines contrastées.

## 16. Performance cible initiale

Prototype PC :

- 1080p ;
- 60 fps visés sur machine milieu de gamme ;
- 30 fps minimum acceptable pendant le développement ;
- pas de chargement bloquant visible dans le corridor principal une fois le niveau lancé.

Les budgets finaux seront fixés après premier benchmark matériel.

## 17. Définition du Vertical Slice terminé

Le Vertical Slice est considéré réussi quand :

1. le joueur peut marcher de Midi à Bourse/Grand-Place ;
2. au moins 3 zones sont visuellement reconnaissables ;
3. un véhicule est utilisable ;
4. le trafic fonctionne ;
5. au moins 20 piétons simulés peuvent être visibles sans casser la cible de performance ;
6. une mission complète est jouable ;
7. le monde se charge/décharge par secteurs ;
8. les sources de données et assets sont tracées dans un registre de licences.
