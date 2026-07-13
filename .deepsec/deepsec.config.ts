import { defineConfig } from "deepsec/config";

export default defineConfig({
  projects: [
    { id: "vantabeat", root: ".." },
    // <deepsec:projects-insert-above>
  ],
});
