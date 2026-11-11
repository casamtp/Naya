import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Naya Market | Épicerie orientale et traiteur à Saint-Jean-de-Védas",
  description: "Découvrez les produits orientaux, pâtisseries et plats traiteur de Naya Market à Saint-Jean-de-Védas."
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="fr">
      <body>{children}</body>
    </html>
  );
}
