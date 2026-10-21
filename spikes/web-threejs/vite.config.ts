import { defineConfig } from "vite";

export default defineConfig({
  // Relative base so the same build runs from Capacitor's WebView and any static host.
  base: "./",
  server: {
    allowedHosts: ["gungbuntu"],
    fs: { allow: ["../.."] },
  },
  build: {
    target: "es2022",
    chunkSizeWarningLimit: 4096,
  },
});
