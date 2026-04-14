import { EditorView, keymap } from "@codemirror/view";
import { invoke } from "@tauri-apps/api/core";
import { open, save as saveDialog, ask } from "@tauri-apps/plugin-dialog";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { initEditor, getContent, setContent } from "./editor";

let currentPath: string | null = null;
let hasUnsavedChanges = false;
let closingConfirmed = false;
let suppressDirtyTracking = false;

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
  await invoke("save_file", { path, content: getContent() });
  currentPath = path;
  hasUnsavedChanges = false;
  updateTitle();
  await invoke("add_recent_file", { path });
  return true;
}

async function handleSave(): Promise<void> {
  if (!currentPath) {
    await handleSaveAs();
    return;
  }
  await invoke("save_file", { path: currentPath, content: getContent() });
  hasUnsavedChanges = false;
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
  updateTitle();

  await invoke("add_recent_file", { path: selected });
}

async function handleNew(): Promise<void> {
  await invoke("create_window", { filePath: null });
}

document.addEventListener("DOMContentLoaded", async () => {
  const editorEl = document.getElementById("editor")!;

  const saveKeymap = keymap.of([
    {
      key: "Mod-s",
      run: () => {
        handleSave();
        return true;
      },
    },
  ]);

  // Track dirty state via an editor update listener
  const dirtyTracker = EditorView.updateListener.of((update) => {
    if (update.docChanged && !suppressDirtyTracking) {
      hasUnsavedChanges = true;
      updateTitle();
    }
  });

  initEditor(editorEl, [saveKeymap, dirtyTracker]);

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
      updateTitle();
    }
  } catch {
    // No pending open — start with empty document
  }

  document.getElementById("btn-open")!.addEventListener("click", handleOpen);

  listen("menu-open", handleOpen);
  listen("menu-save", handleSave);
  listen("menu-new", handleNew);

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
