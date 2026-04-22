/**
 * Format Document (FEAT-052).
 *
 * Invokes the backend `document_format` command, which runs the five
 * markdown_core formatter rules, and applies the returned mutations to the
 * current editor view as a single transaction (so undo rewinds the whole
 * formatting pass).
 */

import { invoke } from "@tauri-apps/api/core";
import { EditorView } from "@codemirror/view";

interface Mutation {
  offset: number;
  delete: number;
  insert: string;
}

export async function formatDocument(view: EditorView): Promise<boolean> {
  try {
    const mutations = await invoke<Mutation[]>("document_format");
    if (mutations.length === 0) return true;
    // Backend returns mutations sorted offset-descending so we can apply
    // without recomputing offsets — but CodeMirror's TransactionSpec expects
    // ascending order for `changes`. Reverse before dispatching.
    const changes = [...mutations]
      .sort((a, b) => a.offset - b.offset)
      .map((m) => ({
        from: m.offset,
        to: m.offset + m.delete,
        insert: m.insert,
      }));
    view.dispatch({ changes });
    return true;
  } catch {
    return false;
  }
}

/** Keymap-compatible command wrapper. */
export function formatDocumentCommand(view: EditorView): boolean {
  void formatDocument(view);
  return true;
}
