import {
  EditorView,
  Decoration,
  WidgetType,
  keymap,
} from "@codemirror/view";
import { StateField, StateEffect, type Extension } from "@codemirror/state";
import { invoke } from "@tauri-apps/api/core";

// ---------------------------------------------------------------------------
// AI model status
// ---------------------------------------------------------------------------

interface AiModelStatus {
  available: boolean;
  download_url: string;
}

let aiAvailable = false;

export async function checkAiModel(): Promise<boolean> {
  try {
    const status = await invoke<AiModelStatus>("ai_check_model");
    aiAvailable = status.available;
    return status.available;
  } catch {
    aiAvailable = false;
    return false;
  }
}

export async function initAiEngine(): Promise<boolean> {
  try {
    const ok = await invoke<boolean>("ai_init");
    aiAvailable = ok;
    return ok;
  } catch {
    aiAvailable = false;
    return false;
  }
}

/** Mark AI as available (called when cloud config has a key). */
export function setAiAvailable(available: boolean): void {
  aiAvailable = available;
}

export function isAiAvailable(): boolean {
  return aiAvailable;
}

// ---------------------------------------------------------------------------
// AI actions — invoke Tauri commands
// ---------------------------------------------------------------------------

export async function aiImprove(
  selectedText: string,
  context: string,
): Promise<string> {
  return invoke<string>("ai_improve", {
    selectedText,
    context,
  });
}

export async function aiSummarize(text: string): Promise<string> {
  return invoke<string>("ai_summarize", { text });
}

export async function aiContinue(text: string): Promise<string> {
  return invoke<string>("ai_continue", { text });
}

// ---------------------------------------------------------------------------
// Inline suggestion state (ghost text / accept-reject)
// ---------------------------------------------------------------------------

export interface AiSuggestion {
  from: number;
  to: number;
  text: string;
}

export const setSuggestion = StateEffect.define<AiSuggestion | null>();

class GhostTextWidget extends WidgetType {
  constructor(readonly text: string) {
    super();
  }
  toDOM(): HTMLElement {
    const span = document.createElement("span");
    span.className = "cm-ai-ghost-text";
    span.textContent = this.text;
    return span;
  }
  ignoreEvent(): boolean {
    return true;
  }
}

export const suggestionField = StateField.define<AiSuggestion | null>({
  create() {
    return null;
  },
  update(value, tr) {
    for (const e of tr.effects) {
      if (e.is(setSuggestion)) return e.value;
    }
    // Clear suggestion on any document change not caused by accepting
    if (tr.docChanged) return null;
    return value;
  },
});

const suggestionDecoration = EditorView.decorations.compute(
  [suggestionField],
  (state) => {
    const suggestion = state.field(suggestionField);
    if (!suggestion) return Decoration.none;

    const deco = Decoration.widget({
      widget: new GhostTextWidget(suggestion.text),
      side: 1,
    });
    return Decoration.set([deco.range(suggestion.to)]);
  },
);

// ---------------------------------------------------------------------------
// Accept / Reject keybindings
// ---------------------------------------------------------------------------

function acceptSuggestion(view: EditorView): boolean {
  const suggestion = view.state.field(suggestionField);
  if (!suggestion) return false;

  // Insert the suggestion text, replacing the original range
  view.dispatch({
    changes: { from: suggestion.from, to: suggestion.to, insert: suggestion.text },
    effects: setSuggestion.of(null),
  });
  return true;
}

function rejectSuggestion(view: EditorView): boolean {
  const suggestion = view.state.field(suggestionField);
  if (!suggestion) return false;

  view.dispatch({ effects: setSuggestion.of(null) });
  return true;
}

// ---------------------------------------------------------------------------
// AI action handlers (called from keyboard shortcuts)
// ---------------------------------------------------------------------------

let aiInProgress = false;

export function isAiActionInProgress(): boolean {
  return aiInProgress;
}

function showAiStatus(message: string): void {
  const el = document.getElementById("stat-ai");
  if (!el) return;
  el.textContent = message;
  el.style.opacity = "1";
}

function hideAiStatus(): void {
  if (aiErrorActive) return; // Don't hide if an error is being displayed
  const el = document.getElementById("stat-ai");
  if (!el) return;
  el.style.opacity = "0";
}

let aiErrorActive = false;

function showAiError(err: unknown): void {
  const el = document.getElementById("stat-ai");
  if (!el) return;
  const msg = typeof err === "string" ? err : String(err);
  // Truncate long error messages for the status bar
  const short = msg.length > 100 ? msg.slice(0, 100) + "\u2026" : msg;
  el.textContent = short;
  el.style.opacity = "1";
  el.style.color = "#cf222e";
  aiErrorActive = true;
  setTimeout(() => {
    el.style.opacity = "0";
    el.style.color = "";
    aiErrorActive = false;
  }, 6000);
}

export function runImprove(view: EditorView): boolean {
  if (!aiAvailable || aiInProgress) return false;

  const { from, to } = view.state.selection.main;
  if (from === to) return false; // No selection

  const selectedText = view.state.sliceDoc(from, to);
  // Get surrounding context (up to 200 chars before and after)
  const contextStart = Math.max(0, from - 200);
  const contextEnd = Math.min(view.state.doc.length, to + 200);
  const context = view.state.sliceDoc(contextStart, contextEnd);

  aiInProgress = true;
  showAiStatus("AI: Improving\u2026");

  aiImprove(selectedText, context)
    .then((improved) => {
      view.dispatch({
        effects: setSuggestion.of({ from, to, text: improved }),
      });
    })
    .catch((err) => {
      console.error("AI improve failed:", err);
      showAiError(err);
    })
    .finally(() => {
      aiInProgress = false;
      hideAiStatus();
    });

  return true;
}

export function runSummarize(view: EditorView): boolean {
  if (!aiAvailable || aiInProgress) return false;

  const { from, to } = view.state.selection.main;
  const text =
    from === to ? view.state.doc.toString() : view.state.sliceDoc(from, to);

  aiInProgress = true;
  showAiStatus("AI: Summarizing\u2026");

  aiSummarize(text)
    .then((summary) => {
      // Insert summary at cursor position (or after selection)
      const insertPos = to;
      const prefix = "\n\n**Summary:** ";
      view.dispatch({
        effects: setSuggestion.of({
          from: insertPos,
          to: insertPos,
          text: prefix + summary,
        }),
      });
    })
    .catch((err) => {
      console.error("AI summarize failed:", err);
      showAiError(err);
    })
    .finally(() => {
      aiInProgress = false;
      hideAiStatus();
    });

  return true;
}

export function runContinue(view: EditorView): boolean {
  if (!aiAvailable || aiInProgress) return false;

  const cursorPos = view.state.selection.main.head;
  // Get text up to cursor for context
  const textBefore = view.state.sliceDoc(
    Math.max(0, cursorPos - 2000),
    cursorPos,
  );

  aiInProgress = true;
  showAiStatus("AI: Writing\u2026");

  aiContinue(textBefore)
    .then((continuation) => {
      view.dispatch({
        effects: setSuggestion.of({
          from: cursorPos,
          to: cursorPos,
          text: continuation,
        }),
      });
    })
    .catch((err) => {
      console.error("AI continue failed:", err);
      showAiError(err);
    })
    .finally(() => {
      aiInProgress = false;
      hideAiStatus();
    });

  return true;
}

// ---------------------------------------------------------------------------
// Ghost text CSS theme
// ---------------------------------------------------------------------------

const aiTheme = EditorView.theme({
  ".cm-ai-ghost-text": {
    opacity: "0.5",
    fontStyle: "italic",
  },
});

// ---------------------------------------------------------------------------
// Combined AI extension for CodeMirror
// ---------------------------------------------------------------------------

export function aiExtension(): Extension {
  return [
    suggestionField,
    suggestionDecoration,
    aiTheme,
    keymap.of([
      { key: "Tab", run: acceptSuggestion },
      { key: "Escape", run: rejectSuggestion },
      { key: "Mod-Shift-i", run: runImprove },
      { key: "Mod-Shift-u", run: runSummarize },
      { key: "Mod-Shift-Enter", run: runContinue },
    ]),
  ];
}
