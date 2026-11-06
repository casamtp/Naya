-- Naya Market — alignement checkout Supabase
-- Appliqué au projet vkmmbgkfpxogscyukvnc le 2026-11-06.
-- Ne modifie pas les commandes ni les stocks existants.
-- Livraison à domicile : 4,90 € ; Mondial Relay : 0 € ; retrait : 0 €.

CREATE OR REPLACE FUNCTION public.create_customer_order(
 p_customer_name text, p_customer_email text, p_customer_phone text, p_mode text, p_items jsonb,
 p_address text DEFAULT NULL, p_relay_city text DEFAULT NULL, p_relay_name text DEFAULT NULL,
 p_pickup_date date DEFAULT NULL, p_pickup_slot text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
 v_item jsonb; v_product public.products%rowtype; v_order_id uuid;
 v_subtotal integer := 0; v_fee integer := 0;
 v_has_food boolean := false; v_has_grocery boolean := false;
 v_qty integer; v_method text; v_type text;
BEGIN
 IF coalesce(btrim(p_customer_name),'')='' OR coalesce(btrim(p_customer_email),'')='' OR coalesce(btrim(p_customer_phone),'')='' THEN RAISE EXCEPTION 'CUSTOMER_REQUIRED'; END IF;
 IF length(btrim(p_customer_name))>120 OR length(btrim(p_customer_email))>254 OR length(btrim(p_customer_phone))>30 THEN RAISE EXCEPTION 'CUSTOMER_FIELD_TOO_LONG'; END IF;
 IF btrim(p_customer_email) !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+[.][A-Z]{2,}$' THEN RAISE EXCEPTION 'INVALID_EMAIL'; END IF;
 IF p_mode IS NULL OR p_mode NOT IN ('pickup','home','relay') THEN RAISE EXCEPTION 'INVALID_FULFILLMENT'; END IF;
 IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 OR jsonb_array_length(p_items)>30 THEN RAISE EXCEPTION 'EMPTY_OR_TOO_LARGE_ORDER'; END IF;
 IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_items) AS x(item) GROUP BY x.item->>'id' HAVING count(*)>1) THEN RAISE EXCEPTION 'DUPLICATE_PRODUCT'; END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
   IF jsonb_typeof(v_item)<>'object' OR coalesce(v_item->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' OR coalesce(v_item->>'qty','') !~ '^[0-9]+$' THEN RAISE EXCEPTION 'INVALID_ITEM'; END IF;
   v_qty := (v_item->>'qty')::integer;
   IF v_qty<1 OR v_qty>50 THEN RAISE EXCEPTION 'INVALID_QUANTITY'; END IF;
   SELECT * INTO v_product FROM public.products WHERE id=(v_item->>'id')::uuid AND is_active=true FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'PRODUCT_UNAVAILABLE'; END IF;
   IF v_product.stock_quantity<v_qty THEN RAISE EXCEPTION 'STOCK_INSUFFICIENT'; END IF;
   v_subtotal := v_subtotal + v_product.price_cents*v_qty;
   IF lower(btrim(coalesce(v_product.category,''))) IN ('traiteur','tajine','couscous','patisserie','patisseries') THEN v_has_food:=true; ELSE v_has_grocery:=true; END IF;
 END LOOP;
 IF v_has_food AND v_has_grocery THEN RAISE EXCEPTION 'MIXED_BASKET_NOT_ALLOWED'; END IF;
 IF v_has_grocery AND NOT v_has_food AND p_mode NOT IN ('relay','home') THEN RAISE EXCEPTION 'GROCERY_RELAY_ONLY'; END IF;
 IF v_has_food THEN
   IF p_mode<>'pickup' THEN RAISE EXCEPTION 'FOOD_PICKUP_ONLY'; END IF;
   IF p_pickup_date IS DISTINCT FROM (((now() AT TIME ZONE 'Europe/Paris')::date+1)+CASE WHEN extract(isodow FROM ((now() AT TIME ZONE 'Europe/Paris')::date+1))=1 THEN 1 ELSE 0 END) THEN RAISE EXCEPTION 'PICKUP_MUST_BE_TOMORROW'; END IF;
   IF coalesce(btrim(p_pickup_slot),'')='' OR length(btrim(p_pickup_slot))>40 THEN RAISE EXCEPTION 'PICKUP_SLOT_REQUIRED'; END IF;
 END IF;
 IF p_mode='home' THEN
   IF NOT v_has_grocery OR v_has_food THEN RAISE EXCEPTION 'GROCERY_RELAY_ONLY'; END IF;
   IF coalesce(btrim(p_address),'')='' OR length(btrim(p_address))>500 THEN RAISE EXCEPTION 'ADDRESS_REQUIRED'; END IF;
   v_fee:=490; v_method:='livraison';
 ELSIF p_mode='relay' THEN
   IF NOT v_has_grocery OR v_has_food THEN RAISE EXCEPTION 'GROCERY_RELAY_ONLY'; END IF;
   IF coalesce(btrim(p_relay_city),'')='' OR length(btrim(p_relay_city))>120 THEN RAISE EXCEPTION 'RELAY_CITY_REQUIRED'; END IF;
   IF coalesce(btrim(p_relay_name),'')='' OR length(btrim(p_relay_name))>200 THEN RAISE EXCEPTION 'RELAY_NAME_REQUIRED'; END IF;
   v_fee:=0; v_method:='relay';
 ELSE v_method:='retrait';
 END IF;
 v_type:=CASE WHEN v_has_food THEN 'plat' ELSE 'epicerie' END;
 INSERT INTO public.orders(customer_name,customer_phone,customer_email,order_type,fulfillment_method,delivery_address,pickup_date,pickup_slot,delivery_fee_cents,subtotal_cents,total_cents,status)
 VALUES(btrim(p_customer_name),btrim(p_customer_phone),lower(btrim(p_customer_email)),v_type,v_method,
   CASE WHEN p_mode='home' THEN btrim(p_address) WHEN p_mode='relay' THEN 'Mondial Relay demandé — '||btrim(p_relay_city)||' — '||btrim(p_relay_name) ELSE NULL END,
   CASE WHEN v_has_food THEN p_pickup_date ELSE NULL END,CASE WHEN v_has_food THEN btrim(p_pickup_slot) ELSE NULL END,
   v_fee,v_subtotal,v_subtotal+v_fee,'nouvelle') RETURNING id INTO v_order_id;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
   v_qty:=(v_item->>'qty')::integer;
   SELECT * INTO v_product FROM public.products WHERE id=(v_item->>'id')::uuid AND is_active=true FOR UPDATE;
   UPDATE public.products SET stock_quantity=stock_quantity-v_qty,updated_at=now() WHERE id=v_product.id AND is_active=true AND stock_quantity>=v_qty;
   IF NOT FOUND THEN RAISE EXCEPTION 'STOCK_INSUFFICIENT'; END IF;
   INSERT INTO public.order_items(order_id,product_id,product_name,quantity,unit_price_cents,line_total_cents) VALUES(v_order_id,v_product.id,v_product.name,v_qty,v_product.price_cents*v_qty,v_product.price_cents*v_qty);
 END LOOP;
 RETURN jsonb_build_object('id',v_order_id,'order_number',upper(substr(replace(v_order_id::text,'-',''),1,8)),'subtotal_cents',v_subtotal,'delivery_fee_cents',v_fee,'total_cents',v_subtotal+v_fee);
END;
$function$;
