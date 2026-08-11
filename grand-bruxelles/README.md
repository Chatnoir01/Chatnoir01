# Grand Bruxelles

Grand Bruxelles est une expérience web statique dédiée à l’exploration de la Région de Bruxelles-Capitale.

## Fonctionnalités

- carte interactive basée sur Leaflet et OpenStreetMap ;
- recherche instantanée de lieux ;
- filtres par catégorie ;
- présentation des 19 communes ;
- sélection éditoriale de lieux emblématiques ;
- interface responsive mobile/desktop ;
- accessibilité de base : navigation clavier, skip-link, réduction des animations.

## Lancer localement

Le projet ne nécessite aucun build. Ouvrez `index.html` avec un petit serveur statique, par exemple :

```bash
python3 -m http.server 8080
```

Puis ouvrez `http://localhost:8080`.

## Architecture

- `index.html` : structure et contenu principal ;
- `styles.css` : design responsive ;
- `app.js` : données, recherche, filtres et carte.

## Données cartographiques

Les tuiles et données cartographiques affichées proviennent d’OpenStreetMap. L’attribution OpenStreetMap est conservée sur la carte et dans le pied de page.

## Prochaines extensions

Le projet peut évoluer vers un vrai portail local avec :

- événements en temps réel ;
- fiches de commerces et restaurants ;
- itinéraires multimodaux ;
- comptes et favoris ;
- contenu multilingue FR/NL/EN ;
- API et base de données ;
- PWA installable ;
- moteur de recommandations locales.
