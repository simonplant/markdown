/**
 * Wikilinks extension for CodeMirror 6.
 *
 * Detects [[filename]] syntax in the document and applies decorations
 * to make them visually distinct (link-styled). Supports Cmd+click
 * (or Ctrl+click) to navigate to the target file, and on-demand
 * backlink computation.
 *
 * This is a file navigation feature, not a PKM system. No graph view,
 * no tags database, no vault. Wikilinks resolve against plain .md files
 * in the directory tree.
 */

import {
  ViewPlugin,
  Decoration,
  EditorView,
  type DecorationSet,
  type ViewUpdate,
} from "@codemirror/view";
import { StateField, StateEffect, type Extension, type Range } from "@codemirror/state";
import { invoke } from "@tauri-apps/api/core";
import { ask } from "@tauri-apps/plugin-dialog";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface Backlink {
  path: string;
  line: number;
  context: string;
}

// ---------------------------------------------------------------------------
// Wikilink regex — matches [[...]] excluding newlines inside
// ---------------------------------------------------------------------------

const WIKILINK_RE = /\[\[([^\[\]\n]+?)\]\]/g;

// ---------------------------------------------------------------------------
// State for current file path (set from main.ts)
// ---------------------------------------------------------------------------

const setCurrentFilePath = StateEffect.define<string | null>();

const currentFilePathField = StateField.define<string | null>({
  create() {
    return null;
  },
  update(value, tr) {
    for (const e of tr.effects) {
      if (e.is(setCurrentFilePath)) return e.value;
    }
    return value;
  },
});

/** Update the current file path in the editor state (called from main.ts). */
export function updateCurrentFilePath(view: EditorView, path: string | null): void {
  view.dispatch({ effects: setCurrentFilePath.of(path) });
}

// ---------------------------------------------------------------------------
// Decoration builder
// ---------------------------------------------------------------------------

const wikilinkMark = Decoration.mark({ class: "cm-wikilink" });
const wikilinkBracketMark = Decoration.mark({ class: "cm-wikilink-bracket" });

function buildWikilinkDecorations(view: EditorView): DecorationSet {
  const decos: Range<Decoration>[] = [];
  const doc = view.state.doc;

  for (let i = 1; i <= doc.lines; i++) {
    const line = doc.line(i);
    const text = line.text;
    WIKILINK_RE.lastIndex = 0;

    let match: RegExpExecArray | null;
    while ((match = WIKILINK_RE.exec(text)) !== null) {
      const from = line.from + match.index;
      const to = from + match[0].length;
      const innerFrom = from + 2; // after [[
      const innerTo = to - 2; // before ]]

      // Opening brackets
      decos.push(wikilinkBracketMark.range(from, innerFrom));
      // Link text
      decos.push(wikilinkMark.range(innerFrom, innerTo));
      // Closing brackets
      decos.push(wikilinkBracketMark.range(innerTo, to));
    }
  }

  return Decoration.set(decos, true);
}

// ---------------------------------------------------------------------------
// ViewPlugin
// ---------------------------------------------------------------------------

const wikilinkPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;

    constructor(view: EditorView) {
      this.decorations = buildWikilinkDecorations(view);
    }

    update(update: ViewUpdate) {
      if (update.docChanged) {
        this.decorations = buildWikilinkDecorations(update.view);
      }
    }
  },
  {
    decorations: (v) => v.decorations,
  },
);

// ---------------------------------------------------------------------------
// Click handler: Cmd+click / Ctrl+click to navigate
// ---------------------------------------------------------------------------

function findWikilinkAtPos(
  view: EditorView,
  pos: number,
): string | null {
  const line = view.state.doc.lineAt(pos);
  const text = line.text;
  WIKILINK_RE.lastIndex = 0;

  let match: RegExpExecArray | null;
  while ((match = WIKILINK_RE.exec(text)) !== null) {
    const from = line.from + match.index;
    const to = from + match[0].length;
    if (pos >= from && pos <= to) {
      return match[1]; // The link text inside [[ ]]
    }
  }
  return null;
}

async function navigateToWikilink(view: EditorView, linkText: string): Promise<void> {
  const currentPath = view.state.field(currentFilePathField);
  if (!currentPath) return;

  try {
    const resolved = await invoke<string | null>("resolve_wikilink", {
      linkText,
      currentFilePath: currentPath,
    });

    if (resolved) {
      // Open the resolved file
      const text = await invoke<string>("open_file", { path: resolved });
      await invoke("add_recent_file", { path: resolved });

      // Notify main.ts BEFORE content change so it can suppress dirty tracking
      // (CustomEvent dispatch is synchronous)
      window.dispatchEvent(
        new CustomEvent("wikilink-navigate", { detail: { path: resolved } }),
      );

      // Dispatch content change
      view.dispatch({
        changes: { from: 0, to: view.state.doc.length, insert: text },
        effects: setCurrentFilePath.of(resolved),
      });
    } else {
      // Target doesn't exist — offer to create it
      const filename = linkText.endsWith(".md") ? linkText : `${linkText}.md`;
      const wantCreate = await ask(
        `"${filename}" does not exist. Create it?`,
        {
          title: "Create File",
          kind: "info",
          okLabel: "Create",
          cancelLabel: "Cancel",
        },
      );

      if (wantCreate) {
        const createdPath = await invoke<string>("create_wikilink_target", {
          linkText,
          currentFilePath: currentPath,
        });

        // Open the newly created file
        const text = await invoke<string>("open_file", { path: createdPath });
        await invoke("add_recent_file", { path: createdPath });

        // Notify main.ts BEFORE content change
        window.dispatchEvent(
          new CustomEvent("wikilink-navigate", { detail: { path: createdPath } }),
        );

        view.dispatch({
          changes: { from: 0, to: view.state.doc.length, insert: text },
          effects: setCurrentFilePath.of(createdPath),
        });
      }
    }
  } catch (err) {
    console.error("Wikilink navigation failed:", err);
  }
}

const wikilinkClickHandler = EditorView.domEventHandlers({
  click(event: MouseEvent, view: EditorView) {
    // Require Cmd (macOS) or Ctrl (Windows/Linux)
    if (!(event.metaKey || event.ctrlKey)) return false;

    const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
    if (pos === null) return false;

    const linkText = findWikilinkAtPos(view, pos);
    if (!linkText) return false;

    event.preventDefault();
    navigateToWikilink(view, linkText);
    return true;
  },
});

// Cursor style for Cmd+hover over wikilinks
const wikilinkCursorStyle = EditorView.domEventHandlers({
  mousemove(event: MouseEvent, view: EditorView) {
    const editorEl = view.dom;
    if (event.metaKey || event.ctrlKey) {
      const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
      if (pos !== null && findWikilinkAtPos(view, pos)) {
        editorEl.style.cursor = "pointer";
        return;
      }
    }
    editorEl.style.cursor = "";
  },
  keyup(_event: KeyboardEvent, view: EditorView) {
    view.dom.style.cursor = "";
  },
});

// ---------------------------------------------------------------------------
// Backlinks
// ---------------------------------------------------------------------------

/** Compute backlinks for the current file on demand. */
export async function computeBacklinks(view: EditorView): Promise<Backlink[]> {
  const currentPath = view.state.field(currentFilePathField);
  if (!currentPath) return [];

  try {
    return await invoke<Backlink[]>("compute_backlinks", {
      filePath: currentPath,
    });
  } catch (err) {
    console.error("Backlink computation failed:", err);
    return [];
  }
}

// ---------------------------------------------------------------------------
// Backlinks panel
// ---------------------------------------------------------------------------

class BacklinksPanel {
  private container: HTMLElement;
  private list: HTMLElement;
  private visible = false;

  constructor(private view: EditorView) {
    this.container = document.createElement("div");
    this.container.className = "cm-backlinks-panel";
    this.container.style.display = "none";

    const header = document.createElement("div");
    header.className = "cm-backlinks-header";
    header.textContent = "Backlinks";
    const closeBtn = document.createElement("button");
    closeBtn.className = "cm-backlinks-close";
    closeBtn.textContent = "\u00d7";
    closeBtn.addEventListener("click", () => this.hide());
    header.appendChild(closeBtn);

    this.list = document.createElement("div");
    this.list.className = "cm-backlinks-list";

    this.container.appendChild(header);
    this.container.appendChild(this.list);

    // Insert into the editor container
    const editorContainer = document.getElementById("editor-container");
    if (editorContainer) {
      editorContainer.appendChild(this.container);
    }
  }

  async toggle(): Promise<void> {
    if (this.visible) {
      this.hide();
    } else {
      await this.show();
    }
  }

  async show(): Promise<void> {
    this.list.innerHTML = "";
    const loading = document.createElement("div");
    loading.className = "cm-backlinks-loading";
    loading.textContent = "Scanning...";
    this.list.appendChild(loading);
    this.container.style.display = "flex";
    this.visible = true;

    const backlinks = await computeBacklinks(this.view);
    this.list.innerHTML = "";

    if (backlinks.length === 0) {
      const empty = document.createElement("div");
      empty.className = "cm-backlinks-empty";
      empty.textContent = "No backlinks found";
      this.list.appendChild(empty);
      return;
    }

    for (const bl of backlinks) {
      const item = document.createElement("div");
      item.className = "cm-backlinks-item";

      const filename = bl.path.split("/").pop() || bl.path;
      const nameEl = document.createElement("span");
      nameEl.className = "cm-backlinks-filename";
      nameEl.textContent = filename;

      const lineEl = document.createElement("span");
      lineEl.className = "cm-backlinks-line";
      lineEl.textContent = `:${bl.line}`;

      const ctxEl = document.createElement("div");
      ctxEl.className = "cm-backlinks-context";
      ctxEl.textContent = bl.context;

      item.appendChild(nameEl);
      item.appendChild(lineEl);
      item.appendChild(ctxEl);

      item.addEventListener("click", async () => {
        try {
          const text = await invoke<string>("open_file", { path: bl.path });
          await invoke("add_recent_file", { path: bl.path });
          this.view.dispatch({
            changes: { from: 0, to: this.view.state.doc.length, insert: text },
            effects: setCurrentFilePath.of(bl.path),
          });
          window.dispatchEvent(
            new CustomEvent("wikilink-navigate", { detail: { path: bl.path } }),
          );
        } catch (err) {
          console.error("Failed to open backlink:", err);
        }
      });

      this.list.appendChild(item);
    }
  }

  hide(): void {
    this.container.style.display = "none";
    this.visible = false;
  }

  destroy(): void {
    this.container.remove();
  }
}

let backlinksPanel: BacklinksPanel | null = null;

/** Toggle the backlinks panel visibility and compute backlinks on demand. */
export function toggleBacklinksPanel(view: EditorView): void {
  if (!backlinksPanel) {
    backlinksPanel = new BacklinksPanel(view);
  }
  backlinksPanel.toggle();
}

// ---------------------------------------------------------------------------
// Status bar integration
// ---------------------------------------------------------------------------

function addBacklinksButton(view: EditorView): void {
  const statusBar = document.getElementById("status-bar");
  if (!statusBar) return;

  const btn = document.createElement("span");
  btn.id = "stat-backlinks";
  btn.className = "cm-backlinks-btn";
  btn.textContent = "Backlinks";
  btn.style.cursor = "pointer";
  btn.addEventListener("click", () => toggleBacklinksPanel(view));

  // Insert before the save indicator (which has margin-left: auto)
  const saveEl = document.getElementById("stat-save");
  if (saveEl) {
    statusBar.insertBefore(btn, saveEl);
  } else {
    statusBar.appendChild(btn);
  }
}

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

const wikilinkLightTheme = EditorView.theme(
  {
    ".cm-wikilink": {
      color: "#0969DA",
      textDecoration: "underline",
      textDecorationColor: "rgba(9, 105, 218, 0.4)",
      cursor: "default",
    },
    ".cm-wikilink-bracket": {
      color: "rgba(9, 105, 218, 0.5)",
      fontSize: "0.9em",
    },
  },
  { dark: false },
);

const wikilinkDarkTheme = EditorView.theme(
  {
    ".cm-wikilink": {
      color: "#4FC1FF",
      textDecoration: "underline",
      textDecorationColor: "rgba(79, 193, 255, 0.4)",
      cursor: "default",
    },
    ".cm-wikilink-bracket": {
      color: "rgba(79, 193, 255, 0.5)",
      fontSize: "0.9em",
    },
  },
  { dark: true },
);

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

/** Wikilinks extension: decoration, click-to-navigate, backlinks. */
export function wikilinks(isDark: boolean): Extension {
  return [
    currentFilePathField,
    wikilinkPlugin,
    wikilinkClickHandler,
    wikilinkCursorStyle,
    isDark ? wikilinkDarkTheme : wikilinkLightTheme,
    // Add backlinks button to status bar after editor mounts
    EditorView.updateListener.of((update) => {
      if (update.view && !document.getElementById("stat-backlinks")) {
        addBacklinksButton(update.view);
      }
    }),
  ];
}
