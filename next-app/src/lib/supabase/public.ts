import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

if (!url || !key) {
  throw new Error("Configuration publique Supabase manquante.");
}

/**
 * Client public : lecture du catalogue actif uniquement via les politiques RLS.
 * Ne jamais utiliser une clé secrète/service_role dans ce module.
 */
export const supabasePublic = createClient(url, key, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false
  }
});
