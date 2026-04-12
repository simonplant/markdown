import { keymap } from "@codemirror/view";
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { listen } from "@tauri-apps/api/event";
import { initEditor, getContent, setContent } from "./editor";

let currentPath: string | null = null;

async function handleOpen(): Promise<void> {
  const selected = await open({
    filters: [{ name: "Markdown", extensions: ["md"] }],
  });
  if (!selected) return;

  const text = await invoke<string>("open_file", { path: selected });
  setContent(text);
  currentPath = selected;
}

async function handleSave(): Promise<void> {
  if (!currentPath) return;
  await invoke("save_file", { path: currentPath, content: getContent() });
}

document.addEventListener("DOMContentLoaded", () => {
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

  initEditor(editorEl, [saveKeymap]);

  document.getElementById("btn-open")!.addEventListener("click", handleOpen);

  listen("menu-open", handleOpen);
  listen("menu-save", handleSave);
});
