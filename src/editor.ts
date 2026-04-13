import { EditorView, keymap, lineNumbers, drawSelection, highlightActiveLine } from "@codemirror/view";
import { EditorState, type Extension } from "@codemirror/state";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { themeExtension, setTheme, getSystemIsDark } from "./themes";

let view: EditorView;

export function initEditor(parent: HTMLElement, extraExtensions: Extension[] = []): EditorView {
  const isDark = getSystemIsDark();

  const state = EditorState.create({
    doc: "",
    extensions: [
      lineNumbers(),
      drawSelection(),
      highlightActiveLine(),
      history(),
      keymap.of([...defaultKeymap, ...historyKeymap]),
      EditorView.lineWrapping,
      themeExtension(isDark),
      ...extraExtensions,
    ],
  });

  view = new EditorView({ state, parent });

  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (e) => {
    setTheme(view, e.matches);
  });

  return view;
}

export function getContent(): string {
  return view.state.doc.toString();
}

export function setContent(text: string): void {
  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: text },
  });
}
