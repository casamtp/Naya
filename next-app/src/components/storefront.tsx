"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";

type Product = {
  id: string;
  slug: string | null;
  name: string;
  description: string | null;
  category: string;
  price_cents: number;
  stock_quantity: number;
  is_active: boolean;
};

type Kind = "grocery" | "food";
type Cart = Record<string, number>;

const FOOD_CATEGORIES = new Set(["traiteur", "tajine", "couscous", "patisserie", "patisseries"]);

function productKind(product: Product): Kind {
  return FOOD_CATEGORIES.has((product.category ?? "").trim().toLowerCase()) ? "food" : "grocery";
}

function euro(cents: number) {
  return new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" }).format(cents / 100);
}

function nextFoodDate() {
  const date = new Date();
  date.setDate(date.getDate() + 1);
  if (date.getDay() === 1) date.setDate(date.getDate() + 1);
  return date.toISOString().slice(0, 10);
}

export function Storefront({ products }: { products: Product[] }) {
  const [groceryCart, setGroceryCart] = useState<Cart>({});
  const [foodCart, setFoodCart] = useState<Cart>({});
  const [activeCart, setActiveCart] = useState<Kind>("grocery");
  const [ready, setReady] = useState(false);
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);
  const [mode, setMode] = useState<"home" | "relay">("home");

  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [address, setAddress] = useState("");
  const [relayCity, setRelayCity] = useState("");
  const [relayName, setRelayName] = useState("");
  const [pickupDate, setPickupDate] = useState(nextFoodDate());
  const [pickupSlot, setPickupSlot] = useState("");

  useEffect(() => {
    try {
      setGroceryCart(JSON.parse(localStorage.getItem("naya:grocery-cart") ?? "{}"));
      setFoodCart(JSON.parse(localStorage.getItem("naya:food-cart") ?? "{}"));
    } catch {
      setGroceryCart({});
      setFoodCart({});
    }
    setReady(true);
  }, []);

  useEffect(() => {
    if (!ready) return;
    localStorage.setItem("naya:grocery-cart", JSON.stringify(groceryCart));
  }, [groceryCart, ready]);

  useEffect(() => {
    if (!ready) return;
    localStorage.setItem("naya:food-cart", JSON.stringify(foodCart));
  }, [foodCart, ready]);

  const activeItems = activeCart === "grocery" ? groceryCart : foodCart;
  const selectedProducts = useMemo(
    () => products.filter((product) => activeItems[product.id] > 0),
    [products, activeItems]
  );
  const subtotal = selectedProducts.reduce(
    (sum, product) => sum + product.price_cents * activeItems[product.id],
    0
  );
  const deliveryFee = activeCart === "grocery" && mode === "home" && selectedProducts.length ? 490 : 0;
  const total = subtotal + deliveryFee;
  const groceryCount = Object.values(groceryCart).reduce((sum, qty) => sum + qty, 0);
  const foodCount = Object.values(foodCart).reduce((sum, qty) => sum + qty, 0);

  function add(product: Product) {
    const kind = productKind(product);
    const update = kind === "food" ? setFoodCart : setGroceryCart;
    const current = kind === "food" ? foodCart : groceryCart;
    const nextQty = (current[product.id] ?? 0) + 1;
    if (!product.is_active || nextQty > product.stock_quantity) {
      setStatus("Stock insuffisant pour cet article.");
      return;
    }
    update((cart) => ({ ...cart, [product.id]: nextQty }));
    setActiveCart(kind);
    setStatus("");
  }

  function changeQty(product: Product, delta: number) {
    const update = activeCart === "food" ? setFoodCart : setGroceryCart;
    const current = activeCart === "food" ? foodCart : groceryCart;
    const nextQty = (current[product.id] ?? 0) + delta;
    if (nextQty > product.stock_quantity) {
      setStatus("Stock insuffisant.");
      return;
    }
    update((cart) => {
      const next = { ...cart };
      if (nextQty <= 0) delete next[product.id];
      else next[product.id] = nextQty;
      return next;
    });
    setStatus("");
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedProducts.length || busy) return;
    setBusy(true);
    setStatus("");

    const isFood = activeCart === "food";
    const payload = {
      kind: activeCart,
      customer: { name, email, phone },
      mode: isFood ? "pickup" : mode,
      address: mode === "home" ? address : undefined,
      relayCity: mode === "relay" ? relayCity : undefined,
      relayName: mode === "relay" ? relayName : undefined,
      pickupDate: isFood ? pickupDate : undefined,
      pickupSlot: isFood ? pickupSlot : undefined,
      items: selectedProducts.map((product) => ({
        id: product.id,
        qty: activeItems[product.id]
      }))
    };

    try {
      const response = await fetch("/api/orders", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      const result = await response.json();
      if (!response.ok || !result.ok) {
        setStatus(result.error ?? "La commande n'a pas pu être enregistrée.");
        return;
      }

      if (isFood) setFoodCart({});
      else setGroceryCart({});
      setStatus(`Demande enregistrée : ${result.order.order_number}. Le magasin doit encore confirmer la commande.`);
    } catch {
      setStatus("Connexion indisponible. Réessaie dans quelques instants.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="store">
      <header className="hero">
        <p className="eyebrow">Épicerie fine · Produits orientaux · Traiteur</p>
        <h1>Naya Market</h1>
        <p>Le meilleur de l'Orient à Saint-Jean-de-Védas.</p>
        <a className="button button-light" href="tel:0767934154">Appeler le magasin · 07 67 93 41 54</a>
      </header>

      <section className="intro">
        <div>
          <p className="eyebrow">La boutique</p>
          <h2>Découvrez nos produits et spécialités</h2>
          <p>Consultez le catalogue et préparez votre demande de commande en ligne.</p>
        </div>
        <div className="address-card">
          <strong>Nous trouver</strong>
          <span>12 avenue de la Libération</span>
          <span>34430 Saint-Jean-de-Védas</span>
        </div>
      </section>

      <section className="catalog">
        <div className="section-heading">
          <div><p className="eyebrow">Catalogue</p><h2>Nos produits</h2></div>
          <div className="cart-counts">
            <button onClick={() => setActiveCart("grocery")} className={activeCart === "grocery" ? "selected" : ""}>Épicerie ({groceryCount})</button>
            <button onClick={() => setActiveCart("food")} className={activeCart === "food" ? "selected" : ""}>Traiteur ({foodCount})</button>
          </div>
        </div>

        {products.length === 0 ? <p>Le catalogue sera bientôt disponible.</p> : (
          <div className="product-grid">
            {products.map((product) => (
              <article className="product-card" key={product.id}>
                <span className="tag">{productKind(product) === "food" ? "Traiteur" : "Épicerie"}</span>
                <h3>{product.name}</h3>
                {product.description && <p>{product.description}</p>}
                <div className="product-bottom">
                  <strong>{euro(product.price_cents)}</strong>
                  <button disabled={!product.is_active || product.stock_quantity <= 0} onClick={() => add(product)}>
                    {product.stock_quantity <= 0 ? "Indisponible" : "Ajouter"}
                  </button>
                </div>
              </article>
            ))}
          </div>
        )}
      </section>

      <section className="checkout">
        <div className="section-heading">
          <div><p className="eyebrow">Votre sélection</p><h2>Panier {activeCart === "food" ? "traiteur" : "épicerie"}</h2></div>
          <span className="tag">{activeCart === "food" ? "Retrait en boutique" : "Livraison / relais"}</span>
        </div>
        {selectedProducts.length === 0 ? <p className="empty">Ce panier est vide. Les paniers épicerie et traiteur sont indépendants.</p> : (
          <div className="basket">
            {selectedProducts.map((product) => (
              <div className="basket-row" key={product.id}>
                <div><strong>{product.name}</strong><small>{euro(product.price_cents)} l'unité</small></div>
                <div className="quantity">
                  <button type="button" onClick={() => changeQty(product, -1)} aria-label={`Retirer un ${product.name}`}>−</button>
                  <span>{activeItems[product.id]}</span>
                  <button type="button" onClick={() => changeQty(product, 1)} aria-label={`Ajouter un ${product.name}`}>+</button>
                </div>
                <strong>{euro(product.price_cents * activeItems[product.id])}</strong>
              </div>
            ))}
            <div className="totals"><span>Sous-total</span><strong>{euro(subtotal)}</strong></div>
            {activeCart === "grocery" && <div className="totals"><span>Frais de livraison</span><strong>{euro(deliveryFee)}</strong></div>}
            <div className="totals total"><span>Total estimatif</span><strong>{euro(total)}</strong></div>
          </div>
        )}

        <form className="checkout-form" onSubmit={submit}>
          <h3>Coordonnées</h3>
          <div className="form-grid">
            <label>Nom et prénom<input required minLength={2} maxLength={120} value={name} onChange={(e) => setName(e.target.value)} /></label>
            <label>Adresse e-mail<input required type="email" maxLength={254} value={email} onChange={(e) => setEmail(e.target.value)} /></label>
            <label>Téléphone<input required type="tel" maxLength={30} value={phone} onChange={(e) => setPhone(e.target.value)} /></label>
          </div>

          {activeCart === "grocery" ? (
            <>
              <h3>Mode de réception</h3>
              <div className="radio-row">
                <label><input type="radio" checked={mode === "home"} onChange={() => setMode("home")} /> Livraison à domicile (4,90 €)</label>
                <label><input type="radio" checked={mode === "relay"} onChange={() => setMode("relay")} /> Demande Mondial Relay</label>
              </div>
              {mode === "home" ? (
                <label>Adresse de livraison<textarea required maxLength={500} value={address} onChange={(e) => setAddress(e.target.value)} /></label>
              ) : (
                <div className="form-grid">
                  <label>Ville du relais<input required maxLength={120} value={relayCity} onChange={(e) => setRelayCity(e.target.value)} /></label>
                  <label>Nom du point relais<input required maxLength={200} value={relayName} onChange={(e) => setRelayName(e.target.value)} /></label>
                </div>
              )}
            </>
          ) : (
            <>
              <h3>Retrait traiteur</h3>
              <div className="form-grid">
                <label>Date souhaitée<input required type="date" min={nextFoodDate()} value={pickupDate} onChange={(e) => setPickupDate(e.target.value)} /></label>
                <label>Créneau souhaité<input required placeholder="Ex. 12h00–12h30" maxLength={40} value={pickupSlot} onChange={(e) => setPickupSlot(e.target.value)} /></label>
              </div>
            </>
          )}

          <p className="notice">Aucun paiement en ligne n'est activé. Il s'agit d'une demande de commande qui reste à confirmer par le magasin.</p>
          <button className="button" disabled={!selectedProducts.length || busy} type="submit">{busy ? "Envoi…" : "Envoyer ma demande"}</button>
          {status && <p className="status" role="status">{status}</p>}
        </form>
      </section>

      <section className="gallery">
        <p className="eyebrow">En images</p><h2>Découvrez notre magasin</h2>
        <p>Les photographies réelles du magasin seront ajoutées après réception.</p>
        <div className="gallery-grid"><div>Le magasin · Photo à venir</div><div>Nos rayons · Photo à venir</div><div>Nos produits · Photo à venir</div><div>Nos spécialités · Photo à venir</div></div>
      </section>

      <footer className="footer">
        <div><strong>Naya Market</strong><p>12 avenue de la Libération, 34430 Saint-Jean-de-Védas</p><p>07 67 93 41 54</p></div>
        <nav><a href="/mentions-legales">Mentions légales</a><a href="/cgv">CGV</a><a href="/politique-de-confidentialite">Confidentialité</a></nav>
      </footer>
    </div>
  );
}
