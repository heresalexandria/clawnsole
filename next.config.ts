import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Electron packages this traced server rather than shipping a second renderer.
  // The normal `next dev` and `next start` workflows are unchanged.
  output: "standalone",
};

export default nextConfig;
