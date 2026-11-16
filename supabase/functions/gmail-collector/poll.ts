import type { AttachmentRef, Message } from "./gmail.ts";
import { GmailError } from "./gmail.ts";
export type Route = {
  labelId: string;
  accountId: string;
  bankCode: "ameria_am" | "alfa_ru";
};
export interface Mailbox {
  list(
    label: string,
    page?: string,
  ): Promise<{ ids: string[]; nextPageToken?: string }>;
  message(id: string): Promise<Message>;
  attachment(id: string, ref: AttachmentRef): Promise<Uint8Array>;
  mark(id: string, done: string, source: string): Promise<void>;
}
export interface Store {
  cursor(label: string): Promise<string | undefined>;
  setCursor(label: string, cursor?: string): Promise<void>;
  claim(
    route: Route,
    message: string,
    ref: AttachmentRef,
    lease: string,
  ): Promise<"claimed" | "complete" | "busy" | "wrong_account">;
  finish(
    message: string,
    ref: AttachmentRef,
    lease: string,
    batch: string | null,
    error: string | null,
  ): Promise<boolean>;
  prepare(
    route: Route,
    bytes: Uint8Array,
    filename: string,
  ): Promise<{ batch: string }>;
}
export type Stats = {
  scanned: number;
  prepared: number;
  failed: number;
  marked: number;
  errorCode?: string;
};
export async function poll(
  mail: Mailbox,
  store: Store,
  routes: Route[],
  done: string,
  now: () => number = Date.now,
): Promise<Stats> {
  const started = now(),
    stats: Stats = { scanned: 0, prepared: 0, failed: 0, marked: 0 };
  const allowed = [
    "authorization_expired",
    "rate_limited",
    "provider_unavailable",
    "unsupported_attachment",
    "unsupported_encrypted",
    "wrong_account",
    "invalid_attachment",
    "invalid_attachment_size",
    "message_too_complex",
  ];
  function failure(e?: unknown): string {
    stats.failed++;
    const code = e instanceof GmailError && allowed.includes(e.code)
      ? e.code
      : "import_failed";
    stats.errorCode ??= code;
    return code;
  }
  for (const route of routes) {
    if (now() - started >= 85_000) break;
    const cursor = await store.cursor(route.labelId);
    let page;
    try {
      page = await mail.list(route.labelId, cursor);
    } catch (e) {
      if (cursor && e instanceof GmailError && e.status === 400) {
        await store.setCursor(route.labelId);
        failure();
        continue;
      }
      throw e;
    }
    let pageFinished = true;
    for (const id of page.ids) {
      if (now() - started >= 85_000) {
        pageFinished = false;
        break;
      }
      stats.scanned++;
      let msg: Message;
      try {
        msg = await mail.message(id);
      } catch (e) {
        failure(e);
        continue;
      }
      if (!msg.attachments.length) {
        failure(new GmailError("unsupported_attachment"));
        continue;
      }
      let allComplete = true;
      for (const ref of msg.attachments) {
        if (now() - started >= 85_000) {
          allComplete = false;
          pageFinished = false;
          break;
        }
        const lease = crypto.randomUUID();
        const claim = await store.claim(route, id, ref, lease);
        if (claim === "complete") continue;
        if (claim !== "claimed") {
          allComplete = false;
          failure(
            claim === "wrong_account"
              ? new GmailError("wrong_account")
              : undefined,
          );
          continue;
        }
        try {
          const bytes = await mail.attachment(id, ref);
          const prepared = await store.prepare(route, bytes, ref.filename);
          if (!await store.finish(id, ref, lease, prepared.batch, null)) {
            allComplete = false;
            failure();
          } else stats.prepared++;
        } catch (e) {
          allComplete = false;
          const code = failure(e);
          await store.finish(id, ref, lease, null, code);
        }
      }
      if (allComplete) {
        try {
          await mail.mark(id, done, route.labelId);
          stats.marked++;
        } catch (e) {
          failure(e);
        }
      }
      if (!pageFinished) break;
    }
    if (pageFinished) await store.setCursor(route.labelId, page.nextPageToken);
  }
  return stats;
}
