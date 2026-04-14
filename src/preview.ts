/**
 * Live rendered markdown preview panel.
 *
 * Converts editor content to HTML via `marked` and displays it
 * in the #preview div. Toggleable via the Preview button or
 * Cmd+Shift+P.
 */

import { marked } from "marked";

// Configure marked for GFM (tables, strikethrough, task lists)
marked.setOptions({
  gfm: true,
  breaks: false,
});

let previewEl: HTMLElement;
let visible = false;

export function initPreview(): void {
  previewEl = document.getElementById("preview")!;
}

export function isPreviewVisible(): boolean {
  return visible;
}

export function togglePreview(getContent: () => string): void {
  visible = !visible;
  if (visible) {
    previewEl.classList.add("visible");
    updatePreview(getContent());
  } else {
    previewEl.classList.remove("visible");
  }
}

export function updatePreview(markdown: string): void {
  if (!visible || !previewEl) return;
  previewEl.innerHTML = marked.parse(markdown) as string;

  // Make checkboxes match the source (they render as disabled by default from GFM)
  previewEl.querySelectorAll('input[type="checkbox"]').forEach((cb) => {
    (cb as HTMLInputElement).disabled = true;
  });
}
