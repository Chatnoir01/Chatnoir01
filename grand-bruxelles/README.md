# Grand Bruxelles

Grand Bruxelles est un guide web interactif consacré aux 19 communes de la Région de Bruxelles-Capitale.

## Aperçu en ligne

**Voir la version actuelle :**
https://htmlpreview.github.io/?https://github.com/Chatnoir01/Chatnoir01/blob/main/grand-bruxelles/index.html

Cette prévisualisation charge directement le fichier HTML présent sur la branche `main`. Le projet a été rendu autonome dans un seul `index.html` afin de limiter les problèmes de chargement de CSS ou JavaScript externes.

## Version actuelle

- 19 communes couvertes ;
- 47 lieux de départ ;
- recherche instantanée ;
- filtre par commune ;
- filtre par catégorie ;
- carte urbaine interactive intégrée ;
- fiches détaillées de lieux ;
- liens d’itinéraire vers OpenStreetMap ;
- grille des 19 communes avec compteurs ;
- sélection des incontournables ;
- filtres « Bruxelles par envie » ;
- présentation de quartiers ;
- navigation responsive mobile / desktop ;
- accessibilité de base et réduction des animations.

## Architecture

La version principale est volontairement autonome :

- `index.html` contient le HTML, le CSS, les données et le JavaScript nécessaires à l’expérience ;
- aucune bibliothèque cartographique externe n’est requise pour afficher la carte urbaine ;
- OpenStreetMap est utilisé uniquement lorsque l’utilisateur ouvre un itinéraire externe.

## Lancer localement

Le projet ne nécessite aucun build. Il peut être ouvert directement ou via un petit serveur statique :

```bash
python3 -m http.server 8080
```

Puis ouvrir `http://localhost:8080/grand-bruxelles/`.

## Prochaines extensions

- événements ;
- restaurants et commerces ;
- transports et mobilité ;
- favoris ;
- comptes utilisateurs ;
- contenus FR / NL / EN ;
- PWA ;
- moteur de recommandations locales.
