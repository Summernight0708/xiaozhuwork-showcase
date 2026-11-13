import * as Sentry from "@sentry/vue";
import { createPinia } from "pinia";
import {
  Badge,
  Button,
  Cell,
  CellGroup,
  Checkbox,
  CheckboxGroup,
  Divider,
  DropdownItem,
  DropdownMenu,
  Empty,
  Field,
  Form,
  Icon,
  Loading,
  NoticeBar,
  Popup,
  Radio,
  RadioGroup,
  Search,
  Switch,
  Tab,
  Tabs,
  Tag,
} from "vant";
import "vant/lib/index.css";
import { createApp } from "vue";

import App from "./App.vue";
import "./assets/main.css";
import { initializeNativeApp } from "./platform/native-app";
import { router } from "./router";
import { initializeAppearance } from "./services/appearance";
import { initializeUmami } from "./services/telemetry/umami";
import {
  sanitizeSentryBreadcrumb,
  sanitizeSentryEvent,
} from "./services/telemetry/sentry";

initializeAppearance();

const app = createApp(App);
const pinia = createPinia();

if (import.meta.env.VITE_SENTRY_DSN) {
  Sentry.init({
    app,
    dsn: import.meta.env.VITE_SENTRY_DSN,
    sendDefaultPii: false,
    beforeSend: sanitizeSentryEvent,
    beforeBreadcrumb: sanitizeSentryBreadcrumb,
  });
}

initializeUmami(router, {
  hostUrl: import.meta.env.VITE_UMAMI_HOST_URL ?? "",
  websiteId: import.meta.env.VITE_UMAMI_WEBSITE_ID ?? "",
});

[
  Badge,
  Button,
  Cell,
  CellGroup,
  Checkbox,
  CheckboxGroup,
  Divider,
  DropdownItem,
  DropdownMenu,
  Empty,
  Field,
  Form,
  Icon,
  Loading,
  NoticeBar,
  Popup,
  Radio,
  RadioGroup,
  Search,
  Switch,
  Tab,
  Tabs,
  Tag,
].forEach((plugin) => app.use(plugin));

app.use(pinia);
app.use(router);
app.mount("#app");
void initializeNativeApp(router);
