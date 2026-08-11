# Architecture cible — Pilot

## Principes

Pilot sépare l'interface, le domaine métier et l'infrastructure. Les calculs fiscaux et la numérotation ne doivent pas dépendre du navigateur ni de la base de données.

## Couches

### 1. Frontend
Application responsive pour tableau de bord, clients, devis, factures et paramètres. Le frontend ne doit jamais être l'autorité finale sur les montants enregistrés.

### 2. API
API HTTP versionnée. Responsabilités : authentification, autorisation, validation, orchestration et sérialisation.

### 3. Domaine
Fonctions déterministes pour calcul des montants, validation des documents, numérotation, transitions de statut et règles devis vers facture.

### 4. Persistance
Cible : PostgreSQL avec transactions. Toute donnée métier appartient à un tenant/une entreprise. Les requêtes doivent systématiquement être filtrées par tenant_id côté serveur.

## Entités principales
User, Organization, Membership, Client, Quote, QuoteLine, Invoice, InvoiceLine, Payment, Reminder, AuditEvent.

## Règles structurelles
1. Montants stockés précisément, idéalement en cents entiers côté persistance.
2. Une facture émise ne doit pas être silencieusement réécrite.
3. Les numéros de facture sont attribués côté serveur dans une transaction.
4. Les PDF sont générés à partir d'un snapshot immuable.
5. Les secrets ne sont jamais envoyés au navigateur.
6. Toute action est autorisée contre l'organisation courante.

## Phases
Phase A : UX, domaine, serveur, tests, CI. Phase B : PostgreSQL et CRUD. Phase C : authentification, multi-tenant, audit, PDF. Phase D : devis, paiements, relances, exports et observabilité.
