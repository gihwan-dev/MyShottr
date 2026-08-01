import type { EditorCommand, EditorDefaults, EditorDocument } from "./elements";
import { applyCommand } from "./reducer";
import { EditorDocumentSchema } from "./schema";

export type HistoryAvailability = {
  canUndo: boolean;
  canRedo: boolean;
};

export type HistoryStore = {
  readonly document: EditorDocument;
  readonly canUndo: boolean;
  readonly canRedo: boolean;
  readonly isTransactionActive: boolean;
  getSnapshot(): EditorDocument;
  subscribe(listener: () => void): () => void;
  setDefaults(defaults: EditorDefaults): void;
  beginTransaction(label: string): void;
  dispatch(command: EditorCommand): void;
  commitTransaction(): void;
  cancelTransaction(): boolean;
  undo(): boolean;
  redo(): boolean;
};

type SceneSnapshot = EditorDocument["elements"];

type Transaction = {
  label: string;
  startingScene: SceneSnapshot;
  hasSceneChanges: boolean;
};

export function createHistoryStore(initialDocument: EditorDocument): HistoryStore {
  let document = EditorDocumentSchema.parse(initialDocument) as EditorDocument;
  const past: SceneSnapshot[] = [];
  const future: SceneSnapshot[] = [];
  const listeners = new Set<() => void>();
  let transaction: Transaction | undefined;
  const emit = () => listeners.forEach((listener) => listener());

  return {
    get document() {
      return document;
    },
    get canUndo() {
      return transaction === undefined && past.length > 0;
    },
    get canRedo() {
      return transaction === undefined && future.length > 0;
    },
    get isTransactionActive() {
      return transaction !== undefined;
    },
    getSnapshot() {
      return document;
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    setDefaults(defaults) {
      document = EditorDocumentSchema.parse({ ...document, defaults }) as EditorDocument;
      emit();
    },
    beginTransaction(label) {
      if (transaction) {
        throw new Error(`Cannot begin transaction while ${transaction.label} is active`);
      }
      if (label.length === 0) {
        throw new Error("Transaction label is required");
      }
      transaction = {
        label,
        startingScene: snapshotScene(document),
        hasSceneChanges: false,
      };
    },
    dispatch(command) {
      const next = applyCommand(document, command);
      if (next === document) {
        return;
      }
      if (!transaction) {
        past.push(snapshotScene(document));
        future.length = 0;
      } else {
        transaction.hasSceneChanges = true;
      }
      document = next;
      emit();
    },
    commitTransaction() {
      if (!transaction) {
        throw new Error("Cannot commit without an active transaction");
      }
      if (transaction.hasSceneChanges) {
        past.push(transaction.startingScene);
        future.length = 0;
      }
      transaction = undefined;
    },
    cancelTransaction() {
      if (!transaction) {
        throw new Error("Cannot cancel without an active transaction");
      }
      const changed = transaction.hasSceneChanges;
      if (changed) {
        document = installScene(document, transaction.startingScene);
      }
      transaction = undefined;
      if (changed) emit();
      return changed;
    },
    undo() {
      assertNoActiveTransaction(transaction, "undo");
      const previous = past.pop();
      if (!previous) return false;
      future.push(snapshotScene(document));
      document = installScene(document, previous);
      emit();
      return true;
    },
    redo() {
      assertNoActiveTransaction(transaction, "redo");
      const next = future.pop();
      if (!next) return false;
      past.push(snapshotScene(document));
      document = installScene(document, next);
      emit();
      return true;
    },
  };
}

const snapshotScene = (document: EditorDocument): SceneSnapshot =>
  document.elements;

const installScene = (
  document: EditorDocument,
  elements: SceneSnapshot,
): EditorDocument =>
  EditorDocumentSchema.parse({ ...document, elements }) as EditorDocument;

function assertNoActiveTransaction(transaction: Transaction | undefined, operation: string): void {
  if (transaction) {
    throw new Error(`Cannot ${operation} while ${transaction.label} is active`);
  }
}
