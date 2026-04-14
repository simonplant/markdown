/**
 * The Render — Markdown's signature interaction (DP-9).
 *
 * When the user toggles between source and rich view (Cmd+Shift+R),
 * markdown syntax characters don't just swap visibility — they
 * *transform*. Raw characters animate into their rendered form:
 * # markers shrink, ** markers dissolve, list markers morph.
 *
 * Implementation: The Render toggles the WYSIWYM decorations between
 * "always visible" (source mode) and "proximity-based hiding" (rich mode).
 * The transition is handled by CSS: the .cm-hidden-marker class gains
 * a transition on opacity, and a body class toggles the mode.
 *
 * Reduced Motion: when prefers-reduced-motion is active, the toggle
 * is instant (no animation) — an accessibility requirement from DP-10.
 *
 * Target: ~400ms spring-like transition. CSS approximation using
 * cubic-bezier for a slight overshoot.
 */

import { EditorView } from "@codemirror/view";
import type { Extension } from "@codemirror/state";
import type { Command } from "@codemirror/view";

let isSourceMode = false;

/**
 * Toggle between source mode (all markers visible) and rich mode
 * (WYSIWYM hides non-proximate markers with animation).
 */
export const toggleRender: Command = (view: EditorView) => {
  isSourceMode = !isSourceMode;
  const el = view.dom.closest(".cm-editor") || view.dom;

  if (isSourceMode) {
    el.classList.add("cm-source-mode");
    el.classList.remove("cm-rich-mode");
  } else {
    el.classList.remove("cm-source-mode");
    el.classList.add("cm-rich-mode");
  }

  // Force decoration rebuild by triggering a selection change
  view.dispatch({ selection: view.state.selection });
  return true;
};

/**
 * Returns whether we're currently in source mode.
 */
export function getIsSourceMode(): boolean {
  return isSourceMode;
}

/**
 * The Render CSS theme extension.
 *
 * In rich mode (default): markers transition opacity over 400ms with a
 * spring-like easing. In source mode: markers are forced visible.
 *
 * The transition fires both ways:
 * - Source → Rich: markers that should hide animate to opacity 0
 * - Rich → Source: hidden markers animate back to opacity 1
 */
const renderTheme = EditorView.baseTheme({
  // Rich mode (default) — WYSIWYM markers animate
  "&.cm-rich-mode .cm-hidden-marker, & .cm-hidden-marker": {
    transition: "opacity 400ms cubic-bezier(0.34, 1.56, 0.64, 1)",
    opacity: "0",
  },

  // Source mode — all markers visible, animated transition back
  "&.cm-source-mode .cm-hidden-marker": {
    transition: "opacity 400ms cubic-bezier(0.34, 1.56, 0.64, 1)",
    opacity: "1 !important",
  },

  // Reduced motion — instant toggle, no animation
  "@media (prefers-reduced-motion: reduce)": {
    "& .cm-hidden-marker": {
      transition: "none !important",
    },
  },
});

/**
 * The Render extension bundle.
 * Wire into the editor extensions and bind Cmd+Shift+R to toggleRender.
 */
export function theRender(): Extension {
  return [renderTheme];
}
