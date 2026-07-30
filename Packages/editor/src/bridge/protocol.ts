import { z } from "zod";
import type { EditorDefaults, EditorDocument, EditorTool } from "../model/elements";
import { EditorDefaultsSchema, EditorDocumentSchema } from "../model/schema";

export const PROTOCOL_VERSION = 1 as const;
export const MAX_PAYLOAD_BYTES = 8 * 1024 * 1024;

const RequestIDSchema = z.string().regex(
  /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i,
  "requestId must be a UUID",
);

const payloadIsWithinLimit = (payload: unknown) =>
  new TextEncoder().encode(JSON.stringify(payload)).byteLength <= MAX_PAYLOAD_BYTES;

const EnvelopeBaseSchema = z.object({
  protocolVersion: z.literal(PROTOCOL_VERSION),
  requestId: RequestIDSchema,
  type: z.string(),
  payload: z.unknown(),
}).strict().superRefine((envelope, context) => {
  if (!payloadIsWithinLimit(envelope.payload)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["payload"],
      message: "Bridge payload exceeds 8 MiB",
    });
  }
});

const EditorReadyPayloadSchema = z.object({}).strict();
const DocumentChangedPayloadSchema = z.object({}).strict();
const EditorPreferencesChangedPayloadSchema = z.object({
  tool: z.enum(["selection", "rectangle", "arrow", "text", "freehand", "highlighter", "redaction", "numberMarker"]),
  defaults: EditorDefaultsSchema,
}).strict();
const AnnotationSnapshotPayloadSchema = z.object({
  document: EditorDocumentSchema,
}).strict();
const CompositeChunkPayloadSchema = z.object({
  requestId: RequestIDSchema,
  index: z.number().int().nonnegative(),
  total: z.number().int().positive(),
  dataBase64: z.string(),
}).strict().superRefine((payload, context) => {
  if (payload.index >= payload.total) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ["index"], message: "index must be smaller than total" });
  }
});
const CompositeCompletedPayloadSchema = z.object({ requestId: RequestIDSchema }).strict();
const BridgeErrorPayloadSchema = z.object({
  code: z.enum(["INVALID_DOCUMENT", "INVALID_MESSAGE", "RENDER_FAILED"]),
  message: z.string().min(1),
}).strict();

const EditorToNativeMessageSchema = z.discriminatedUnion("type", [
  z.object({ protocolVersion: z.literal(PROTOCOL_VERSION), requestId: RequestIDSchema, type: z.literal("editorReady"), payload: EditorReadyPayloadSchema }).strict(),
  z.object({ protocolVersion: z.literal(PROTOCOL_VERSION), requestId: RequestIDSchema, type: z.literal("documentChanged"), payload: DocumentChangedPayloadSchema }).strict(),
  z.object({ protocolVersion: z.literal(PROTOCOL_VERSION), requestId: RequestIDSchema, type: z.literal("editorPreferencesChanged"), payload: EditorPreferencesChangedPayloadSchema }).strict(),
  z.object({ protocolVersion: z.literal(PROTOCOL_VERSION), requestId: RequestIDSchema, type: z.literal("annotationSnapshot"), payload: AnnotationSnapshotPayloadSchema }).strict(),
  z.object({ protocolVersion: z.literal(PROTOCOL_VERSION), requestId: RequestIDSchema, type: z.literal("compositeChunk"), payload: CompositeChunkPayloadSchema }).strict(),
  z.object({ protocolVersion: z.literal(PROTOCOL_VERSION), requestId: RequestIDSchema, type: z.literal("compositeCompleted"), payload: CompositeCompletedPayloadSchema }).strict(),
  z.object({ protocolVersion: z.literal(PROTOCOL_VERSION), requestId: RequestIDSchema, type: z.literal("bridgeError"), payload: BridgeErrorPayloadSchema }).strict(),
]);

const LoadDocumentPayloadSchema = z.object({
  documentId: RequestIDSchema,
  sourceImageURL: z.string(),
  annotationDocument: EditorDocumentSchema,
  initialTool: z.enum(["selection", "rectangle", "arrow", "text", "freehand", "highlighter", "redaction", "numberMarker"]),
}).strict().superRefine((payload, context) => {
  const expectedURL = `myshottr-editor://editor/document/${payload.documentId}/original.png`;
  if (payload.sourceImageURL !== expectedURL) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["sourceImageURL"],
      message: "sourceImageURL must address this document's original PNG",
    });
  }
});
const SaveCompletedPayloadSchema = z.object({ requestId: RequestIDSchema }).strict();
const SaveFailedPayloadSchema = z.object({ requestId: RequestIDSchema, message: z.string().min(1) }).strict();
const RequestCompositePayloadSchema = z.object({ requestId: RequestIDSchema }).strict();
const SetAppearancePayloadSchema = z.object({ colorScheme: z.enum(["light", "dark"]) }).strict();

const NativeToEditorMessageSchema = z.discriminatedUnion("type", [
  z.object({ protocolVersion: z.literal(PROTOCOL_VERSION), requestId: RequestIDSchema, type: z.literal("loadDocument"), payload: LoadDocumentPayloadSchema }).strict(),
  z.object({ protocolVersion: z.literal(PROTOCOL_VERSION), requestId: RequestIDSchema, type: z.literal("saveCompleted"), payload: SaveCompletedPayloadSchema }).strict(),
  z.object({ protocolVersion: z.literal(PROTOCOL_VERSION), requestId: RequestIDSchema, type: z.literal("saveFailed"), payload: SaveFailedPayloadSchema }).strict(),
  z.object({ protocolVersion: z.literal(PROTOCOL_VERSION), requestId: RequestIDSchema, type: z.literal("requestComposite"), payload: RequestCompositePayloadSchema }).strict(),
  z.object({ protocolVersion: z.literal(PROTOCOL_VERSION), requestId: RequestIDSchema, type: z.literal("setAppearance"), payload: SetAppearancePayloadSchema }).strict(),
]);

export const EditorToNativeEnvelopeSchema = EnvelopeBaseSchema.pipe(EditorToNativeMessageSchema);
export const NativeToEditorEnvelopeSchema = EnvelopeBaseSchema.pipe(NativeToEditorMessageSchema);

export type Envelope<T extends string, P> = {
  protocolVersion: 1;
  requestId: string;
  type: T;
  payload: P;
};

export type EditorToNativePayloads = {
  editorReady: {};
  documentChanged: {};
  editorPreferencesChanged: { tool: EditorTool; defaults: EditorDefaults };
  annotationSnapshot: { document: EditorDocument };
  compositeChunk: { requestId: string; index: number; total: number; dataBase64: string };
  compositeCompleted: { requestId: string };
  bridgeError: { code: "INVALID_DOCUMENT" | "INVALID_MESSAGE" | "RENDER_FAILED"; message: string };
};

export type NativeToEditorEnvelope =
  | Envelope<"loadDocument", { documentId: string; sourceImageURL: string; annotationDocument: EditorDocument; initialTool: EditorTool }>
  | Envelope<"saveCompleted", { requestId: string }>
  | Envelope<"saveFailed", { requestId: string; message: string }>
  | Envelope<"requestComposite", { requestId: string }>
  | Envelope<"setAppearance", { colorScheme: "light" | "dark" }>;

export type EditorToNativeType = keyof EditorToNativePayloads;
export type PayloadFor<T extends EditorToNativeType> = EditorToNativePayloads[T];
