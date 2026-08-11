# Pipeline Bruxelles réel → jeu

## But

Utiliser des données et références réelles pour gagner en fidélité sans importer aveuglément du contenu externe. Le jeu final doit rester optimisé, cohérent artistiquement et juridiquement traçable.

## 1. Sources de géométrie urbaine

### OpenStreetMap

Utilisations prévues :

- axes routiers ;
- intersections ;
- emprises de bâtiments quand disponibles ;
- parcs ;
- rails ;
- points d’intérêt utiles.

Règle : conserver l’attribution OpenStreetMap et des contributeurs et documenter toute base dérivée distribuée.

### Open Data Bruxelles

Utilisations possibles selon dataset :

- mobilier ;
- équipements ;
- arbres/espaces verts ;
- données administratives ;
- autres couches géographiques.

Règle : vérifier la licence **dataset par dataset**, même si de nombreux jeux de données de la Ville sont sous CC0.

## 2. Sources photo

### Wikimedia Commons

Utilisation principale : **référence visuelle et texture source sélectionnée**.

Pour chaque fichier utilisé :

- URL de la page du fichier ;
- auteur ;
- licence ;
- obligations d’attribution ;
- modifications effectuées ;
- date de récupération.

Ne jamais supposer que deux photos Commons ont la même licence.

### Photos originales du projet

À privilégier pour :

- façades secondaires ;
- détails de voirie ;
- mobilier ;
- textures ;
- références peu couvertes.

Conserver : date, zone, auteur et autorisation d’usage.

### Street-level imagery externe

Peut être utilisée comme **référence** si les conditions du service le permettent. Ne pas copier massivement des images, ne pas embarquer les images dans le jeu sans droit explicite et ne pas entraîner automatiquement une texture pipeline dessus sans vérification contractuelle.

## 3. Registre de licences

Créer plus tard `assets/LICENSE_REGISTRY.csv` avec :

```csv
asset_id,source_url,author,license,attribution_required,derivative_terms,local_path,notes
```

Aucun asset externe ne passe en production sans entrée dans ce registre.

## 4. Pipeline OSM

### Étape A — extraction

Zone pilote approximative autour :

- Gare du Midi ;
- Anneessens ;
- Bourse ;
- Grand-Place ;
- Sablon/Mont des Arts en option.

### Étape B — nettoyage

Ne garder que ce qui est utile au jeu :

- voies carrossables ;
- voies piétonnes ;
- bâtiments ;
- rails ;
- espaces verts ;
- eau ;
- POI de référence.

### Étape C — conversion

Convertir vers un format de travail contrôlé : GeoJSON/JSON puis générer :

- centre des routes ;
- largeur approximative ;
- segments ;
- carrefours ;
- polygones bâtiments ;
- identifiants stables.

### Étape D — correction artistique

Les données réelles ne suffisent pas :

- corriger les largeurs ;
- simplifier les courbes ;
- résoudre les doubles voies ;
- créer trottoirs ;
- ajouter niveaux/escaliers ;
- replacer manuellement les landmarks.

## 5. Façades

Trois niveaux :

### Tier A — Landmark

Modèle spécifique et référence photo approfondie.

### Tier B — façade importante

Kit modulaire avec combinaison de fenêtres, portes, corniches, matériaux.

### Tier C — remplissage urbain

Volumes simples + matériaux/atlases + variations procédurales.

## 6. Photos → matériaux

Pipeline conseillé :

1. choisir photo légalement réutilisable ;
2. corriger perspective ;
3. retirer éléments temporaires/personnes si nécessaire ;
4. créer texture répétable ou trim ;
5. générer normal/roughness avec outils adaptés ;
6. réduire résolution selon budget ;
7. enregistrer la provenance ;
8. tester dans une scène avec éclairage neutre.

## 7. Reconstruction des landmarks

Pour chaque landmark :

- 10 à 30 photos de référence sous plusieurs angles si possible ;
- mesures approximatives via données géographiques et proportions ;
- silhouette low-poly ;
- validation distance ;
- détails moyen plan ;
- textures ;
- LOD0/LOD1/LOD2 ;
- collision simplifiée ;
- test de performance.

## 8. Ce qu’on ne fait pas

- scraper n’importe quel site photo sans licence ;
- importer Google Street View comme textures sans autorisation ;
- utiliser logos GTA ou assets Rockstar ;
- recopier des marques visibles partout sans réflexion juridique/artistique ;
- mettre des milliers de photos HD brutes dans le dépôt Git.

## 9. Validation de fidélité

Chaque zone reçoit une checklist :

- tracé principal correct ;
- largeur visuelle crédible ;
- skyline reconnaissable ;
- 3 repères visuels minimum ;
- matériaux cohérents ;
- circulation logique ;
- performance dans le budget.

## 10. Priorité de collecte Vertical Slice 01

1. Gare du Midi / Esplanade de l’Europe ;
2. Avenue Fonsny / boulevard du Midi ;
3. Anneessens ;
4. boulevard Maurice Lemonnier ;
5. Bourse ;
6. rue du Midi / rues centrales ;
7. Grand-Place ;
8. raccord Sablon / Mont des Arts si le budget le permet.
