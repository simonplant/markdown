import { EditorView, keymap, lineNumbers, drawSelection, highlightActiveLine } from "@codemirror/view";
import { EditorState, type Extension } from "@codemirror/state";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";

let view: EditorView;

export function initEditor(parent: HTMLElement, extraExtensions: Extension[] = []): EditorView {
  const state = EditorState.create({
    doc: "",
    extensions: [
      lineNumbers(),
      drawSelection(),
      highlightActiveLine(),
      history(),
      keymap.of([...defaultKeymap, ...historyKeymap]),
      EditorView.lineWrapping,
      ...extraExtensions,
    ],
  });

  view = new EditorView({ state, parent });
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
