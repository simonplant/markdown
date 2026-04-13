export interface DocumentStats {
  words: number;
  chars: number;
  readingTime: number;
}

export function countWords(text: string): DocumentStats {
  const chars = text.length;

  // Strip fenced code block contents (``` or ~~~ blocks)
  let stripped = text.replace(/^(`{3,}|~{3,}).*\n[\s\S]*?^\1\s*$/gm, "");

  // Strip inline code
  stripped = stripped.replace(/`[^`\n]+`/g, "");

  // Strip ATX heading markers
  stripped = stripped.replace(/^#{1,6}\s+/gm, "");

  // Strip link/image syntax: ![alt](url) and [text](url)
  stripped = stripped.replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1");

  // Strip reference links: [text][ref] and [ref]
  stripped = stripped.replace(/\[([^\]]*)\]\[[^\]]*\]/g, "$1");

  // Strip emphasis markers (bold/italic)
  stripped = stripped.replace(/(\*{1,3}|_{1,3})/g, "");

  // Strip strikethrough
  stripped = stripped.replace(/~~(.*?)~~/g, "$1");

  // Strip horizontal rules
  stripped = stripped.replace(/^[-*_]{3,}\s*$/gm, "");

  // Strip blockquote markers
  stripped = stripped.replace(/^>\s?/gm, "");

  // Strip list markers (unordered and ordered)
  stripped = stripped.replace(/^[\s]*[-*+]\s+/gm, "");
  stripped = stripped.replace(/^[\s]*\d+\.\s+/gm, "");

  // Split on whitespace and count non-empty tokens
  const words = stripped.split(/\s+/).filter((t) => t.length > 0).length;

  // Reading time: words / 200, rounded, minimum 1 min
  const readingTime = words === 0 ? 0 : Math.max(1, Math.round(words / 200));

  return { words, chars, readingTime };
}
