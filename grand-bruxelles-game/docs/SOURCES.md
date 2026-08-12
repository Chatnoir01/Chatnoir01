# Sources de données et références

## OpenStreetMap

Usage : réseau routier, polygones de bâtiments, chemins, rails, espaces verts et points d’intérêt servant de base géographique.

Licence : Open Database License (ODbL). Attribution obligatoire à OpenStreetMap et ses contributeurs. Toute base dérivée distribuée doit être examinée au regard des obligations ODbL.

Source officielle : https://www.openstreetmap.org/

## Open Data Ville de Bruxelles

Usage : couches urbaines complémentaires selon disponibilité.

La majorité des datasets produits par la Ville de Bruxelles sont annoncés sous CC0 1.0, mais les datasets de tiers peuvent avoir une autre licence. Vérification obligatoire dans la fiche de chaque dataset.

Source officielle : https://opendata.brussels.be/

## UrbIS - Constructions 3D

Usage : géométrie sémantique LoD2 des bâtiments et ouvrages, en EPSG:31370. La Bourse est extraite depuis les `BuildingFaces` officielles, son enregistrement agrégé `BuildingSolids` étant un `Null Shape` valide dans la distribution SHP auditée.

Licence : CC0 1.0, vérifiée le 2026-08-12 dans les métadonnées officielles de Bruxelles. La géométrie dérivée conserve l’URL exacte du paquet, la date, les identifiants UrbIS et les SHA-256 du paquet et des composants sources.

Source officielle : https://datastore.brussels/web/data/dataset/e9ec2aa4-cffd-11ee-bccc-00090ffe0001

## Wikimedia Commons

Usage : références photographiques, architecture, matériaux et éventuellement textures lorsque la licence du fichier autorise clairement la réutilisation prévue.

Chaque fichier doit être vérifié individuellement : auteur, licence, attribution, partage à l’identique éventuel, restrictions supplémentaires.

Source officielle : https://commons.wikimedia.org/

## MediaWiki Action API

L’outil `tools/collect_wikimedia_refs.py` utilise l’API officielle MediaWiki pour rechercher des fichiers Commons et récupérer leurs métadonnées (`imageinfo` / `extmetadata`).

L’outil ne considère jamais qu’un résultat est automatiquement validé pour le jeu. Il produit une liste de candidats à examiner humainement avant téléchargement ou transformation.

## Photos originales

Les photos prises spécifiquement pour le projet sont à privilégier pour les façades secondaires et les détails urbains.

À enregistrer dans le registre :

- auteur ;
- date ;
- quartier ;
- autorisation d’usage ;
- personnes/marques visibles nécessitant éventuellement un traitement.

## Règle d’intégration

Aucun fichier externe n’entre dans `assets/production/` sans :

1. une source connue ;
2. une licence vérifiée ;
3. une ligne dans `assets/LICENSE_REGISTRY.csv` ;
4. une attribution préparée si nécessaire ;
5. une vérification que l’usage dans un jeu et la redistribution sont compatibles.
