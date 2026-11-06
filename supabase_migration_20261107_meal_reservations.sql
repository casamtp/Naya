-- Naya Market — demandes de réservation traiteur dans Supabase
-- Table dédiée pour préserver les champs du formulaire sans modifier le checkout épicerie.

CREATE TABLE IF NOT EXISTS public.meal_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_name text NOT NULL,
  customer_phone text NOT NULL,
  dish text NOT NULL,
  people integer,
  pickup_date date,
  comment text,
  status text NOT NULL DEFAULT 'nouvelle',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT meal_reservations_people_check CHECK (people IS NULL OR people BETWEEN 1 AND 100),
  CONSTRAINT meal_reservations_status_check CHECK (status IN ('nouvelle','confirmee','terminee','annulee'))
);

ALTER TABLE public.meal_reservations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can read meal reservations" ON public.meal_reservations;
CREATE POLICY "Admins can read meal reservations"
ON public.meal_reservations FOR SELECT TO authenticated
USING ((auth.jwt()->'app_metadata'->>'role') = 'admin');

DROP POLICY IF EXISTS "Admins can update meal reservations" ON public.meal_reservations;
CREATE POLICY "Admins can update meal reservations"
ON public.meal_reservations FOR UPDATE TO authenticated
USING ((auth.jwt()->'app_metadata'->>'role') = 'admin')
WITH CHECK ((auth.jwt()->'app_metadata'->>'role') = 'admin');

CREATE OR REPLACE FUNCTION public.create_meal_reservation(
  p_customer_name text,
  p_customer_phone text,
  p_dish text,
  p_people integer DEFAULT NULL,
  p_pickup_date date DEFAULT NULL,
  p_comment text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE v_id uuid;
BEGIN
  IF coalesce(btrim(p_customer_name),'') = '' OR coalesce(btrim(p_customer_phone),'') = '' OR coalesce(btrim(p_dish),'') = '' THEN
    RAISE EXCEPTION 'CUSTOMER_REQUIRED';
  END IF;
  IF length(btrim(p_customer_name)) > 120 OR length(btrim(p_customer_phone)) > 30 OR length(btrim(p_dish)) > 200 THEN
    RAISE EXCEPTION 'FIELD_TOO_LONG';
  END IF;
  IF p_people IS NOT NULL AND (p_people < 1 OR p_people > 100) THEN
    RAISE EXCEPTION 'INVALID_PEOPLE_COUNT';
  END IF;
  IF p_comment IS NOT NULL AND length(p_comment) > 2000 THEN
    RAISE EXCEPTION 'COMMENT_TOO_LONG';
  END IF;
  INSERT INTO public.meal_reservations(customer_name, customer_phone, dish, people, pickup_date, comment)
  VALUES (btrim(p_customer_name), btrim(p_customer_phone), btrim(p_dish), p_people, p_pickup_date, nullif(btrim(p_comment),''))
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'nouvelle');
END;
$function$;

REVOKE ALL ON FUNCTION public.create_meal_reservation(text,text,text,integer,date,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_meal_reservation(text,text,text,integer,date,text) TO anon, authenticated;
