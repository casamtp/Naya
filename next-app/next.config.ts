import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  poweredByHeader: false,
  reactStrictMode: true,
  // Le site n'utilise pas d'optimisation d'images distante pour le moment.
  // Ajouter des domaines précis ici si next/image est introduit.
};

export default nextConfig;
