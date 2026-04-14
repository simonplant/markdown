/**
 * WYSIWYM decorations for CodeMirror 6.
 *
 * Hides markdown syntax characters (# ** * ` [] ()) when the cursor
 * is not within the same parent node. Cursor proximity reveals markers
 * so the user can edit them; moving away hides them again for a clean
 * reading view.
 *
 * This is HyperMD-style WYSIWYM — the text always remains markdown
 * source. We decorate, not transform.
 *
 * Reduced motion: when prefers-reduced-motion: reduce is active,
 * all markers stay visible (no hiding).
 */

import {
  ViewPlugin,
  Decoration,
  EditorView,
  type DecorationSet,
  type ViewUpdate,
} from "@codemirror/view";
import { syntaxTree } from "@codemirror/language";
import type { Extension, Range } from "@codemirror/state";

const hiddenMark = Decoration.mark({ class: "cm-hidden-marker" });

/** Lezer node types that represent syntax markers we want to hide. */
const MARKER_TYPES = new Set([
  "HeaderMark",
  "EmphasisMark",
  "CodeMark",
  "LinkMark",
  "QuoteMark",
]);

function buildDecorations(view: EditorView): DecorationSet {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    return Decoration.none;
  }

  const head = view.state.selection.main.head;
  const decorations: Range<Decoration>[] = [];

  syntaxTree(view.state).iterate({
    enter(node) {
      if (!MARKER_TYPES.has(node.name)) return;

      const parent = node.node.parent;
      if (parent && head >= parent.from && head <= parent.to) {
        return; // cursor is proximate — keep markers visible
      }

      decorations.push(hiddenMark.range(node.from, node.to));
    },
  });

  return Decoration.set(decorations, true);
}

const wysiwymPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;

    constructor(view: EditorView) {
      this.decorations = buildDecorations(view);
    }

    update(update: ViewUpdate) {
      if (update.docChanged || update.selectionSet) {
        this.decorations = buildDecorations(update.view);
      }
    }
  },
  {
    decorations: (v) => v.decorations,
  }
);

const wysiwymBaseTheme = EditorView.baseTheme({
  ".cm-hidden-marker": {
    opacity: "0",
  },
});

/** WYSIWYM decorations extension — hides syntax markers on cursor distance. */
export function wysiwym(): Extension {
  return [wysiwymPlugin, wysiwymBaseTheme];
}
