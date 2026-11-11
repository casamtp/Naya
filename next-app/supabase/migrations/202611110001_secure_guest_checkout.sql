-- NAYA — durcissement de l'accès aux données et checkout invité côté serveur
-- À appliquer UNIQUEMENT après déploiement et test de la route Next.js /api/orders.
-- Projet Supabase : vkmmbgkfpxogscyukvnc
--
-- Le schéma actuel ne possède ni user_id dans orders, ni table de panier.
-- Les paniers restent côté navigateur. Les visiteurs peuvent soumettre une
-- commande via l'API serveur, mais ne peuvent pas lire/modifier les commandes
-- après création. La gestion administrative reste réservée aux utilisateurs
-- authentifiés dont app_metadata.role = 'admin' selon les policies existantes.

begin;

-- 1. RLS explicite sur les tables applicatives exposées.
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.meal_reservations enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.site_analytics_events enable row level security;
alter table public.stock_alerts enable row level security;
alter table public.posts enable row level security;
alter table public.comments enable row level security;
alter table public.users enable row level security;

-- 2. Catalogue : lecture publique uniquement des produits actifs.
-- Les policies admin existantes pour les opérations de gestion sont conservées.
drop policy if exists "Public can view active products" on public.products;
create policy "Public can view active products"
  on public.products
  for select
  to anon, authenticated
  using (is_active = true);

grant select on public.products to anon, authenticated;

-- 2bis. Politiques administrateur : autorisation fondée sur app_metadata,
-- jamais sur user_metadata modifiable par l'utilisateur.
drop policy if exists "Admins can read all products" on public.products;
create policy "Admins can read all products" on public.products
  for select to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins can insert products" on public.products;
create policy "Admins can insert products" on public.products
  for insert to authenticated
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins can update product stock" on public.products;
create policy "Admins can update product stock" on public.products
  for update to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins can delete products" on public.products;
create policy "Admins can delete products" on public.products
  for delete to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins can read orders" on public.orders;
create policy "Admins can read orders" on public.orders
  for select to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins can update orders" on public.orders;
create policy "Admins can update orders" on public.orders
  for update to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins can read order items" on public.order_items;
create policy "Admins can read order items" on public.order_items
  for select to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins can read meal reservations" on public.meal_reservations;
create policy "Admins can read meal reservations" on public.meal_reservations
  for select to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins can update meal reservations" on public.meal_reservations;
create policy "Admins can update meal reservations" on public.meal_reservations
  for update to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Only admins can read analytics events" on public.site_analytics_events;
create policy "Only admins can read analytics events" on public.site_analytics_events
  for select to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins can read stock alerts" on public.stock_alerts;
create policy "Admins can read stock alerts" on public.stock_alerts
  for select to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- 3. Pas d'accès direct des visiteurs anonymes aux données de commande.
-- Les accès admin authentifiés existants sont conservés et restent filtrés par RLS.
revoke all on table public.orders from anon;
revoke all on table public.order_items from anon;
revoke all on table public.meal_reservations from anon;
revoke all on table public.push_subscriptions from anon;
revoke all on table public.stock_alerts from anon;

-- 4. Tables non nécessaires au parcours public : aucun accès direct client.
-- L'absence de policies RLS est volontaire pour ces tables internes/sociales.
revoke all on table public.push_subscriptions from anon, authenticated;
revoke all on table public.posts from anon, authenticated;
revoke all on table public.comments from anon, authenticated;
revoke all on table public.users from anon, authenticated;

-- 5. RPC de création : l'accès public est retiré.
-- Seul le serveur Next.js, via SUPABASE_SECRET_KEY, peut les appeler.
revoke all on function public.create_customer_order(
  text, text, text, text, jsonb, text, text, text, date, text
) from public, anon, authenticated;
grant execute on function public.create_customer_order(
  text, text, text, text, jsonb, text, text, text, date, text
) to service_role;

revoke all on function public.create_meal_reservation(
  text, text, text, integer, date, text
) from public, anon, authenticated;
grant execute on function public.create_meal_reservation(
  text, text, text, integer, date, text
) to service_role;

-- 6. Les fonctions internes "unlimited" ne sont jamais des endpoints API.
-- Les wrappers SECURITY DEFINER, détenus par postgres, les invoquent en interne.
revoke all on function public.create_customer_order_unlimited(
  text, text, text, text, jsonb, text, text, text, date, text
) from public, anon, authenticated, service_role;

revoke all on function public.create_meal_reservation_unlimited(
  text, text, text, integer, date, text
) from public, anon, authenticated, service_role;

-- 7. Helpers anti-abus privés : aucune exécution directe depuis les rôles API.
revoke all on function private.naya_check_order_rate_limit(text, text)
  from public, anon, authenticated, service_role;
revoke all on function private.naya_record_order_rate_limit(text, text)
  from public, anon, authenticated, service_role;
revoke all on function private.naya_check_reservation_rate_limit(text)
  from public, anon, authenticated, service_role;
revoke all on function private.naya_record_reservation_rate_limit(text)
  from public, anon, authenticated, service_role;

-- 8. La fonction event-trigger ne doit pas être une API exécutable.
revoke all on function public.rls_auto_enable()
  from public, anon, authenticated;

-- 9. Les tables commandes et réservations ne reçoivent aucune policy publique.
-- Les policies existantes "Admins can read/update ..." restent en place.
-- Analytics : la policy d'insertion publique avec contraintes reste en place.

commit;

-- Contrôles post-migration à exécuter séparément :
-- select * from pg_policies where schemaname='public' order by tablename, policyname;
-- select has_function_privilege('anon',
--   'public.create_customer_order(text,text,text,text,jsonb,text,text,text,date,text)', 'EXECUTE');
-- Résultat attendu : false.
-- select has_function_privilege('service_role',
--   'public.create_customer_order(text,text,text,text,jsonb,text,text,text,date,text)', 'EXECUTE');
-- Résultat attendu : true.
