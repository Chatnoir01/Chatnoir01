# Assets Guide & Recommended Sources

Ce document liste des sources libres et recommandations pour les assets utilisés dans Sprint 0 et suivants.

Characters / Animations
- MakeHuman — générateur de personnages open source. Licence : GPL (vérifier). https://www.makehumancommunity.org
- Mixamo — animations gratuites via Adobe (nécessite compte Adobe). Vérifier les termes d'utilisation : https://www.mixamo.com

3D Models / Props / Vehicles
- glTF Sample Models (Khronos) — modèles d'exemple ; vérifier la licence par modèle. https://github.com/KhronosGroup/glTF-Sample-Models
- CC0 / Public Domain model repositories (vérifier source et licence avant intégration):
  - Poly Haven (assets 3D + HDRI) : https://polyhaven.com (textures et modèles sous CC0)
  - OpenGameArt (divers) : https://opengameart.org

Textures / HDRI
- Poly Haven (CC0 HDRIs / textures) : https://polyhaven.com/textures

Photogrammetry
- AliceVision / Meshroom — pipeline photogrammetry open source : https://github.com/alicevision/meshroom

GIS / OSM
- BlenderGIS — importer OSM/GIS dans Blender : https://github.com/domlysz/BlenderGIS
- GDAL/OGR & QGIS pour reprojection et traitement : https://gdal.org, https://qgis.org

Traffic / Simulation Data
- SUMO — Simulation of Urban Mobility (EPL) : https://www.eclipse.org/sumo/

Licensing checklist (toujours remplir avant commit)
- S’assurer que chaque asset dispose d’un champ de licence dans `grand-bruxelles-game/assets/LICENSE_REGISTRY.tsv`
- Préférer CC0 / public domain pour les assets provisoires. Pour assets commerciaux, stocker preuve d’achat/licence.

