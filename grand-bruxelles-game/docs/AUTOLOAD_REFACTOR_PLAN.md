# Plan de refactorisation des autoloads

Contexte
- Le projet contient actuellement plusieurs autoloads déclarés dans project.godot. Les autoloads sont pratiques mais provoquent :
  - état global dispersé
  - temps de démarrage plus long
  - difficultés de test unitaire et d'isolation

Objectif
- Réduire le nombre d'autoloads non critiques (cibler 6–8) en les transformant en services lazy-loaded ou en les instanciant depuis un ServiceLocator central.

Étapes proposées
1. Auditer la liste actuelle des autoloads (ouvrir project.godot et lister).
2. Classer en : critique (à conserver), utile mais lazy (à convertir), à supprimer.
3. Implémenter ServiceLocator (game/scripts/service_locator.gd) et déplacer la logique d'initialisation dans des méthodes `init()` appelées au besoin.
4. Mettre en place tests unitaires pour s'assurer que l'ordre d'initialisation fonctionne.
5. Mesurer temps de démarrage avant/après.

Recommandation immédiate
- Ne pas modifier project.godot pour supprimer autoloads sans déployer ServiceLocator et assurer fallback. Procéder par étapes : convertir 2–3 autoloads tests, valider, poursuivre.
