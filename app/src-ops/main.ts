import { createPinia } from "pinia";
import { createApp } from "vue";

import App from "@ops/App.vue";
import "@ops/assets/main.css";
import { opsRouter } from "@ops/router";

const app = createApp(App);
app.use(createPinia());
app.use(opsRouter);
app.mount("#app");
