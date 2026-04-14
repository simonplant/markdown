import { EditorView, keymap } from "@codemirror/view";
import { invoke } from "@tauri-apps/api/core";
import { open, save as saveDialog, ask } from "@tauri-apps/plugin-dialog";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { initEditor, getContent, setContent } from "./editor";
import { initPreview, togglePreview, updatePreview } from "./preview";
import { updateCurrentFilePath } from "./wikilinks";

let currentPath: string | null = null;
let editorView: EditorView;
let hasUnsavedChanges = false;
let closingConfirmed = false;
let suppressDirtyTracking = false;

// Auto-save state
let lastSavedHash: number = 0;
let autoSaveTimer: ReturnType<typeof setTimeout> | null = null;
const AUTO_SAVE_DELAY_MS = 2000;

// FNV-1a hash for content comparison
function fnv1aHash(str: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    hash ^= str.charCodeAt(i);
    hash = (hash * 0x01000193) >>> 0;
  }
  return hash;
}

function showSaveIndicator(): void {
  const el = document.getElementById("stat-save");
  if (!el) return;
  el.textContent = "Saved";
  el.style.opacity = "1";
  setTimeout(() => {
    el.style.opacity = "0";
  }, 2000);
}

function scheduleAutoSave(): void {
  if (autoSaveTimer !== null) {
    clearTimeout(autoSaveTimer);
  }
  // Skip untitled documents (no file path yet)
  if (!currentPath) return;

  autoSaveTimer = setTimeout(async () => {
    autoSaveTimer = null;
    if (!currentPath) return;

    const content = getContent();
    const hash = fnv1aHash(content);
    if (hash === lastSavedHash) return;

    try {
      await invoke("save_file", { path: currentPath, content });
      lastSavedHash = hash;
      hasUnsavedChanges = false;
      updateTitle();
      showSaveIndicator();
    } catch {
      // Auto-save failed silently — user can still save manually
    }
  }, AUTO_SAVE_DELAY_MS);
}

function updateTitle(): void {
  const filename = currentPath ? currentPath.split("/").pop() : "Untitled";
  const prefix = hasUnsavedChanges ? "\u25CF " : "";
  document.title = `${prefix}${filename} \u2014 Markdown`;
}

async function handleSaveAs(): Promise<boolean> {
  const path = await saveDialog({
    filters: [{ name: "Markdown", extensions: ["md"] }],
  });
  if (!path) return false;
  const content = getContent();
  await invoke("save_file", { path, content });
  currentPath = path;
  hasUnsavedChanges = false;
  lastSavedHash = fnv1aHash(content);
  if (autoSaveTimer !== null) { clearTimeout(autoSaveTimer); autoSaveTimer = null; }
  updateTitle();
  updateCurrentFilePath(editorView, currentPath);
  await invoke("add_recent_file", { path });
  return true;
}

async function handleSave(): Promise<void> {
  if (!currentPath) {
    await handleSaveAs();
    return;
  }
  const content = getContent();
  await invoke("save_file", { path: currentPath, content });
  hasUnsavedChanges = false;
  lastSavedHash = fnv1aHash(content);
  if (autoSaveTimer !== null) { clearTimeout(autoSaveTimer); autoSaveTimer = null; }
  updateTitle();
  await invoke("add_recent_file", { path: currentPath });
}

async function handleOpen(): Promise<void> {
  // Prompt for unsaved changes before replacing current content
  if (hasUnsavedChanges) {
    const filename = currentPath ? currentPath.split("/").pop() : "Untitled";
    const wantSave = await ask(
      `Do you want to save changes to "${filename}"?`,
      {
        title: "Unsaved Changes",
        kind: "warning",
        okLabel: "Save",
        cancelLabel: "Don\u2019t Save",
      },
    );
    if (wantSave) {
      if (currentPath) {
        await handleSave();
      } else {
        const saved = await handleSaveAs();
        if (!saved) return; // Cancelled save-as, abort open
      }
    }
  }

  const selected = await open({
    filters: [{ name: "Markdown", extensions: ["md"] }],
  });
  if (!selected) return;

  const text = await invoke<string>("open_file", { path: selected });
  suppressDirtyTracking = true;
  setContent(text);
  suppressDirtyTracking = false;
  currentPath = selected;
  hasUnsavedChanges = false;
  lastSavedHash = fnv1aHash(text);
  if (autoSaveTimer !== null) { clearTimeout(autoSaveTimer); autoSaveTimer = null; }
  updateTitle();
  updatePreview(text);
  updateCurrentFilePath(editorView, currentPath);

  await invoke("add_recent_file", { path: selected });
}

async function handleNew(): Promise<void> {
  await invoke("create_window", { filePath: null });
}

document.addEventListener("DOMContentLoaded", async () => {
  const editorEl = document.getElementById("editor")!;

  initPreview();

  const saveKeymap = keymap.of([
    {
      key: "Mod-s",
      run: () => {
        handleSave();
        return true;
      },
    },
    {
      key: "Mod-Shift-p",
      run: () => {
        togglePreview(getContent);
        return true;
      },
    },
  ]);

  // Track dirty state, update preview, and schedule auto-save
  const dirtyTracker = EditorView.updateListener.of((update) => {
    if (update.docChanged && !suppressDirtyTracking) {
      hasUnsavedChanges = true;
      updateTitle();
      updatePreview(update.state.doc.toString());
      scheduleAutoSave();
    }
  });

  editorView = initEditor(editorEl, [saveKeymap, dirtyTracker]);

  // Check for a pending file open (e.g. from Open Recent creating this window)
  try {
    const pendingPath = await invoke<string | null>("get_pending_open");
    if (pendingPath) {
      const text = await invoke<string>("open_file", { path: pendingPath });
      suppressDirtyTracking = true;
      setContent(text);
      suppressDirtyTracking = false;
      currentPath = pendingPath;
      hasUnsavedChanges = false;
      lastSavedHash = fnv1aHash(text);
      updateTitle();
      updatePreview(text);
      updateCurrentFilePath(editorView, currentPath);
    }
  } catch {
    // No pending open — start with empty document
  }

  document.getElementById("btn-open")!.addEventListener("click", handleOpen);
  document.getElementById("btn-preview")!.addEventListener("click", () => {
    togglePreview(getContent);
  });

  listen("menu-open", handleOpen);
  listen("menu-save", handleSave);
  listen("menu-new", handleNew);

  // Handle wikilink navigation events from wikilinks.ts.
  // This fires synchronously BEFORE the view.dispatch that changes content,
  // so we set suppressDirtyTracking here and clear it in a microtask after
  // the synchronous dispatch completes.
  window.addEventListener("wikilink-navigate", ((event: CustomEvent) => {
    const path = event.detail?.path;
    if (path) {
      suppressDirtyTracking = true;
      currentPath = path;
      hasUnsavedChanges = false;
      if (autoSaveTimer !== null) { clearTimeout(autoSaveTimer); autoSaveTimer = null; }
      updateTitle();
      // Re-enable dirty tracking after the synchronous view.dispatch completes
      queueMicrotask(() => {
        const content = getContent();
        lastSavedHash = fnv1aHash(content);
        updatePreview(content);
        suppressDirtyTracking = false;
      });
    }
  }) as EventListener);

  // Intercept window close to prompt for unsaved changes
  getCurrentWindow().onCloseRequested(async (event) => {
    if (closingConfirmed || !hasUnsavedChanges) return;

    event.preventDefault();

    const filename = currentPath ? currentPath.split("/").pop() : "Untitled";
    const wantSave = await ask(
      `Do you want to save changes to "${filename}"?`,
      {
        title: "Unsaved Changes",
        kind: "warning",
        okLabel: "Save",
        cancelLabel: "Don\u2019t Save",
      },
    );

    if (wantSave) {
      if (currentPath) {
        await handleSave();
      } else {
        const saved = await handleSaveAs();
        if (!saved) return; // Cancelled save-as dialog — abort close
      }
    }

    // Proceed with close (either saved or discarded)
    closingConfirmed = true;
    await invoke("close_current_window");
  });

  updateTitle();
});
