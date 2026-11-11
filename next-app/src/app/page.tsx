import { Storefront } from "@/components/storefront";
import { supabasePublic } from "@/lib/supabase/public";

export const revalidate = 60;

export default async function HomePage() {
  const { data, error } = await supabasePublic
    .from("products")
    .select("id,slug,name,description,category,price_cents,stock_quantity,is_active")
    .eq("is_active", true)
    .order("category", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    console.error("NAYA public catalogue query failed:", error.code);
  }

  return <Storefront products={data ?? []} />;
}
