/**
 * Document doctor integration (FEAT-050).
 *
 * Debounces edits (500 ms), calls the Rust `document_diagnose` command, and
 * renders results as:
 *   - A gutter marker on the line containing each diagnostic.
 *   - An underline decoration on the offending byte range.
 *   - A hover tooltip with the diagnostic message.
 *
 * Only active in author mode. Read mode suppresses the visual layer.
 */

import { invoke } from "@tauri-apps/api/core";
import {
  Decoration,
  EditorView,
  ViewPlugin,
  gutter,
  GutterMarker,
  hoverTooltip,
  type DecorationSet,
  type ViewUpdate,
} from "@codemirror/view";
import {
  RangeSetBuilder,
  StateEffect,
  StateField,
  type Extension,
} from "@codemirror/state";
import { readModeField } from "./read-mode";

export interface Diagnostic {
  rule: string;
  severity: "error" | "warning" | "hint";
  start: number;
  end: number;
  message: string;
}

const setDiagnostics = StateEffect.define<Diagnostic[]>();

const diagnosticsField = StateField.define<Diagnostic[]>({
  create: () => [],
  update(value, tr) {
    for (const e of tr.effects) {
      if (e.is(setDiagnostics)) return e.value;
    }
    return value;
  },
});

class DoctorGutterMarker extends GutterMarker {
  constructor(private severity: Diagnostic["severity"]) {
    super();
  }
  toDOM(): Node {
    const el = document.createElement("span");
    el.className = `cm-doctor-gutter cm-doctor-${this.severity}`;
    el.textContent =
      this.severity === "error" ? "✖" : this.severity === "warning" ? "!" : "·";
    return el;
  }
}

const doctorGutter = gutter({
  class: "cm-doctor-gutter-track",
  lineMarker(view, line) {
    if (view.state.field(readModeField)) return null;
    const diags = view.state.field(diagnosticsField);
    for (const d of diags) {
      // Convert byte offsets to line. CodeMirror's Text is char-indexed; for
      // ASCII-heavy prose this matches bytes. Non-ASCII content produces
      // off-by-a-few markers, acceptable for v1.
      const lineAt = view.state.doc.lineAt(Math.min(d.start, view.state.doc.length));
      if (lineAt.from === line.from) {
        return new DoctorGutterMarker(d.severity);
      }
    }
    return null;
  },
  initialSpacer: () => new DoctorGutterMarker("hint"),
});

function buildUnderlineDecorations(
  view: EditorView,
  diags: Diagnostic[]
): DecorationSet {
  if (view.state.field(readModeField)) return Decoration.none;
  const builder = new RangeSetBuilder<Decoration>();
  const docLen = view.state.doc.length;
  const sorted = [...diags].sort((a, b) => a.start - b.start || a.end - b.end);
  for (const d of sorted) {
    const start = Math.min(Math.max(0, d.start), docLen);
    const end = Math.min(Math.max(start, d.end), docLen);
    if (end <= start) continue;
    builder.add(
      start,
      end,
      Decoration.mark({ class: `cm-doctor-underline cm-doctor-${d.severity}` })
    );
  }
  return builder.finish();
}

const underlinePlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = buildUnderlineDecorations(
        view,
        view.state.field(diagnosticsField)
      );
    }
    update(update: ViewUpdate) {
      const diagsChanged = update.transactions.some((tr) =>
        tr.effects.some((e) => e.is(setDiagnostics))
      );
      const modeChanged =
        update.state.field(readModeField) !==
        update.startState.field(readModeField);
      if (diagsChanged || modeChanged) {
        this.decorations = buildUnderlineDecorations(
          update.view,
          update.state.field(diagnosticsField)
        );
      }
    }
  },
  { decorations: (v) => v.decorations }
);

const doctorTooltip = hoverTooltip((view, pos) => {
  const diags = view.state.field(diagnosticsField);
  const hit = diags.find((d) => pos >= d.start && pos <= d.end);
  if (!hit) return null;
  return {
    pos: hit.start,
    end: hit.end,
    above: true,
    create() {
      const dom = document.createElement("div");
      dom.className = `cm-doctor-tooltip cm-doctor-${hit.severity}`;
      dom.textContent = `${hit.message} (${hit.rule})`;
      return { dom };
    },
  };
});

const doctorTheme = EditorView.baseTheme({
  ".cm-doctor-gutter-track": {
    width: "14px",
  },
  ".cm-doctor-gutter": {
    display: "inline-block",
    width: "12px",
    textAlign: "center",
    fontWeight: "bold",
    cursor: "help",
  },
  ".cm-doctor-gutter.cm-doctor-error": { color: "#d73a49" },
  ".cm-doctor-gutter.cm-doctor-warning": { color: "#b08800" },
  ".cm-doctor-gutter.cm-doctor-hint": { color: "#6a737d" },
  ".cm-doctor-underline": {
    textDecoration: "underline wavy",
    textDecorationSkipInk: "none",
  },
  ".cm-doctor-underline.cm-doctor-error": { textDecorationColor: "#d73a49" },
  ".cm-doctor-underline.cm-doctor-warning": { textDecorationColor: "#b08800" },
  ".cm-doctor-underline.cm-doctor-hint": { textDecorationColor: "#6a737d" },
  ".cm-doctor-tooltip": {
    padding: "6px 10px",
    backgroundColor: "var(--cm-tooltip-bg, #24292f)",
    color: "var(--cm-tooltip-fg, #ffffff)",
    borderRadius: "4px",
    fontSize: "12px",
    maxWidth: "320px",
  },
});

/** Debounced runner that calls the Tauri command and dispatches diagnostics. */
function makeRunner(view: EditorView): () => void {
  let timer: ReturnType<typeof setTimeout> | null = null;
  let inflight = 0;
  return () => {
    if (timer !== null) clearTimeout(timer);
    timer = setTimeout(async () => {
      timer = null;
      const myToken = ++inflight;
      try {
        const diags = await invoke<Diagnostic[]>("document_diagnose");
        if (myToken !== inflight) return; // superseded by a newer request
        view.dispatch({ effects: setDiagnostics.of(diags) });
      } catch {
        // Doctor failed — clear diagnostics rather than leaving stale markers.
        if (myToken === inflight) {
          view.dispatch({ effects: setDiagnostics.of([]) });
        }
      }
    }, 500);
  };
}

const debounceDriver = ViewPlugin.fromClass(
  class {
    run: () => void;
    constructor(view: EditorView) {
      this.run = makeRunner(view);
      // Kick an initial run once the view is mounted.
      queueMicrotask(() => this.run());
    }
    update(update: ViewUpdate) {
      if (update.docChanged) this.run();
    }
  }
);

/** Document doctor extension — on by default in author mode. */
export function doctorDiagnostics(): Extension {
  return [
    diagnosticsField,
    doctorGutter,
    underlinePlugin,
    doctorTooltip,
    doctorTheme,
    debounceDriver,
  ];
}
