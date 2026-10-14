import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { dirname, basename, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const experimentRoot = dirname(fileURLToPath(import.meta.url));
const outputRoot =
  basename(dirname(experimentRoot)) === "experiments"
    ? resolve(experimentRoot, "../..")
    : experimentRoot;

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: resolve(outputRoot, ".local/algorithm-workbench/dist"),
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    strictPort: true,
    proxy: { "/api": "http://127.0.0.1:8787" },
  },
});
