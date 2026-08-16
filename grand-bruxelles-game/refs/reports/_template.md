# Photo → Jeu — rapport de lot

## Identité
- Sujet : `<sujet>`
- Zone : `<zone>`
- Angle cible in-game : `<angle/camera>`
- Lot : `<correctif unique>`

## Référence photo
- Fichier : `refs/photos/<sujet>/<photo>`
- Source / auteur : `<source>`
- Licence / autorisation : `<licence ou preuve>`
- Droit à l'image vérifié : `OUI/NON/N/A`

## BEFORE
- Témoin : `refs/witnesses/<sujet>_before.png`

## Diagnostic — 3 écarts maximum
1. Proportion : `<écart ou N/A>`
2. Matière : `<écart ou N/A>`
3. Détail : `<écart ou N/A>`

## Correctif unique
`<une seule modification mesurable>`

## AFTER
- Témoin : `refs/witnesses/<sujet>_after.png`
- Même caméra / point de vue : `OUI/NON — <raison si NON>`

## Gate humain 3 s
- Verdict : `PASS/FAIL`
- Motif : `<crédibilité visible en 3 secondes>`
- Si décoration générique / échafaudage : `FAIL`

## Archive
- [ ] Photo référence archivée
- [ ] BEFORE archivé
- [ ] AFTER archivé
- [ ] Verdict renseigné

## Risque restant
`<risque principal>`

## Décision
- `PASS` → proposer merge vers `main`
- `FAIL` → fermer sans merge
