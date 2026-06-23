/**
 * Read mode — the default view when a .md file is opened (D-UX-1, DP-3).
 *
 * Read mode renders the document: syntax markers hidden everywhere (not just
 * near the cursor), editing disabled, selection and copy still work on the
 * rendered text. A single click transitions to author mode with the cursor
 * placed at the click position. Cmd+E (platform-idiomatic Mod-e) toggles.
 *
 * Under prefers-reduced-motion, the mode swap is instant rather than faded.
 */

import {
  ViewPlugin,
  Decoration,
  EditorView,
  type DecorationSet,
  type ViewUpdate,
} from "@codemirror/view";
import { syntaxTree } from "@codemirror/language";
import {
  Annotation,
  Compartment,
  EditorState,
  StateEffect,
  StateField,
  type Extension,
  type Range,
} from "@codemirror/state";

/** Lezer node types representing syntax markers we hide in read mode. */
const MARKER_TYPES = new Set([
  "HeaderMark",
  "EmphasisMark",
  "CodeMark",
  "LinkMark",
  "QuoteMark",
  "ListMark",
]);

const hiddenMark = Decoration.mark({ class: "cm-hidden-marker" });

/** StateEffect: toggle or set read mode. */
export const setReadMode = StateEffect.define<boolean>();

/** StateField: whether the editor is currently in read mode. */
export const readModeField = StateField.define<boolean>({
  create: () => true,
  update(value, tr) {
    for (const e of tr.effects) {
      if (e.is(setReadMode)) return e.value;
    }
    return value;
  },
});

/** Decorations: hide every MARKER_TYPES node unconditionally. */
function buildReadModeDecorations(view: EditorView): DecorationSet {
  const decorations: Range<Decoration>[] = [];
  syntaxTree(view.state).iterate({
    enter(node) {
      if (MARKER_TYPES.has(node.name)) {
        decorations.push(hiddenMark.range(node.from, node.to));
      }
    },
  });
  return Decoration.set(decorations, true);
}

const readModeDecorations = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = view.state.field(readModeField)
        ? buildReadModeDecorations(view)
        : Decoration.none;
    }
    update(update: ViewUpdate) {
      const inRead = update.state.field(readModeField);
      const wasRead = update.startState.field(readModeField);
      // Also rebuild on viewport scroll and background-parse progress: the syntax
      // tree is parsed incrementally for large docs, so markers in not-yet-parsed
      // or newly-scrolled regions would otherwise show through raw in read mode.
      const treeChanged = syntaxTree(update.startState) !== syntaxTree(update.state);
      if (
        inRead !== wasRead ||
        (inRead && (update.docChanged || update.viewportChanged || treeChanged))
      ) {
        this.decorations = inRead
          ? buildReadModeDecorations(update.view)
          : Decoration.none;
      }
    }
  },
  { decorations: (v) => v.decorations }
);

/** Visual polish for read mode: no caret, tighter line gaps, link cursor on clickable targets. */
const readModeTheme = EditorView.theme({
  "&.cm-read-mode .cm-cursor, &.cm-read-mode .cm-cursorLayer": {
    display: "none !important",
  },
  "&.cm-read-mode .cm-content": {
    caretColor: "transparent",
    cursor: "text",
  },
  "&.cm-read-mode .cm-activeLine": {
    backgroundColor: "transparent",
  },
  "&.cm-read-mode .cm-activeLineGutter": {
    backgroundColor: "transparent",
  },
  ".cm-mode-transition .cm-content": {
    transition: "opacity 180ms ease",
  },
});

/**
 * ViewPlugin that toggles a CSS class on the editor root based on mode,
 * and handles clicks in read mode to transition to author at the click pos.
 */
const readModeClassAndClick = ViewPlugin.fromClass(
  class {
    constructor(view: EditorView) {
      this.sync(view);
    }
    update(update: ViewUpdate) {
      if (
        update.state.field(readModeField) !==
        update.startState.field(readModeField)
      ) {
        this.sync(update.view);
      }
    }
    sync(view: EditorView) {
      const inRead = view.state.field(readModeField);
      view.dom.classList.toggle("cm-read-mode", inRead);
      view.contentDOM.setAttribute("contenteditable", inRead ? "false" : "true");
    }
  }
);

/** DOM click handler: in read mode, enter author mode with cursor at click. */
const readModeClickHandler = EditorView.domEventHandlers({
  mousedown(event, view) {
    if (!view.state.field(readModeField)) return false;
    const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
    enterAuthorMode(view, pos ?? undefined);
    return false; // allow default selection handling to continue
  },
});

/** Keymap-compatible command to toggle modes. */
export function toggleMode(view: EditorView): boolean {
  const inRead = view.state.field(readModeField);
  if (inRead) {
    enterAuthorMode(view);
  } else {
    enterReadMode(view);
  }
  return true;
}

export function enterReadMode(view: EditorView): void {
  view.dispatch({ effects: setReadMode.of(true) });
}

export function enterAuthorMode(view: EditorView, pos?: number): void {
  const reducedMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)"
  ).matches;
  const selection =
    pos !== undefined ? { anchor: pos, head: pos } : undefined;
  if (reducedMotion) {
    view.dispatch({ effects: setReadMode.of(false), selection });
    view.focus();
    return;
  }
  view.dom.classList.add("cm-mode-transition");
  view.contentDOM.style.opacity = "0.4";
  requestAnimationFrame(() => {
    view.dispatch({ effects: setReadMode.of(false), selection });
    view.contentDOM.style.opacity = "";
    view.focus();
    setTimeout(() => view.dom.classList.remove("cm-mode-transition"), 200);
  });
}

export function isReadMode(view: EditorView): boolean {
  return view.state.field(readModeField);
}

/**
 * Annotation marking a transaction as a programmatic content load (file open,
 * Format Document) so the read-mode edit guard lets it through.
 */
export const programmaticEdit = Annotation.define<boolean>();

/**
 * Read mode must be genuinely read-only. `contenteditable=false` only blocks
 * native DOM input — keymap commands (Cmd+B/I, deleteLine, Enter list
 * continuation) call `view.dispatch` programmatically and would still mutate the
 * document with no visible caret. This filter drops any doc-changing transaction
 * while in read mode unless it is an explicit programmatic load.
 */
const readModeEditGuard = EditorState.transactionFilter.of((tr) => {
  if (
    tr.docChanged &&
    tr.startState.field(readModeField) &&
    !tr.annotation(programmaticEdit)
  ) {
    return [];
  }
  return tr;
});

/** Full read-mode extension bundle — adds state, decorations, class sync, click handler. */
export function readMode(): Extension {
  return [
    readModeField,
    readModeEditGuard,
    readModeDecorations,
    readModeTheme,
    readModeClassAndClick,
    readModeClickHandler,
  ];
}

/**
 * Compartment for mode-specific extensions that need to switch dynamically
 * (e.g., the EditorState.readOnly facet cannot be parameterized per field).
 * Currently unused — the class-toggle + contenteditable approach is enough —
 * but exported so the compartment pattern is available for future growth.
 */
export const modeCompartment = new Compartment();
