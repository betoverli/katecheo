import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";

export const Route = createFileRoute("/native-editor")({
  head: () => ({
    meta: [{ title: "Katecheo Editor Spike" }],
  }),
  component: NativeEditorSpike,
});

/** Accepts NoteDocumentV1 or legacy note shapes for the spike. */
type SpikeNote = {
  schemaVersion?: number;
  id: string;
  title: string;
  happenedAt: string;
  tags: string[];
  speakerId?: string | null;
  noteSpeakerId?: string | null;
  blocks?: Array<{ id: string; type: string; inlines?: Array<{ type: string; text?: string }> }>;
  body?: {
    blocks: Array<{
      id: string;
      type: string;
      spans?: Array<{ type: string; text?: string }>;
      blocks?: Array<{ id: string; type: string; spans?: Array<{ type: string; text?: string }> }>;
    }>;
  };
  visibility: string;
  updatedAt: string;
};

type BridgeInbound =
  | { type: "loadNote"; note: SpikeNote; speakers?: unknown[]; readOnly?: boolean }
  | { type: "setReadOnly"; readOnly: boolean }
  | { type: "focus" };

function postToNative(payload: Record<string, unknown>) {
  try {
    (
      window as Window & {
        webkit?: { messageHandlers?: { v2n?: { postMessage: (msg: unknown) => void } } };
      }
    ).webkit?.messageHandlers?.v2n?.postMessage(payload);
  } catch {
    /* browser preview */
  }
  console.log("[native-editor→native]", payload);
}

function textFromNote(note: SpikeNote): string {
  const lines: string[] = [];
  if (note.body?.blocks?.length) {
    for (const block of note.body.blocks) {
      if (block.type === "speakerSection") {
        for (const child of block.blocks ?? []) {
          lines.push((child.spans ?? []).map((s) => (s.type === "text" ? s.text ?? "" : "[ref]")).join(""));
        }
        continue;
      }
      lines.push((block.spans ?? []).map((s) => (s.type === "text" ? s.text ?? "" : "[ref]")).join(""));
    }
    return lines.join("\n");
  }
  for (const block of note.blocks ?? []) {
    if (block.type === "speaker") continue;
    const inline = (block.inlines ?? [])
      .map((part) => (part.type === "text" ? part.text ?? "" : `[ref]`))
      .join("");
    lines.push(inline);
  }
  return lines.join("\n");
}

function noteFromText(base: SpikeNote, text: string): SpikeNote {
  const lines = text.split("\n");
  const bodyBlocks = lines.map((line, index) => ({
    id: base.body?.blocks?.[index]?.id ?? `line-${index}-${Date.now().toString(36)}`,
    type: "paragraph" as const,
    spans: line ? [{ type: "text" as const, text: line }] : [],
  }));
  return {
    schemaVersion: 1,
    ...base,
    noteSpeakerId: base.noteSpeakerId ?? base.speakerId ?? null,
    body: { blocks: bodyBlocks.length ? bodyBlocks : [{ id: "line-0", type: "paragraph", spans: [] }] },
    updatedAt: new Date().toISOString(),
  };
}

/**
 * Phase 0 miolo spike: plain textarea + WK bridge.
 * Native loads this URL (or posts loadNote). Not the full notebook editor.
 */
function NativeEditorSpike() {
  const [note, setNote] = useState<SpikeNote | null>(null);
  const [text, setText] = useState("");
  const [readOnly, setReadOnly] = useState(false);
  const [status, setStatus] = useState("waiting for loadNote…");
  const debounce = useRef<number | null>(null);
  const search = typeof window !== "undefined" ? new URLSearchParams(window.location.search) : null;
  const noteId = search?.get("noteId") ?? "";
  const demo = search?.get("demo") === "1";

  useEffect(() => {
    document.documentElement.classList.add("native-editor-spike");
    const onMessage = (event: MessageEvent) => {
      const data = event.data as BridgeInbound | null;
      if (!data || typeof data !== "object" || !("type" in data)) return;
      if (data.type === "loadNote") {
        setNote(data.note);
        setText(textFromNote(data.note));
        setReadOnly(Boolean(data.readOnly));
        setStatus(`loaded ${data.note.id}`);
        postToNative({ type: "ready", noteId: data.note.id });
      } else if (data.type === "setReadOnly") {
        setReadOnly(Boolean(data.readOnly));
      } else if (data.type === "focus") {
        document.getElementById("miolo")?.focus();
      }
    };
    window.addEventListener("message", onMessage);
    (window as Window & { __V2N_EDITOR_LOAD__?: (msg: BridgeInbound) => void }).__V2N_EDITOR_LOAD__ = (
      msg,
    ) => onMessage({ data: msg } as MessageEvent);

    postToNative({ type: "ready", noteId: noteId || null });

    if (demo && !noteId) {
      const sample: SpikeNote = {
        schemaVersion: 1,
        id: "demo-note",
        title: "Demo",
        happenedAt: new Date().toISOString().slice(0, 10),
        tags: [],
        noteSpeakerId: null,
        body: {
          blocks: [
            { id: "1", type: "paragraph", spans: [{ type: "text", text: "Editor spike — type here." }] },
          ],
        },
        visibility: "private",
        updatedAt: new Date().toISOString(),
      };
      setNote(sample);
      setText(textFromNote(sample));
      setStatus("demo note");
    }

    if (noteId) {
      void (async () => {
        try {
          const headers: HeadersInit = {};
          const bearer =
            window.localStorage.getItem("grok-auth.bearer-token") ||
            window.sessionStorage.getItem("grok-auth.bearer-token");
          if (bearer) headers.Authorization = `Bearer ${bearer}`;
          const res = await fetch(`/api/native/v1/notes/${encodeURIComponent(noteId)}`, { headers });
          const data = (await res.json()) as { ok?: boolean; note?: SpikeNote; error?: string };
          if (!res.ok || !data.note) {
            setStatus(`fetch failed: ${data.error ?? res.status}`);
            postToNative({ type: "error", message: data.error ?? String(res.status) });
            return;
          }
          setNote(data.note);
          setText(textFromNote(data.note));
          setStatus(`fetched ${data.note.id}`);
          postToNative({ type: "ready", noteId: data.note.id });
        } catch (error) {
          setStatus(String(error));
          postToNative({ type: "error", message: String(error) });
        }
      })();
    }

    return () => {
      window.removeEventListener("message", onMessage);
      if (debounce.current) window.clearTimeout(debounce.current);
    };
  }, [noteId, demo]);

  function onChange(next: string) {
    setText(next);
    if (!note || readOnly) return;
    if (debounce.current) window.clearTimeout(debounce.current);
    debounce.current = window.setTimeout(() => {
      const updated = noteFromText(note, next);
      setNote(updated);
      postToNative({ type: "noteChanged", note: updated });
    }, 280);
  }

  return (
    <main
      style={{
        margin: 0,
        minHeight: "100dvh",
        background: "#0c0c0c",
        color: "#f2f2f2",
        fontFamily: "ui-sans-serif, system-ui, sans-serif",
        padding: "12px",
        boxSizing: "border-box",
      }}
    >
      <p style={{ margin: "0 0 8px", fontSize: 12, opacity: 0.55 }} data-testid="editor-status">
        {status}
      </p>
      <textarea
        id="miolo"
        value={text}
        readOnly={readOnly}
        onChange={(event) => onChange(event.target.value)}
        spellCheck
        style={{
          width: "100%",
          minHeight: "70dvh",
          border: "none",
          outline: "none",
          resize: "vertical",
          background: "transparent",
          color: "inherit",
          fontSize: 17,
          lineHeight: 1.45,
          padding: 0,
        }}
        placeholder="Note body…"
      />
    </main>
  );
}
