import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseAdmin } from "@/lib/supabase/admin";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const itemSchema = z.object({
  id: z.string().uuid(),
  qty: z.number().int().min(1).max(50)
}).strict();

const checkoutSchema = z.object({
  kind: z.enum(["grocery", "food"]),
  customer: z.object({
    name: z.string().trim().min(2).max(120),
    email: z.email().max(254),
    phone: z.string().trim().min(6).max(30)
  }).strict(),
  items: z.array(itemSchema).min(1).max(30),
  mode: z.enum(["home", "relay", "pickup"]),
  address: z.string().trim().max(500).optional(),
  relayCity: z.string().trim().max(120).optional(),
  relayName: z.string().trim().max(200).optional(),
  pickupDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  pickupSlot: z.string().trim().max(40).optional()
}).strict();

function errorResponse(message: string, status: number) {
  return NextResponse.json({ ok: false, error: message }, { status });
}

export async function POST(request: NextRequest) {
  // Défense CSRF : seuls les appels same-origin sont acceptés.
  const origin = request.headers.get("origin");
  const requestOrigin = new URL(request.url).origin;
  if (!origin || origin !== requestOrigin) {
    return errorResponse("Origine de requête refusée.", 403);
  }

  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > 16_384) {
    return errorResponse("Requête trop volumineuse.", 413);
  }

  if (!request.headers.get("content-type")?.includes("application/json")) {
    return errorResponse("Format de requête invalide.", 415);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse("Corps JSON invalide.", 400);
  }

  const parsed = checkoutSchema.safeParse(body);
  if (!parsed.success) {
    return errorResponse("Vérifie les coordonnées et les informations de commande.", 400);
  }

  const data = parsed.data;
  const isFood = data.kind === "food";

  if (isFood && data.mode !== "pickup") {
    return errorResponse("Les commandes traiteur sont à retirer en boutique.", 400);
  }
  if (!isFood && data.mode === "pickup") {
    return errorResponse("Choisis une livraison ou une demande Mondial Relay.", 400);
  }
  if (data.mode === "home" && !data.address) {
    return errorResponse("L'adresse de livraison est obligatoire.", 400);
  }
  if (data.mode === "relay" && (!data.relayCity || !data.relayName)) {
    return errorResponse("La ville et le point Mondial Relay sont obligatoires.", 400);
  }
  if (isFood && (!data.pickupDate || !data.pickupSlot)) {
    return errorResponse("La date et le créneau de retrait sont obligatoires.", 400);
  }

  try {
    const supabase = createSupabaseAdmin();
    const { data: order, error } = await supabase.rpc("create_customer_order", {
      p_customer_name: data.customer.name,
      p_customer_email: data.customer.email,
      p_customer_phone: data.customer.phone,
      p_mode: data.mode,
      p_items: data.items,
      p_address: data.mode === "home" ? data.address ?? null : null,
      p_relay_city: data.mode === "relay" ? data.relayCity ?? null : null,
      p_relay_name: data.mode === "relay" ? data.relayName ?? null : null,
      p_pickup_date: isFood ? data.pickupDate ?? null : null,
      p_pickup_slot: isFood ? data.pickupSlot ?? null : null
    });

    if (error) {
      const code = error.message ?? "";
      if (code.includes("ORDER_RATE_LIMITED")) {
        return errorResponse("Trop de commandes ont été envoyées avec ces coordonnées. Réessaie plus tard.", 429);
      }
      if (code.includes("STOCK_INSUFFICIENT") || code.includes("PRODUCT_UNAVAILABLE")) {
        return errorResponse("Un produit n'est plus disponible en quantité suffisante. Actualise le catalogue.", 409);
      }
      if (code.includes("PICKUP_MUST_BE_TOMORROW") || code.includes("PICKUP_SLOT_REQUIRED")) {
        return errorResponse("La date ou le créneau de retrait traiteur doit être corrigé.", 400);
      }
      // Ne pas renvoyer au navigateur le détail SQL ou les données personnelles.
      console.error("NAYA checkout RPC error:", error.code ?? "UNKNOWN");
      return errorResponse("La commande n'a pas pu être enregistrée. Réessaie ou contacte le magasin.", 400);
    }

    return NextResponse.json({ ok: true, order }, { status: 201, headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    console.error("NAYA checkout server error:", error instanceof Error ? error.message : "UNKNOWN");
    return errorResponse("Service momentanément indisponible.", 503);
  }
}
