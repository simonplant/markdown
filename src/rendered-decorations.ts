/**
 * Rendered markdown decorations for CodeMirror 6.
 *
 * Adds block-level styling and widget decorations so markdown content
 * looks rendered rather than raw source. Cursor proximity reveals the
 * underlying syntax for editing — same pattern as wysiwym.ts.
 *
 * Constructs handled:
 * - Blockquotes: left border + tinted background
 * - Code blocks: monospace font + background
 * - Horizontal rules: styled <hr> widget
 * - Task checkboxes: <input type="checkbox"> widget
 * - Images: rendered <img> widget below the syntax
 */

import {
  ViewPlugin,
  Decoration,
  EditorView,
  WidgetType,
  type DecorationSet,
  type ViewUpdate,
} from "@codemirror/view";
import { syntaxTree } from "@codemirror/language";
import type { Extension, Range } from "@codemirror/state";
import { getIsSourceMode } from "./the-render";
import { Compartment } from "@codemirror/state";

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class HorizontalRuleWidget extends WidgetType {
  toDOM() {
    const hr = document.createElement("hr");
    hr.className = "cm-rendered-hr";
    return hr;
  }

  eq() {
    return true;
  }
}

class CheckboxWidget extends WidgetType {
  constructor(private checked: boolean) {
    super();
  }

  toDOM() {
    const cb = document.createElement("input");
    cb.type = "checkbox";
    cb.className = "cm-rendered-checkbox";
    cb.checked = this.checked;
    cb.disabled = true;
    return cb;
  }

  eq(other: CheckboxWidget) {
    return this.checked === other.checked;
  }
}

class ImageWidget extends WidgetType {
  constructor(
    private src: string,
    private alt: string,
  ) {
    super();
  }

  toDOM() {
    const wrapper = document.createElement("div");
    wrapper.className = "cm-rendered-image";
    const img = document.createElement("img");
    img.alt = this.alt;

    // Only allow relative paths and https URLs
    if (
      this.src.startsWith("https://") ||
      (!this.src.includes("://") && !this.src.startsWith("javascript"))
    ) {
      img.src = this.src;
    }

    img.onerror = () => {
      wrapper.classList.add("cm-rendered-image-error");
      img.style.display = "none";
      const fallback = document.createElement("span");
      fallback.className = "cm-rendered-image-fallback";
      fallback.textContent = `[image: ${this.alt || this.src}]`;
      wrapper.appendChild(fallback);
    };

    wrapper.appendChild(img);
    return wrapper;
  }

  eq(other: ImageWidget) {
    return this.src === other.src && this.alt === other.alt;
  }
}

// ---------------------------------------------------------------------------
// Decoration builder
// ---------------------------------------------------------------------------

function buildDecorations(view: EditorView): DecorationSet {
  if (getIsSourceMode()) {
    return Decoration.none;
  }

  const head = view.state.selection.main.head;
  const lineDecos: Range<Decoration>[] = [];
  const inlineDecos: Range<Decoration>[] = [];

  syntaxTree(view.state).iterate({
    enter(node) {
      const cursorInside = head >= node.from && head <= node.to;

      switch (node.name) {
        // --- Blockquotes: line decoration on each line ---
        case "Blockquote": {
          if (cursorInside) return;
          const from = node.from;
          const to = node.to;
          for (let pos = from; pos < to; ) {
            const line = view.state.doc.lineAt(pos);
            lineDecos.push(
              Decoration.line({ class: "cm-blockquote-line" }).range(
                line.from,
              ),
            );
            pos = line.to + 1;
          }
          return;
        }

        // --- Fenced code blocks: line decoration on each line ---
        case "FencedCode": {
          if (cursorInside) return;
          const from = node.from;
          const to = node.to;
          for (let pos = from; pos < to; ) {
            const line = view.state.doc.lineAt(pos);
            lineDecos.push(
              Decoration.line({ class: "cm-codeblock-line" }).range(
                line.from,
              ),
            );
            pos = line.to + 1;
          }
          return;
        }

        // --- Horizontal rules: replace with styled <hr> ---
        case "HorizontalRule": {
          if (cursorInside) return;
          inlineDecos.push(
            Decoration.replace({
              widget: new HorizontalRuleWidget(),
            }).range(node.from, node.to),
          );
          return;
        }

        // --- Task markers: replace [ ] or [x] with checkbox ---
        case "TaskMarker": {
          if (cursorInside) return;
          const text = view.state.doc.sliceString(node.from, node.to);
          const checked = text.includes("x") || text.includes("X");
          inlineDecos.push(
            Decoration.replace({
              widget: new CheckboxWidget(checked),
            }).range(node.from, node.to),
          );
          return;
        }

        // --- Images: render <img> widget after the syntax ---
        case "Image": {
          if (cursorInside) return;

          // Extract alt text and URL from child nodes
          let alt = "";
          let src = "";
          const imgNode = node.node;
          const cursor = imgNode.cursor();
          if (cursor.firstChild()) {
            do {
              if (cursor.name === "URL") {
                src = view.state.doc.sliceString(cursor.from, cursor.to);
              } else if (
                cursor.name !== "LinkMark" &&
                cursor.name !== "Image"
              ) {
                alt += view.state.doc.sliceString(cursor.from, cursor.to);
              }
            } while (cursor.nextSibling());
          }

          if (!alt && !src) {
            // Fallback: parse from text
            const fullText = view.state.doc.sliceString(node.from, node.to);
            const match = fullText.match(/!\[([^\]]*)\]\(([^)]*)\)/);
            if (match) {
              alt = match[1];
              src = match[2];
            }
          }

          if (src) {
            // Hide the syntax text
            inlineDecos.push(
              Decoration.replace({}).range(node.from, node.to),
            );
            // Add the image widget after
            inlineDecos.push(
              Decoration.widget({
                widget: new ImageWidget(src, alt),
                side: 1,
              }).range(node.to),
            );
          }
          return;
        }
      }
    },
  });

  // Line decorations must be sorted and unique by line start
  const seenLines = new Set<number>();
  const uniqueLineDecos = lineDecos.filter((d) => {
    const from = d.from;
    if (seenLines.has(from)) return false;
    seenLines.add(from);
    return true;
  });

  // Merge line and inline decorations, sorted by position
  const all = [...uniqueLineDecos, ...inlineDecos];
  all.sort((a, b) => a.from - b.from || a.value.startSide - b.value.startSide);

  return Decoration.set(all);
}

// ---------------------------------------------------------------------------
// ViewPlugin
// ---------------------------------------------------------------------------

const renderedPlugin = ViewPlugin.fromClass(
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
  },
);

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

// Light mode theme
const renderedLightTheme = EditorView.theme(
  {
    ".cm-blockquote-line": {
      borderLeft: "3px solid #0969DA",
      paddingLeft: "12px",
      background: "rgba(9, 105, 218, 0.06)",
    },
    ".cm-codeblock-line": {
      background: "#F0F0F0",
      fontFamily:
        "'SF Mono', SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace",
      fontSize: "0.9em",
    },
    ".cm-rendered-hr": {
      border: "none",
      borderTop: "2px solid #D0D7DE",
      margin: "0.8em 0",
    },
    ".cm-rendered-checkbox": {
      marginRight: "4px",
      verticalAlign: "middle",
      cursor: "default",
    },
    ".cm-rendered-image": {
      padding: "4px 0",
    },
    ".cm-rendered-image img": {
      maxWidth: "100%",
      borderRadius: "4px",
      display: "block",
    },
    ".cm-rendered-image-fallback": {
      color: "#8B949E",
      fontStyle: "italic",
      fontSize: "0.9em",
    },
  },
  { dark: false },
);

// Dark mode theme — colors chosen for contrast on #1E1E1E
const renderedDarkTheme = EditorView.theme(
  {
    ".cm-blockquote-line": {
      borderLeft: "3px solid #4FC1FF",
      paddingLeft: "12px",
      background: "rgba(79, 193, 255, 0.08)",
    },
    ".cm-codeblock-line": {
      background: "#2D2D2D",
      fontFamily:
        "'SF Mono', SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace",
      fontSize: "0.9em",
    },
    ".cm-rendered-hr": {
      border: "none",
      borderTop: "2px solid #555D66",
      margin: "0.8em 0",
    },
    ".cm-rendered-checkbox": {
      marginRight: "4px",
      verticalAlign: "middle",
      cursor: "default",
    },
    ".cm-rendered-image": {
      padding: "4px 0",
    },
    ".cm-rendered-image img": {
      maxWidth: "100%",
      borderRadius: "4px",
      display: "block",
    },
    ".cm-rendered-image-fallback": {
      color: "#9DA5B4",
      fontStyle: "italic",
      fontSize: "0.9em",
    },
  },
  { dark: true },
);

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

const renderedThemeCompartment = new Compartment();

/** Rendered markdown decorations extension. */
export function renderedDecorations(isDark: boolean): Extension {
  return [
    renderedPlugin,
    renderedThemeCompartment.of(isDark ? renderedDarkTheme : renderedLightTheme),
  ];
}

/** Reconfigure the rendered decorations theme for light/dark. */
export function setRenderedTheme(view: EditorView, isDark: boolean): void {
  view.dispatch({
    effects: renderedThemeCompartment.reconfigure(
      isDark ? renderedDarkTheme : renderedLightTheme,
    ),
  });
}
