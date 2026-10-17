-- Naya Market: liaison catalogue, stock et commandes
-- Projet Supabase : vkmmbgkfpxogscyukvnc
-- Tables products/orders/order_items déjà créées dans le projet.

alter table public.products add column if not exists slug text;
update public.products set slug = case name
 when 'Huile d’olive (1 L)' then 'huile-olive'
 when 'Olives marinées (1 kg)' then 'olives'
 when 'Baklava assortiment' then 'baklava'
 when 'Cornes de gazelle' then 'cornes'
 when 'Grand plateau fête' then 'plateau'
 when 'Makrout dattes/miel' then 'makrout'
 when 'Tajine poulet' then 'tajine-poulet'
 when 'Tajine kefta' then 'tajine-kefta'
 when 'Tajine bœuf' then 'tajine-boeuf'
 when 'Tajine agneau' then 'tajine-agneau'
 else lower(trim(both '-' from regexp_replace(name, '[^a-zA-Z0-9]+', '-', 'g')))
 end where slug is null;
create unique index if not exists products_slug_unique on public.products(slug);

-- Mondial Relay reste une demande : frais et disponibilité à confirmer manuellement.
alter table public.orders drop constraint if exists orders_fulfillment_method_check;
alter table public.orders add constraint orders_fulfillment_method_check
 check (fulfillment_method = any (array['livraison','retrait','relay']));
alter table public.orders drop constraint if exists orders_delivery_fee_rules;
alter table public.orders add constraint orders_delivery_fee_rules check (
 (fulfillment_method='livraison' and delivery_fee_cents=490 and delivery_address is not null)
 or (fulfillment_method='retrait' and delivery_fee_cents=0)
 or (fulfillment_method='relay' and delivery_fee_cents=0)
);
alter table public.orders drop constraint if exists orders_fulfillment_rules;
alter table public.orders add constraint orders_fulfillment_rules check (
 (order_type='epicerie' and fulfillment_method in ('livraison','retrait','relay'))
 or (order_type='plat' and fulfillment_method='retrait' and pickup_date is not null and pickup_slot is not null)
);

drop function if exists public.create_customer_order(text,text,text,jsonb,text,text,text,date,text);
create function public.create_customer_order(
 p_customer_name text, p_customer_email text, p_customer_phone text, p_mode text, p_items jsonb,
 p_address text default null, p_relay_city text default null, p_relay_name text default null,
 p_pickup_date date default null, p_pickup_slot text default null
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_item jsonb; v_product public.products%rowtype; v_order_id uuid; v_subtotal integer:=0; v_fee integer:=0; v_has_food boolean:=false; v_has_grocery boolean:=false; v_qty integer; v_method text; v_type text;
begin
 if coalesce(trim(p_customer_name),'')='' or coalesce(trim(p_customer_email),'')='' or coalesce(trim(p_customer_phone),'')='' then raise exception 'CUSTOMER_REQUIRED'; end if;
 if length(trim(p_customer_name))>120 or length(trim(p_customer_email))>254 or length(trim(p_customer_phone))>30 then raise exception 'CUSTOMER_FIELD_TOO_LONG'; end if;
 if p_mode not in ('pickup','home','relay') then raise exception 'INVALID_FULFILLMENT'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>30 then raise exception 'EMPTY_OR_TOO_LARGE_ORDER'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
  if coalesce(v_item->>'id','') !~* '^[0-9a-f-]{36}$' or coalesce(v_item->>'qty','') !~ '^[0-9]+$' then raise exception 'INVALID_ITEM'; end if;
  v_qty:=(v_item->>'qty')::integer; if v_qty<1 or v_qty>50 then raise exception 'INVALID_QUANTITY'; end if;
  select * into v_product from public.products where id=(v_item->>'id')::uuid and is_active=true for update;
  if not found then raise exception 'PRODUCT_UNAVAILABLE'; end if;
  if v_product.stock_quantity<v_qty then raise exception 'STOCK_INSUFFICIENT'; end if;
  v_subtotal:=v_subtotal+v_product.price_cents*v_qty;
  if v_product.category in ('tajine','couscous','patisserie') then v_has_food:=true; else v_has_grocery:=true; end if;
 end loop;
 if v_has_food and v_has_grocery then raise exception 'MIXED_BASKET_NOT_ALLOWED'; end if;
 if v_has_food then
  if p_mode<>'pickup' then raise exception 'FOOD_PICKUP_ONLY'; end if;
  if p_pickup_date is distinct from ((now() at time zone 'Europe/Paris')::date+1) then raise exception 'PICKUP_MUST_BE_TOMORROW'; end if;
  if coalesce(trim(p_pickup_slot),'')='' then raise exception 'PICKUP_SLOT_REQUIRED'; end if;
 end if;
 if p_mode='home' then if not v_has_grocery or v_has_food then raise exception 'GROCERY_DELIVERY_ONLY'; end if; if coalesce(trim(p_address),'')='' then raise exception 'ADDRESS_REQUIRED'; end if; v_fee:=490; v_method:='livraison';
 elsif p_mode='relay' then if not v_has_grocery or v_has_food then raise exception 'GROCERY_RELAY_ONLY'; end if; if coalesce(trim(p_relay_city),'')='' then raise exception 'RELAY_CITY_REQUIRED'; end if; v_method:='relay';
 else v_method:='retrait'; end if;
 v_type:=case when v_has_food then 'plat' else 'epicerie' end;
 insert into public.orders(customer_name,customer_phone,customer_email,order_type,fulfillment_method,delivery_address,pickup_date,pickup_slot,delivery_fee_cents,subtotal_cents,total_cents,status)
 values(trim(p_customer_name),trim(p_customer_phone),trim(p_customer_email),v_type,v_method,
 case when p_mode='home' then trim(p_address) when p_mode='relay' then concat('Mondial Relay demandé — ',trim(p_relay_city),case when coalesce(trim(p_relay_name),'')<>'' then ' — '||trim(p_relay_name) else '' end) else null end,
 case when v_has_food then p_pickup_date else null end,case when v_has_food then p_pickup_slot else null end,v_fee,v_subtotal,v_subtotal+v_fee,'nouvelle') returning id into v_order_id;
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_qty:=(v_item->>'qty')::integer; select * into v_product from public.products where id=(v_item->>'id')::uuid and is_active=true for update;
  update public.products set stock_quantity=stock_quantity-v_qty,updated_at=now() where id=v_product.id;
  insert into public.order_items(order_id,product_id,product_name,quantity,unit_price_cents,line_total_cents) values(v_order_id,v_product.id,v_product.name,v_qty,v_product.price_cents*v_qty,v_product.price_cents*v_qty);
 end loop;
 return jsonb_build_object('id',v_order_id,'order_number',upper(substr(replace(v_order_id::text,'-',''),1,8)),'subtotal_cents',v_subtotal,'delivery_fee_cents',v_fee,'total_cents',v_subtotal+v_fee);
end; $$;
revoke all on function public.create_customer_order(text,text,text,text,jsonb,text,text,text,date,text) from public;
grant execute on function public.create_customer_order(text,text,text,text,jsonb,text,text,text,date,text) to anon, authenticated;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
