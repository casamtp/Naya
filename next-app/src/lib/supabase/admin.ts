import "server-only";
import { createClient } from "@supabase/supabase-js";

/**
 * Client serveur réservé aux Route Handlers.
 * SUPABASE_SECRET_KEY ne doit jamais être exposée au navigateur.
 * Les RPC appelées par ce client sont limitées à service_role en SQL.
 */
export function createSupabaseAdmin() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const secret = process.env.SUPABASE_SECRET_KEY;

  if (!url || !secret) {
    throw new Error("Configuration serveur Supabase manquante.");
  }

  return createClient(url, secret, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false
    },
    global: {
      headers: { "X-Client-Info": "naya-market-next-server" }
    }
  });
}
