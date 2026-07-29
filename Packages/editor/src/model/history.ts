import type { EditorCommand, EditorDocument } from "./elements";
import { applyCommand } from "./reducer";
import { EditorDocumentSchema } from "./schema";

export type HistoryStore = {
  readonly document: EditorDocument;
  beginTransaction(label: string): void;
  dispatch(command: EditorCommand): void;
  commitTransaction(): void;
  cancelTransaction(): boolean;
  undo(): boolean;
  redo(): boolean;
};

type Transaction = {
  label: string;
  startingDocument: EditorDocument;
};

export function createHistoryStore(initialDocument: EditorDocument): HistoryStore {
  let document = EditorDocumentSchema.parse(initialDocument) as EditorDocument;
  const past: EditorDocument[] = [];
  const future: EditorDocument[] = [];
  let transaction: Transaction | undefined;

  return {
    get document() {
      return EditorDocumentSchema.parse(document) as EditorDocument;
    },
    beginTransaction(label) {
      if (transaction) {
        throw new Error(`Cannot begin transaction while ${transaction.label} is active`);
      }
      if (label.length === 0) {
        throw new Error("Transaction label is required");
      }
      transaction = { label, startingDocument: document };
    },
    dispatch(command) {
      const next = applyCommand(document, command);
      if (next === document) {
        return;
      }
      if (!transaction) {
        past.push(document);
        future.length = 0;
      }
      document = next;
    },
    commitTransaction() {
      if (!transaction) {
        throw new Error("Cannot commit without an active transaction");
      }
      if (document !== transaction.startingDocument) {
        past.push(transaction.startingDocument);
        future.length = 0;
      }
      transaction = undefined;
    },
    cancelTransaction() {
      if (!transaction) {
        throw new Error("Cannot cancel without an active transaction");
      }
      const changed = document !== transaction.startingDocument;
      document = transaction.startingDocument;
      transaction = undefined;
      return changed;
    },
    undo() {
      assertNoActiveTransaction(transaction, "undo");
      const previous = past.pop();
      if (!previous) return false;
      future.push(document);
      document = previous;
      return true;
    },
    redo() {
      assertNoActiveTransaction(transaction, "redo");
      const next = future.pop();
      if (!next) return false;
      past.push(document);
      document = next;
      return true;
    },
  };
}

function assertNoActiveTransaction(transaction: Transaction | undefined, operation: string): void {
  if (transaction) {
    throw new Error(`Cannot ${operation} while ${transaction.label} is active`);
  }
}
