import { defineConfig } from "deepsec/config";

export default defineConfig({
  projects: [
    { id: "g-play-web", root: ".." },
    // <deepsec:projects-insert-above>
  ],
});
