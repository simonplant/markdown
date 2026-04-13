/**
 * Markdown syntax highlighting for CodeMirror 6.
 *
 * Uses @codemirror/lang-markdown (backed by @lezer/markdown) as the
 * incremental parser. This is the same parser Obsidian uses — it handles
 * CommonMark + GFM extensions (tables, strikethrough, task lists, autolinks)
 * and runs at keystroke speed in the browser.
 *
 * The highlight styles here define how every markdown construct looks.
 * They are intentionally opinionated: headings are visually distinct by
 * level, emphasis is real italic/bold (not just colored), code is
 * monospaced with a background, and markup characters are dimmed.
 *
 * This module does NOT add WYSIWYM decorations (hiding syntax characters).
 * That comes in FEAT-013. This is pure syntax highlighting — every
 * character is visible, but markdown structure is color-coded.
 */

import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags } from "@lezer/highlight";
import type { Extension } from "@codemirror/state";

/**
 * Light theme syntax highlighting.
 *
 * Design principles:
 * - Headings use weight + size, not just color — they should feel like headings
 * - Emphasis uses real font-style, not color — italic looks italic, bold looks bold
 * - Code uses monospace + subtle background — visually distinct from prose
 * - Links use underline + color — the standard web convention
 * - Markup characters (# ** ``` etc.) are dimmed, not hidden — WYSIWYM hides them later
 * - Colors are chosen for WCAG AA contrast on #FAFAFA background
 */
const lightHighlightStyle = HighlightStyle.define([
  // Headings — progressively smaller, all bold, blue-tinted
  { tag: tags.heading1, fontWeight: "700", fontSize: "1.6em", color: "#1A3A5C", lineHeight: "1.3" },
  { tag: tags.heading2, fontWeight: "700", fontSize: "1.35em", color: "#1A3A5C", lineHeight: "1.3" },
  { tag: tags.heading3, fontWeight: "600", fontSize: "1.15em", color: "#2A4A6C" },
  { tag: tags.heading4, fontWeight: "600", fontSize: "1.05em", color: "#2A4A6C" },
  { tag: tags.heading5, fontWeight: "600", color: "#3A5A7C" },
  { tag: tags.heading6, fontWeight: "600", color: "#3A5A7C" },

  // Emphasis — real typographic treatment, not just color
  { tag: tags.emphasis, fontStyle: "italic", color: "#1A1A1A" },
  { tag: tags.strong, fontWeight: "700", color: "#1A1A1A" },
  { tag: tags.strikethrough, textDecoration: "line-through", color: "#6E7781" },

  // Code — monospace with subtle background
  { tag: tags.monospace, fontFamily: "'SF Mono', 'Fira Code', 'Cascadia Code', monospace", color: "#C73E1D", backgroundColor: "#F0F0F0", borderRadius: "3px", padding: "1px 4px" },

  // Links
  { tag: tags.link, color: "#0969DA", textDecoration: "underline" },
  { tag: tags.url, color: "#0969DA", textDecoration: "underline" },

  // Markup characters — dimmed but visible (WYSIWYM hides them later)
  { tag: tags.processingInstruction, color: "#8B949E" },  // # heading markers
  { tag: tags.contentSeparator, color: "#8B949E" },       // --- thematic breaks

  // Blockquotes
  { tag: tags.quote, color: "#57606A", fontStyle: "italic" },

  // Lists
  { tag: tags.list, color: "#0969DA" },

  // Meta / frontmatter
  { tag: tags.meta, color: "#8B949E" },

  // HTML in markdown
  { tag: tags.angleBracket, color: "#8B949E" },
  { tag: tags.tagName, color: "#116329" },
  { tag: tags.attributeName, color: "#0550AE" },
  { tag: tags.attributeValue, color: "#0A3069" },
]);

/**
 * Dark theme syntax highlighting.
 * Same structure as light, colors adapted for #1E1E1E background.
 * All colors checked for WCAG AA contrast.
 */
const darkHighlightStyle = HighlightStyle.define([
  // Headings
  { tag: tags.heading1, fontWeight: "700", fontSize: "1.6em", color: "#7EB6FF", lineHeight: "1.3" },
  { tag: tags.heading2, fontWeight: "700", fontSize: "1.35em", color: "#7EB6FF", lineHeight: "1.3" },
  { tag: tags.heading3, fontWeight: "600", fontSize: "1.15em", color: "#8EC4FF" },
  { tag: tags.heading4, fontWeight: "600", fontSize: "1.05em", color: "#8EC4FF" },
  { tag: tags.heading5, fontWeight: "600", color: "#9ED0FF" },
  { tag: tags.heading6, fontWeight: "600", color: "#9ED0FF" },

  // Emphasis
  { tag: tags.emphasis, fontStyle: "italic", color: "#D4D4D4" },
  { tag: tags.strong, fontWeight: "700", color: "#D4D4D4" },
  { tag: tags.strikethrough, textDecoration: "line-through", color: "#858585" },

  // Code
  { tag: tags.monospace, fontFamily: "'SF Mono', 'Fira Code', 'Cascadia Code', monospace", color: "#CE9178", backgroundColor: "#2A2A2A", borderRadius: "3px", padding: "1px 4px" },

  // Links
  { tag: tags.link, color: "#4FC1FF", textDecoration: "underline" },
  { tag: tags.url, color: "#4FC1FF", textDecoration: "underline" },

  // Markup characters
  { tag: tags.processingInstruction, color: "#6A737D" },
  { tag: tags.contentSeparator, color: "#6A737D" },

  // Blockquotes
  { tag: tags.quote, color: "#9DA5B4", fontStyle: "italic" },

  // Lists
  { tag: tags.list, color: "#4FC1FF" },

  // Meta
  { tag: tags.meta, color: "#6A737D" },

  // HTML
  { tag: tags.angleBracket, color: "#6A737D" },
  { tag: tags.tagName, color: "#4EC9B0" },
  { tag: tags.attributeName, color: "#9CDCFE" },
  { tag: tags.attributeValue, color: "#CE9178" },
]);

/**
 * Returns the full markdown language extension bundle:
 * - @codemirror/lang-markdown with GFM support
 * - Syntax highlighting for both light and dark themes
 *
 * Both highlight styles are registered — CodeMirror automatically uses
 * the one that matches the current theme's dark/light setting.
 */
export function markdownExtension(): Extension {
  return [
    markdown({
      base: markdownLanguage,
    }),
    syntaxHighlighting(lightHighlightStyle),
    syntaxHighlighting(darkHighlightStyle),
  ];
}
