export interface DocumentStats {
  words: number;
  chars: number;
  readingTime: number;
}

export function countWords(text: string): DocumentStats {
  // Count Unicode code points, not UTF-16 units, so emoji / astral chars (and
  // ZWJ sequences' components) aren't double-counted as 2.
  const chars = [...text].length;

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

  // Count words. CJK scripts (Chinese, Japanese kana) don't separate words with
  // spaces, so a whitespace split alone would count a whole sentence as one word.
  // Count each CJK ideograph/kana as a word (the Word/Pages convention), and
  // whitespace-split the remaining (Latin-style) text.
  // Ranges: CJK Unified Ideographs incl. Ext A (U+3400–U+9FFF), Compatibility
  // Ideographs (U+F900–U+FAFF), Hiragana + Katakana (U+3040–U+30FF).
  const cjk = /[㐀-鿿豈-﫿぀-ヿ]/g;
  const cjkWords = (stripped.match(cjk) || []).length;
  const latinWords = stripped
    .replace(cjk, " ")
    .split(/\s+/)
    .filter((t) => t.length > 0).length;
  const words = cjkWords + latinWords;

  // Reading time: words / 200, rounded, minimum 1 min
  const readingTime = words === 0 ? 0 : Math.max(1, Math.round(words / 200));

  return { words, chars, readingTime };
}
