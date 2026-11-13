import type { ObjectDirective } from "vue";

type Listeners = {
  pointerDown: (event: PointerEvent) => void;
  keyDown: (event: KeyboardEvent) => void;
};

const listeners = new WeakMap<HTMLDetailsElement, Listeners>();

// Native <details> retains summary-click toggling and keyboard access.
// Only dropdown menus opt in; ordinary disclosure sections stay unchanged.
export const vDismissibleDetails: ObjectDirective<HTMLDetailsElement> = {
  mounted(element) {
    const pointerDown = (event: PointerEvent) => {
      if (
        element.open &&
        event.target instanceof Node &&
        !element.contains(event.target)
      ) {
        element.open = false;
      }
    };
    const keyDown = (event: KeyboardEvent) => {
      if (element.open && event.key === "Escape") {
        element.open = false;
        element.querySelector("summary")?.focus();
      }
    };
    document.addEventListener("pointerdown", pointerDown, true);
    document.addEventListener("keydown", keyDown);
    listeners.set(element, { pointerDown, keyDown });
  },
  unmounted(element) {
    const callbacks = listeners.get(element);
    if (!callbacks) return;
    document.removeEventListener("pointerdown", callbacks.pointerDown, true);
    document.removeEventListener("keydown", callbacks.keyDown);
    listeners.delete(element);
  },
};
