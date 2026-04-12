import { EditorView, keymap, lineNumbers, drawSelection, highlightActiveLine } from "@codemirror/view";
import { EditorState } from "@codemirror/state";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";

let view: EditorView;

export function initEditor(parent: HTMLElement): EditorView {
  const state = EditorState.create({
    doc: "",
    extensions: [
      lineNumbers(),
      drawSelection(),
      highlightActiveLine(),
      history(),
      keymap.of([...defaultKeymap, ...historyKeymap]),
      EditorView.lineWrapping,
    ],
  });

  view = new EditorView({ state, parent });
  return view;
}

export function getContent(): string {
  return view.state.doc.toString();
}
