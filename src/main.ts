import { EditorView, keymap } from "@codemirror/view";
import { invoke } from "@tauri-apps/api/core";
import { open, save as saveDialog, ask, message } from "@tauri-apps/plugin-dialog";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { initEditor, getContent, setContent } from "./editor";
import { initPreview, togglePreview, updatePreview } from "./preview";
import { updateCurrentFilePath } from "./wikilinks";
import { checkAiModel, initAiEngine, setAiAvailable } from "./ai";
import { loadSettings, openSettings, updateAiStatusIndicator } from "./settings";

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
  startWatchingCurrentFile();
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
  startWatchingCurrentFile();
}

async function handleNew(): Promise<void> {
  await invoke("create_window", { filePath: null });
}

async function startWatchingCurrentFile(): Promise<void> {
  if (!currentPath) return;
  try {
    await invoke("start_watching", { path: currentPath });
  } catch {
    // File watching is best-effort — editor works without it
  }
}

async function handleFileChangedExternally(kind: string, path: string): Promise<void> {
  // Ignore events for a different file (e.g. stale event after navigation)
  if (path !== currentPath) return;

  if (kind === "deleted") {
    await message(
      "This file has been deleted or moved from disk.\n\nYou can save your current content to a new location using File > Save As.",
      { title: "File Deleted", kind: "warning" },
    );
    return;
  }

  // kind === "modified"
  if (!hasUnsavedChanges) {
    // No unsaved changes — reload silently
    try {
      const text = await invoke<string>("open_file", { path });
      suppressDirtyTracking = true;
      setContent(text);
      suppressDirtyTracking = false;
      hasUnsavedChanges = false;
      lastSavedHash = fnv1aHash(text);
      if (autoSaveTimer !== null) { clearTimeout(autoSaveTimer); autoSaveTimer = null; }
      updateTitle();
      updatePreview(text);
    } catch {
      // File may have been deleted between event and reload attempt
    }
    return;
  }

  // Unsaved changes exist — show conflict dialog
  const reload = await ask(
    "This file was changed externally.\n\nReload the external version or keep your changes?",
    {
      title: "File Changed Externally",
      kind: "warning",
      okLabel: "Reload External Version",
      cancelLabel: "Keep My Version",
    },
  );

  if (reload) {
    // Reload the external version
    try {
      const text = await invoke<string>("open_file", { path });
      suppressDirtyTracking = true;
      setContent(text);
      suppressDirtyTracking = false;
      hasUnsavedChanges = false;
      lastSavedHash = fnv1aHash(text);
      if (autoSaveTimer !== null) { clearTimeout(autoSaveTimer); autoSaveTimer = null; }
      updateTitle();
      updatePreview(text);
    } catch {
      // File may have been deleted
    }
  } else {
    // User chose "Keep My Version" — offer to show diff
    const showDiff = await ask(
      "Would you like to see the external version for comparison?",
      {
        title: "Show Diff",
        okLabel: "Show External Version",
        cancelLabel: "Dismiss",
      },
    );
    if (showDiff) {
      // Open the external version in a new window for side-by-side comparison
      try {
        await invoke("create_window", { filePath: path });
      } catch {
        // Best effort
      }
    }
  }
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
      startWatchingCurrentFile();
    }
  } catch {
    // No pending open — start with empty document
  }

  document.getElementById("btn-open")!.addEventListener("click", handleOpen);
  document.getElementById("btn-preview")!.addEventListener("click", () => {
    togglePreview(getContent);
  });
  document.getElementById("btn-settings")!.addEventListener("click", openSettings);

  // AI mode indicator click opens settings
  const aiModeEl = document.getElementById("stat-ai-mode");
  if (aiModeEl) aiModeEl.addEventListener("click", openSettings);

  listen("menu-open", handleOpen);
  listen("menu-save", handleSave);
  listen("menu-new", handleNew);

  // Listen for external file change events from the backend file watcher
  listen<{ kind: string; path: string }>("file-changed-externally", (event) => {
    handleFileChangedExternally(event.payload.kind, event.payload.path);
  });

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
      startWatchingCurrentFile();
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

  // Initialize AI: check cloud config first, then fall back to local model
  loadSettings().then(async (config) => {
    if (config?.use_cloud) {
      // Cloud mode — check if there's an API key
      try {
        const key = await invoke<string>("load_api_key");
        if (key) {
          setAiAvailable(true);
          updateAiStatusIndicator();
          return;
        }
      } catch {
        // Keyring not available — fall through to local
      }
    }
    // Try local model
    const available = await checkAiModel();
    if (available) {
      await initAiEngine().catch(() => {});
    }
    updateAiStatusIndicator();
  });

  updateTitle();
});
