# Naya Market — nouvelle application Next.js / Vercel

Cette application est ajoutée dans `next-app/` afin de préserver le site GitHub Pages actuel pendant la migration. Elle utilise Next.js 16.4.5 (et non Next.js 14, qui n'est plus supporté), React, Supabase et une route serveur pour l'envoi des commandes.

## Architecture

- `src/app/page.tsx` : page d'accueil et chargement du catalogue public.
- `src/components/storefront.tsx` : interface React et deux paniers indépendants (épicerie / traiteur), persistés séparément dans le stockage local du navigateur.
- `src/app/api/orders/route.ts` : validation serveur du checkout et appel RPC Supabase.
- `src/lib/supabase/public.ts` : clé publishable uniquement.
- `src/lib/supabase/admin.ts` : clé secrète serveur uniquement.
- `supabase/migrations/202611110001_secure_guest_checkout.sql` : durcissement des droits SQL.
- `src/app/cgv`, `src/app/mentions-legales`, `src/app/politique-de-confidentialite` : modèles de pages légales à compléter.

## Variables Vercel

À renseigner dans Project Settings > Environment Variables (Production, Preview et Development selon besoin) :

1. `NEXT_PUBLIC_SUPABASE_URL` — `https://vkmmbgkfpxogscyukvnc.supabase.co`
2. `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` — clé `sb_publishable_...` du projet Supabase.
3. `SUPABASE_SECRET_KEY` — clé secrète `sb_secret_...` du projet Supabase. **Serveur uniquement. Ne jamais la préfixer par NEXT_PUBLIC_.**
4. `NEXT_PUBLIC_SITE_URL` — URL Vercel ou domaine personnalisé (facultative pour le fonctionnement initial, à renseigner pour les métadonnées canoniques futures).

Ne jamais committer `.env.local`, une clé secrète ou un jeton de service.

## Déploiement Vercel

1. Importer le dépôt GitHub `casamtp/Naya` dans Vercel.
2. Choisir la branche `refonte/nextjs-vercel-securisation`.
3. Définir **Root Directory** sur `next-app`.
4. Framework : Next.js ; Node.js : 22.x.
5. Ajouter les variables ci-dessus.
6. Lancer un déploiement Preview et vérifier catalogue, panier épicerie, panier traiteur, formulaire et erreurs.
7. Ne basculer le domaine de production qu'après validation des tests et de la migration SQL.
8. Conserver le site GitHub Pages tant que le nouveau déploiement n'a pas été accepté.

Le fichier `vercel.json` ne réécrit pas les routes : Next.js gère nativement les routes App Router et les routes API dynamiques.

## Migration SQL — ordre impératif

La migration révoque les appels anon/authenticated aux RPC de création de commandes et de réservations. Le checkout actuel sur GitHub Pages appelle directement la RPC depuis le navigateur : **il cessera de fonctionner si la migration est appliquée avant que le nouveau site Vercel et sa route serveur soient opérationnels.**

Procédure :
1. Déployer la nouvelle application en Preview avec une clé secrète Supabase serveur.
2. Tester les commandes de bout en bout sur une base de test ou avec des commandes de test convenues.
3. Faire une sauvegarde et examiner le SQL.
4. Appliquer la migration dans Supabase SQL Editor.
5. Vérifier les Advisors et tester immédiatement une commande épicerie et une commande traiteur.
6. Basculer ensuite le domaine public.

La clé secrète Supabase permet au serveur d'appeler les RPC après révocation des droits publics. Elle ne doit jamais être envoyée au navigateur.

## Modèle de sécurité et limites métier

- Le catalogue actif est public en lecture selon la politique RLS existante.
- Les commandes, lignes de commande, réservations et abonnements push ne sont pas directement lisibles/modifiables par les visiteurs.
- Les demandes de commande passent par une API serveur et la fonction SQL qui vérifie les prix et le stock en base.
- Les paniers sont conservés localement dans le navigateur ; il n'existe pas de table de panier dans le schéma Supabase actuel.
- Le schéma actuel n'associe pas les commandes invitées à un compte client. Le client peut soumettre une commande et reçoit un numéro, mais il n'existe pas de fonction publique de consultation ou modification ultérieure de sa commande. L'accès à un historique client nécessiterait un compte authentifié ou un jeton d'accès invité à usage contrôlé.
- Aucun paiement en ligne n'est activé.
- La demande Mondial Relay doit être confirmée manuellement par le magasin selon le fonctionnement actuel.

## Vérifications

Exécuter localement :

```bash
cd next-app
cp .env.example .env.local
# Remplacer les valeurs par celles du dashboard Supabase
npm install
npm run typecheck
npm run build
npm run dev
```

Les CGV, mentions légales et la politique de confidentialité sont des modèles. Les champs entre crochets doivent être complétés par l'entreprise et validés avant publication. En particulier, le médiateur de la consommation, les durées de conservation, les informations légales et les modalités de livraison/paiement ne doivent pas être inventés.

## Site historique

Le site actuellement publié sur GitHub Pages reste à la racine du dépôt. Cette branche ne le supprime pas. Le nouveau site doit être validé avant toute modification de la production.
