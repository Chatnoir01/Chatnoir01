# Pilot

MVP professionnel de gestion commerciale pour indépendants belges.

## Fonctionnalités actuelles
- Tableau de bord financier responsive
- Gestion locale des clients
- Liste et statuts des factures
- Création de facture
- Calcul HTVA + TVA + TTC
- Taux TVA configurables 0 / 6 / 12 / 21 %
- Persistance locale via localStorage

## Architecture V0
Application statique HTML/CSS/JavaScript avec un serveur Node minimal et une couche métier séparée pour les calculs et validations.

## Prochaines étapes
1. Base de données PostgreSQL
2. Authentification multi-tenant
3. Paramètres entreprise et numérotation robuste
4. Génération PDF
5. Devis vers facture
6. Échéances et relances
7. Tests d'intégration
8. Sécurité et journalisation

Prototype : les données affichées sont de démonstration et ne constituent pas un système comptable certifié.
