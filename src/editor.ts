import { EditorView, keymap, lineNumbers, drawSelection, highlightActiveLine } from "@codemirror/view";
import { EditorState, type Extension } from "@codemirror/state";
import { defaultKeymap, history, historyKeymap, deleteLine } from "@codemirror/commands";
import { searchKeymap, highlightSelectionMatches } from "@codemirror/search";
import { themeExtension, setTheme, getSystemIsDark } from "./themes";
import { toggleBold, toggleItalic } from "./markdown-commands";
import { countWords } from "./wordcount";
import { markdownExtension } from "./markdown-highlight";
import { wysiwym } from "./wysiwym";
import { theRender, toggleRender } from "./the-render";

let view: EditorView;

function updateStatusBar(text: string): void {
  const stats = countWords(text);
  const wordsEl = document.getElementById("stat-words");
  const charsEl = document.getElementById("stat-chars");
  const readingEl = document.getElementById("stat-reading");
  if (wordsEl) wordsEl.textContent = `${stats.words} words`;
  if (charsEl) charsEl.textContent = `${stats.chars} characters`;
  if (readingEl) readingEl.textContent = `${stats.readingTime} min read`;
}

export function initEditor(parent: HTMLElement, extraExtensions: Extension[] = []): EditorView {
  const isDark = getSystemIsDark();

  const state = EditorState.create({
    doc: "",
    extensions: [
      lineNumbers(),
      drawSelection(),
      highlightActiveLine(),
      history(),
      highlightSelectionMatches(),
      keymap.of([
        { key: "Mod-b", run: toggleBold },
        { key: "Mod-i", run: toggleItalic },
        { key: "Mod-Shift-r", run: toggleRender },
        { key: "Mod-Shift-k", run: deleteLine },
        ...searchKeymap,
        ...defaultKeymap,
        ...historyKeymap,
      ]),
      markdownExtension(),
      wysiwym(),
      theRender(),
      EditorView.lineWrapping,
      themeExtension(isDark),
      EditorView.updateListener.of((update) => {
        if (update.docChanged) {
          updateStatusBar(update.state.doc.toString());
        }
      }),
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
