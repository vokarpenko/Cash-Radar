import { GmailError } from "./gmail.ts";
import type { AttachmentRef } from "./gmail.ts";
import type { Route, Store } from "./poll.ts";
import { handleImport } from "../import-statement/handler.ts";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export class Database implements Store {
  constructor(
    private base: string,
    private key: string,
    private user: string,
  ) {}
  private async request(
    path: string,
    init: RequestInit = {},
  ): Promise<unknown> {
    const res = await fetch(this.base + "/rest/v1/" + path, {
      ...init,
      headers: {
        apikey: this.key,
        Authorization: `Bearer ${this.key}`,
        "content-type": "application/json",
        ...init.headers,
      },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) throw new GmailError("database_unavailable");
    try {
      const body = await res.text();
      return body ? JSON.parse(body) : null;
    } catch {
      throw new GmailError("database_unavailable");
    }
  }
  async record(
    scanned: number,
    prepared: number,
    failed: number,
    error: string | null,
  ): Promise<void> {
    await this.request("gmail_collector_runs", {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        user_id: this.user,
        scanned,
        prepared,
        failed,
        error_code: error,
      }),
    });
  }
  async checkRoute(r: Route): Promise<void> {
    const q = new URLSearchParams({
      select: "id,bank_id,is_active",
      id: `eq.${r.accountId}`,
      user_id: `eq.${this.user}`,
      limit: "1",
    });
    const rows = await this.request("accounts?" + q);
    if (
      !Array.isArray(rows) || rows.length !== 1 || !rows[0].is_active ||
      !rows[0].bank_id
    ) throw new GmailError("account_unavailable");
    const b = new URLSearchParams({
      select: "code",
      id: `eq.${rows[0].bank_id}`,
      limit: "1",
    });
    const banks = await this.request("banks?" + b);
    if (
      !Array.isArray(banks) || banks.length !== 1 ||
      banks[0].code !== r.bankCode
    ) throw new GmailError("account_unavailable");
  }
  async cursor(labelId: string): Promise<string | undefined> {
    const q = new URLSearchParams({
      select: "page_token",
      user_id: `eq.${this.user}`,
      label_id: `eq.${labelId}`,
      limit: "1",
    });
    const data = await this.request("gmail_poll_cursors?" + q);
    if (!Array.isArray(data) || data.length > 1) {
      throw new GmailError("database_unavailable");
    }
    return data[0]?.page_token ?? undefined;
  }
  async setCursor(labelId: string, cursor?: string): Promise<void> {
    await this.request("gmail_poll_cursors?on_conflict=user_id,label_id", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify({
        user_id: this.user,
        label_id: labelId,
        page_token: cursor ?? null,
        updated_at: new Date().toISOString(),
      }),
    });
  }
  async claim(
    route: Route,
    message: string,
    ref: AttachmentRef,
    lease: string,
  ): Promise<"claimed" | "complete" | "busy" | "wrong_account"> {
    const data = await this.request("rpc/gmail_claim_attachment", {
      method: "POST",
      body: JSON.stringify({
        p_user: this.user,
        p_account: route.accountId,
        p_message: message,
        p_attachment: ref.attachmentId,
        p_lease: lease,
      }),
    });
    if (
      data !== "claimed" && data !== "complete" && data !== "busy" &&
      data !== "wrong_account"
    ) throw new GmailError("database_unavailable");
    return data;
  }
  async finish(
    message: string,
    ref: AttachmentRef,
    lease: string,
    batch: string | null,
    error: string | null,
  ): Promise<boolean> {
    return await this.request("rpc/gmail_finish_attachment", {
      method: "POST",
      body: JSON.stringify({
        p_user: this.user,
        p_message: message,
        p_attachment: ref.attachmentId,
        p_lease: lease,
        p_batch: batch,
        p_error: error,
      }),
    }) === true;
  }
  async prepare(
    route: Route,
    bytes: Uint8Array,
    filename: string,
  ): Promise<{ batch: string }> {
    // ACBA is deliberately disabled for the first version; no bank password is stored.
    if (
      bytes.length >= 8 &&
      [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1].every((b, i) =>
        bytes[i] === b
      )
    ) throw new GmailError("unsupported_encrypted");
    let binary = "";
    for (let i = 0; i < bytes.length; i += 8192) {
      binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
    }
    const req = new Request("http://localhost/internal", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        account_id: route.accountId,
        filename,
        file_base64: btoa(binary),
      }),
    });
    const response = await handleImport(req, this.user);
    if (!response.ok) throw new GmailError("import_failed");
    const parsed = await response.json();
    if (typeof parsed.id !== "string" || !uuid.test(parsed.id)) {
      throw new GmailError("import_failed");
    }
    const q = new URLSearchParams({
      select: "account_id",
      id: `eq.${parsed.id}`,
      user_id: `eq.${this.user}`,
      limit: "1",
    });
    const batch = await this.request("import_batches?" + q);
    if (
      !Array.isArray(batch) || batch.length !== 1 ||
      batch[0].account_id !== route.accountId
    ) throw new GmailError("wrong_account");
    return { batch: parsed.id };
  }
}
