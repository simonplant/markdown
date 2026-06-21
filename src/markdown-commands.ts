import { EditorView } from "@codemirror/view";
import type { Command } from "@codemirror/view";
import { EditorSelection } from "@codemirror/state";

function wrapSelection(view: EditorView, mark: string): boolean {
  const { state } = view;
  const changes = state.changeByRange((range) => {
    const selected = state.sliceDoc(range.from, range.to);
    const len = mark.length;

    // Check if selection is already wrapped with exactly this mark. For the
    // single-char italic mark `*`, a `**…**` / `***…***` run is bold (or
    // bold+italic), not italic — don't strip a star from it (which would
    // silently downgrade **bold** to *bold* or delete a bare `**`).
    const doubled = mark[0] + mark[0];
    if (
      selected.length >= len * 2 &&
      selected.startsWith(mark) &&
      selected.endsWith(mark) &&
      !(len === 1 && (selected.startsWith(doubled) || selected.endsWith(doubled)))
    ) {
      const unwrapped = selected.slice(len, -len);
      return {
        changes: { from: range.from, to: range.to, insert: unwrapped },
        range: EditorSelection.range(range.from, range.from + unwrapped.length),
      };
    }

    // Also check if marks exist just outside the selection
    const before = state.sliceDoc(range.from - len, range.from);
    const after = state.sliceDoc(range.to, range.to + len);
    if (before === mark && after === mark) {
      return {
        changes: [
          { from: range.from - len, to: range.from, insert: "" },
          { from: range.to, to: range.to + len, insert: "" },
        ],
        range: EditorSelection.range(range.from - len, range.to - len),
      };
    }

    // Wrap: add marks around the selection
    const wrapped = mark + selected + mark;
    const cursorPos = range.from + len + selected.length;
    return {
      changes: { from: range.from, to: range.to, insert: wrapped },
      range: selected.length === 0
        ? EditorSelection.cursor(cursorPos)
        : EditorSelection.range(range.from, range.from + wrapped.length),
    };
  });

  view.dispatch(changes);
  return true;
}

export const toggleBold: Command = (view) => wrapSelection(view, "**");
export const toggleItalic: Command = (view) => wrapSelection(view, "*");
