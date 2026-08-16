# Pipeline Photo → Jeu

Objectif : améliorer un élément visible du jeu à partir d'une photo réelle de Bruxelles, sans refonte globale.

## Flux obligatoire
1. Capturer une référence photo légale, claire et centrée sur un seul sujet.
2. Noter le sujet, la zone et l'angle cible in-game.
3. Capturer le BEFORE au même point de vue, ou au plus proche possible.
4. Limiter le diagnostic à 3 écarts : proportion, matière, détail.
5. Appliquer un seul correctif dans le lot.
6. Capturer l'AFTER avec le même témoin caméra.
7. Faire le gate humain 3 s : PASS si l'amélioration est immédiatement crédible ; FAIL si elle ressemble à de la décoration générique ou à un échafaudage.
8. Archiver photo, BEFORE, AFTER et verdict.

## Arborescence
- `refs/photos/<sujet>/` : référence et preuve de licence/autorisation si nécessaire.
- `refs/witnesses/<sujet>_before.png`
- `refs/witnesses/<sujet>_after.png`
- `refs/reports/<sujet>.md` à partir de `_template.md`.

## Rails
- 1 photo = 1 sujet = 1 lot.
- Aucun lot photo ne doit inventer de géométrie UrbIS hors contrat source.
- La CI peut mesurer un diff pixel, jamais remplacer le jugement humain de crédibilité.
- Respecter licence, auteur et droit à l'image ; ne pas archiver une référence non autorisée.
- Un PASS propose un merge vers `main`. Un FAIL ferme le lot sans merge.
- Citygen continue en parallèle mais ne prend pas la priorité sur le fun jouable et les améliorations visibles côté joueur.
