/**
 * Web / PWA entry point for Markdown.
 *
 * Replaces Tauri IPC with browser-native file handling:
 *  - File System Access API (showOpenFilePicker / showSaveFilePicker) on Chromium
 *  - <input type="file"> / download-as-file fallback on Firefox / Safari
 */

import "./style.css";
import { EditorView, keymap } from "@codemirror/view";
import { initEditor, getContent, setContent } from "./editor";
import { initPreview, togglePreview, updatePreview } from "./preview";

let currentHandle: FileSystemFileHandle | null = null;
let currentFilename: string | null = null;
let editorView: EditorView;
let hasUnsavedChanges = false;

// FNV-1a hash for content comparison
function fnv1aHash(str: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    hash ^= str.charCodeAt(i);
    hash = (hash * 0x01000193) >>> 0;
  }
  return hash;
}

let lastSavedHash: number = 0;

function showSaveIndicator(): void {
  const el = document.getElementById("stat-save");
  if (!el) return;
  el.textContent = "Saved";
  el.style.opacity = "1";
  setTimeout(() => {
    el.style.opacity = "0";
  }, 2000);
}

function updateTitle(): void {
  const filename = currentFilename || "Untitled";
  const prefix = hasUnsavedChanges ? "\u25CF " : "";
  document.title = `${prefix}${filename} \u2014 Markdown`;
}

// --- File System Access API detection ---

function hasFileSystemAccess(): boolean {
  return "showOpenFilePicker" in window;
}

// --- Open ---

async function openWithFSA(): Promise<void> {
  const [handle] = await window.showOpenFilePicker({
    types: [
      {
        description: "Markdown",
        accept: { "text/markdown": [".md", ".markdown"] },
      },
    ],
    multiple: false,
  });
  const file = await handle.getFile();
  const text = await file.text();
  currentHandle = handle;
  currentFilename = file.name;
  setContent(text);
  hasUnsavedChanges = false;
  lastSavedHash = fnv1aHash(text);
  updateTitle();
  updatePreview(text);
}

async function openWithFallback(): Promise<void> {
  return new Promise<void>((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = ".md,.markdown,text/markdown";
    input.onchange = async () => {
      const file = input.files?.[0];
      if (!file) {
        resolve();
        return;
      }
      const text = await file.text();
      currentHandle = null;
      currentFilename = file.name;
      setContent(text);
      hasUnsavedChanges = false;
      lastSavedHash = fnv1aHash(text);
      updateTitle();
      updatePreview(text);
      resolve();
    };
    // Handle cancel (no change event fires)
    input.oncancel = () => resolve();
    input.click();
  });
}

async function handleOpen(): Promise<void> {
  if (hasUnsavedChanges) {
    const filename = currentFilename || "Untitled";
    if (!confirm(`You have unsaved changes to "${filename}". Discard and open a new file?`)) {
      return;
    }
  }

  try {
    if (hasFileSystemAccess()) {
      await openWithFSA();
    } else {
      await openWithFallback();
    }
  } catch (e: unknown) {
    // User cancelled the picker — not an error
    if (e instanceof DOMException && e.name === "AbortError") return;
    throw e;
  }
}

// --- Save ---

async function saveWithFSA(): Promise<void> {
  if (!currentHandle) {
    await saveAsWithFSA();
    return;
  }
  const content = getContent();
  const writable = await currentHandle.createWritable();
  await writable.write(content);
  await writable.close();
  hasUnsavedChanges = false;
  lastSavedHash = fnv1aHash(content);
  updateTitle();
  showSaveIndicator();
}

async function saveAsWithFSA(): Promise<void> {
  const handle = await window.showSaveFilePicker({
    suggestedName: currentFilename || "untitled.md",
    types: [
      {
        description: "Markdown",
        accept: { "text/markdown": [".md", ".markdown"] },
      },
    ],
  });
  currentHandle = handle;
  currentFilename = handle.name;
  const content = getContent();
  const writable = await handle.createWritable();
  await writable.write(content);
  await writable.close();
  hasUnsavedChanges = false;
  lastSavedHash = fnv1aHash(content);
  updateTitle();
  showSaveIndicator();
}

function saveWithFallback(): void {
  const content = getContent();
  const blob = new Blob([content], { type: "text/markdown" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = currentFilename || "untitled.md";
  a.click();
  URL.revokeObjectURL(url);
  hasUnsavedChanges = false;
  lastSavedHash = fnv1aHash(content);
  updateTitle();
  showSaveIndicator();
}

async function handleSave(): Promise<void> {
  try {
    if (hasFileSystemAccess()) {
      await saveWithFSA();
    } else {
      saveWithFallback();
    }
  } catch (e: unknown) {
    if (e instanceof DOMException && e.name === "AbortError") return;
    throw e;
  }
}

// --- Init ---

document.addEventListener("DOMContentLoaded", () => {
  const editorEl = document.getElementById("editor")!;

  initPreview();

  const saveKeymap = keymap.of([
    {
      key: "Mod-s",
      run: () => {
        handleSave();
        return true;
      },
      preventDefault: true,
    },
    {
      key: "Mod-Shift-p",
      run: () => {
        togglePreview(getContent);
        return true;
      },
    },
  ]);

  const dirtyTracker = EditorView.updateListener.of((update) => {
    if (update.docChanged) {
      hasUnsavedChanges = true;
      updateTitle();
      updatePreview(update.state.doc.toString());
    }
  });

  editorView = initEditor(editorEl, [saveKeymap, dirtyTracker]);

  document.getElementById("btn-open")!.addEventListener("click", handleOpen);
  document.getElementById("btn-preview")!.addEventListener("click", () => {
    togglePreview(getContent);
  });

  // Warn before leaving with unsaved changes
  window.addEventListener("beforeunload", (e) => {
    if (hasUnsavedChanges) {
      e.preventDefault();
    }
  });

  updateTitle();

  // Register service worker for PWA offline support
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("/sw.js").catch(() => {
      // Service worker registration failed — app still works without offline support
    });
  }
});
