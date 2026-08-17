# Jouer à Grand Bruxelles

## Lien unique

https://chatnoir01.github.io/Chatnoir01/

Cette URL GitHub Pages est l’unique porte d’entrée Web prévue pour le joueur. Le contenu servi vient directement de `grand-bruxelles-game/web-preview/` sur `main` : `index.html`, `index.js`, `index.wasm` et `index.pck`.

## État actuel

Le build jouable existe bien sur `main`. GitHub Pages doit encore être activé une seule fois par un administrateur du dépôt :

**GitHub → Settings → Pages → Build and deployment → Source → GitHub Actions**

GitHub a refusé la création initiale du site Pages depuis `GITHUB_TOKEN` avec `Resource not accessible by integration`. Après cette activation manuelle unique, le workflow `Grand Bruxelles Playable Link` déploie automatiquement `web-preview/` et vérifie que la page et les assets Godot répondent correctement.

RawGitHack n’est pas une solution finale et ne doit pas être communiqué comme lien joueur principal.

## Validation ACCESS

PASS uniquement lorsque `Grand Bruxelles Playable Link` affiche `PLAYABLE_PAGES_OK` et qu’un humain peut ouvrir le lien unique ci-dessus et atteindre l’écran de chargement Godot.
