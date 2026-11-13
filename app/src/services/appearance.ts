export type AppearancePreference = "light" | "dark" | "system";

const STORAGE_KEY = "xiaozhuwork-appearance";
const LEGACY_STORAGE_KEY = "teamup-appearance";

export function getAppearancePreference(): AppearancePreference {
  const stored =
    localStorage.getItem(STORAGE_KEY) ??
    localStorage.getItem(LEGACY_STORAGE_KEY);
  return stored === "light" || stored === "dark" || stored === "system"
    ? stored
    : "system";
}

export function applyAppearance(preference: AppearancePreference) {
  const dark =
    preference === "dark" ||
    (preference === "system" &&
      window.matchMedia("(prefers-color-scheme: dark)").matches);
  document.documentElement.dataset.theme = dark ? "dark" : "light";
}

export function saveAppearancePreference(preference: AppearancePreference) {
  localStorage.setItem(STORAGE_KEY, preference);
  localStorage.removeItem(LEGACY_STORAGE_KEY);
  applyAppearance(preference);
}

export function initializeAppearance() {
  const preference = getAppearancePreference();
  if (
    localStorage.getItem(STORAGE_KEY) === null &&
    localStorage.getItem(LEGACY_STORAGE_KEY) !== null
  ) {
    saveAppearancePreference(preference);
  }
  applyAppearance(preference);
  const media = window.matchMedia("(prefers-color-scheme: dark)");
  media.addEventListener("change", () => {
    if (getAppearancePreference() === "system") applyAppearance("system");
  });
}
