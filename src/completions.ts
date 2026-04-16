import { EditorView, keymap } from "@codemirror/view";
import { type Extension } from "@codemirror/state";
import {
  isAiAvailable,
  isAiActionInProgress,
  aiContinue,
  setSuggestion,
  suggestionField,
} from "./ai";

// ---------------------------------------------------------------------------
// Debounced inline completion trigger
// ---------------------------------------------------------------------------

const DEBOUNCE_MS = 500;

let debounceTimer: ReturnType<typeof setTimeout> | null = null;
let requestGeneration = 0;

function cancelPendingCompletion(): void {
  if (debounceTimer !== null) {
    clearTimeout(debounceTimer);
    debounceTimer = null;
  }
  requestGeneration++;
}

function triggerCompletion(view: EditorView): void {
  if (!isAiAvailable() || isAiActionInProgress()) return;

  const cursorPos = view.state.selection.main.head;
  if (cursorPos === 0) return;

  // Don't trigger if there's already a suggestion showing
  if (view.state.field(suggestionField)) return;

  const gen = ++requestGeneration;

  const textBefore = view.state.sliceDoc(
    Math.max(0, cursorPos - 2000),
    cursorPos,
  );

  aiContinue(textBefore)
    .then((continuation) => {
      // Discard if a newer request was made or user typed further
      if (gen !== requestGeneration) return;
      if (!continuation || continuation.trim() === "") return;

      view.dispatch({
        effects: setSuggestion.of({
          from: cursorPos,
          to: cursorPos,
          text: continuation,
        }),
      });
    })
    .catch(() => {
      // Silently ignore — completions are a background feature
    });
}

// ---------------------------------------------------------------------------
// Partial accept (Cmd+Right / Ctrl+Right) — accept one word at a time
// ---------------------------------------------------------------------------

function partialAccept(view: EditorView): boolean {
  const suggestion = view.state.field(suggestionField);
  if (!suggestion) return false;

  const text = suggestion.text;
  let end = 0;

  // Skip leading whitespace
  while (end < text.length && /\s/.test(text[end])) end++;
  // Skip to end of word
  while (end < text.length && !/\s/.test(text[end])) end++;

  if (end === 0) end = text.length;

  const acceptedText = text.slice(0, end);
  const remainingText = text.slice(end);

  if (remainingText.length === 0) {
    // Accept entire remaining suggestion
    view.dispatch({
      changes: { from: suggestion.from, to: suggestion.to, insert: suggestion.text },
      effects: setSuggestion.of(null),
    });
  } else {
    // Accept partial — insert the word and update the suggestion to the remainder
    const newPos = suggestion.from + acceptedText.length;
    view.dispatch({
      changes: { from: suggestion.from, to: suggestion.to, insert: acceptedText },
      effects: setSuggestion.of({
        from: newPos,
        to: newPos,
        text: remainingText,
      }),
    });
  }

  return true;
}

// ---------------------------------------------------------------------------
// Update listener — schedule completion on typing pauses
// ---------------------------------------------------------------------------

const completionListener = EditorView.updateListener.of((update) => {
  if (update.docChanged) {
    cancelPendingCompletion();

    if (!isAiAvailable()) return;

    debounceTimer = setTimeout(() => {
      triggerCompletion(update.view);
    }, DEBOUNCE_MS);
  }
});

// ---------------------------------------------------------------------------
// Combined completions extension
// ---------------------------------------------------------------------------

export function completionsExtension(): Extension {
  return [
    completionListener,
    keymap.of([
      { key: "Mod-ArrowRight", run: partialAccept },
    ]),
  ];
}
