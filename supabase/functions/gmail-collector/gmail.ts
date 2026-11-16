// Gmail transport. No message bodies, credentials, or provider responses are logged.
const api = "https://gmail.googleapis.com/gmail/v1/users/me";
const tokenUrl = "https://oauth2.googleapis.com/token";
const maxAttachmentBytes = 1024 * 1024;
const validId = /^[A-Za-z0-9_-]{1,256}$/;

type Fetch = typeof fetch;
type Json = Record<string, unknown>;
export class GmailError extends Error {
  constructor(public code: string, public status?: number) {
    super(code);
  }
}
function object(value: unknown): Json {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new GmailError("invalid_provider_response");
  }
  return value as Json;
}
function identifier(value: unknown): string {
  if (typeof value !== "string" || !validId.test(value)) {
    throw new GmailError("invalid_provider_response");
  }
  return value;
}
function pageTokenValue(value: unknown): string {
  if (typeof value !== "string" || !/^[\x21-\x7e]{1,2048}$/.test(value)) {
    throw new GmailError("invalid_provider_response");
  }
  return value;
}
async function jsonResponse(res: Response): Promise<Json> {
  if (!res.ok) {
    throw new GmailError(
      res.status === 401
        ? "authorization_expired"
        : res.status === 429
        ? "rate_limited"
        : res.status >= 500
        ? "provider_unavailable"
        : "provider_error",
      res.status,
    );
  }
  try {
    const length = Number(res.headers.get("content-length") ?? "0");
    if (length > 1_500_000 || !res.body) {
      throw new GmailError("response_too_large");
    }
    const reader = res.body.getReader();
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 1_500_000) {
        await reader.cancel();
        throw new GmailError("response_too_large");
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    return object(
      JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
    );
  } catch (e) {
    if (e instanceof GmailError) throw e;
    throw new GmailError("invalid_provider_response");
  }
}
export async function refreshAccessToken(
  credentials: { clientId: string; clientSecret: string; refreshToken: string },
  fetcher: Fetch = fetch,
): Promise<string> {
  if (
    !credentials.clientId || !credentials.clientSecret ||
    !credentials.refreshToken
  ) throw new GmailError("not_configured");
  const body = new URLSearchParams({
    client_id: credentials.clientId,
    client_secret: credentials.clientSecret,
    refresh_token: credentials.refreshToken,
    grant_type: "refresh_token",
  });
  const res = await fetcher(tokenUrl, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
    signal: AbortSignal.timeout(12_000),
  });
  if (!res.ok) {
    throw new GmailError(
      res.status === 400 || res.status === 401
        ? "authorization_expired"
        : "provider_unavailable",
      res.status,
    );
  }
  const json = await jsonResponse(res);
  if (
    typeof json.access_token !== "string" || !json.access_token ||
    json.access_token.length > 8192
  ) throw new GmailError("invalid_provider_response");
  return json.access_token;
}
export type AttachmentRef = {
  partId: string;
  attachmentId: string;
  filename: string;
  size: number;
};
export type Message = { id: string; attachments: AttachmentRef[] };
function attachments(payload: unknown): AttachmentRef[] {
  const result: AttachmentRef[] = [];
  const todo: { value: unknown; depth: number }[] = [{
    value: payload,
    depth: 0,
  }];
  let nodes = 0;
  while (todo.length) {
    const { value, depth } = todo.pop()!;
    if (++nodes > 200 || depth > 12) {
      throw new GmailError("message_too_complex");
    }
    const part = object(value);
    if (Array.isArray(part.parts)) {
      for (const p of part.parts) todo.push({ value: p, depth: depth + 1 });
    }
    if (part.filename === undefined || part.filename === "") continue;
    if (
      typeof part.filename !== "string" || part.filename.length > 160 ||
      /[\\/\x00-\x1f\x7f]/.test(part.filename)
    ) throw new GmailError("invalid_attachment");
    // Embedded logos and signatures may accompany a statement. An unsupported
    // document must keep the message unprocessed rather than being lost silently.
    if (/\.(?:png|jpe?g|gif|webp|svg|p7s)$/i.test(part.filename)) continue;
    if (!/\.xlsx$/i.test(part.filename)) {
      throw new GmailError("unsupported_attachment");
    }
    const body = object(part.body);
    if (
      !Number.isSafeInteger(body.size) || (body.size as number) <= 0 ||
      (body.size as number) > maxAttachmentBytes
    ) throw new GmailError("invalid_attachment_size");
    result.push({
      partId:
        typeof part.partId === "string" && /^[0-9.]{0,64}$/.test(part.partId)
          ? part.partId
          : (() => {
            throw new GmailError("invalid_provider_response");
          })(),
      attachmentId: identifier(body.attachmentId),
      filename: part.filename,
      size: body.size as number,
    });
    if (result.length > 10) throw new GmailError("too_many_attachments");
  }
  return result;
}
export class GmailClient {
  constructor(private token: string, private fetcher: Fetch = fetch) {
    if (!token || token.length > 8192 || /[\r\n]/.test(token)) {
      throw new GmailError("invalid_token");
    }
  }
  private async request(path: string, init: RequestInit = {}): Promise<Json> {
    const response = await this.fetcher(api + path, {
      ...init,
      headers: { Authorization: `Bearer ${this.token}`, ...init.headers },
      signal: AbortSignal.timeout(12_000),
    });
    return await jsonResponse(response);
  }
  async profile(): Promise<string> {
    const data = await this.request("/profile");
    if (
      typeof data.emailAddress !== "string" ||
      !/^[^\s@]+@[^\s@]+$/.test(data.emailAddress) ||
      data.emailAddress.length > 254
    ) throw new GmailError("invalid_provider_response");
    return data.emailAddress.toLowerCase();
  }
  async list(
    labelId: string,
    pageToken?: string,
  ): Promise<{ ids: string[]; nextPageToken?: string }> {
    identifier(labelId);
    if (pageToken !== undefined && !/^[\x21-\x7e]{1,2048}$/.test(pageToken)) {
      throw new GmailError("invalid_provider_response");
    }
    const query = new URLSearchParams({
      labelIds: labelId,
      maxResults: "10",
      includeSpamTrash: "false",
    });
    if (pageToken) query.set("pageToken", pageToken);
    const data = await this.request("/messages?" + query);
    if (data.messages !== undefined && !Array.isArray(data.messages)) {
      throw new GmailError("invalid_provider_response");
    }
    const messages = (data.messages ?? []) as unknown[];
    if (messages.length > 10) throw new GmailError("invalid_provider_response");
    return {
      ids: messages.map((m) => identifier(object(m).id)),
      ...(data.nextPageToken !== undefined
        ? { nextPageToken: pageTokenValue(data.nextPageToken) }
        : {}),
    };
  }
  async message(id: string): Promise<Message> {
    identifier(id);
    let partFields = "partId,filename,body(attachmentId,size)";
    for (let i = 0; i < 10; i++) {
      partFields =
        `partId,filename,body(attachmentId,size),parts(${partFields})`;
    }
    const params = new URLSearchParams({
      format: "full",
      fields: `id,payload(${partFields})`,
    });
    const data = await this.request(`/messages/${id}?${params}`);
    if (identifier(data.id) !== id) {
      throw new GmailError("invalid_provider_response");
    }
    return { id, attachments: attachments(data.payload) };
  }
  async attachment(messageId: string, ref: AttachmentRef): Promise<Uint8Array> {
    identifier(messageId);
    identifier(ref.attachmentId);
    if (
      !Number.isSafeInteger(ref.size) || ref.size <= 0 ||
      ref.size > maxAttachmentBytes
    ) throw new GmailError("invalid_attachment_size");
    const data = await this.request(
      `/messages/${messageId}/attachments/${ref.attachmentId}`,
    );
    if (
      data.size !== ref.size || typeof data.data !== "string" ||
      data.data.length > Math.ceil(maxAttachmentBytes * 4 / 3) + 4 ||
      !/^[A-Za-z0-9_-]+={0,2}$/.test(data.data)
    ) throw new GmailError("invalid_attachment");
    let raw: string;
    try {
      raw = atob(data.data.replace(/-/g, "+").replace(/_/g, "/"));
    } catch {
      throw new GmailError("invalid_attachment");
    }
    if (raw.length !== ref.size) throw new GmailError("invalid_attachment");
    return Uint8Array.from(raw, (c) => c.charCodeAt(0));
  }
  async mark(
    messageId: string,
    doneLabelId: string,
    sourceLabelId: string,
  ): Promise<void> {
    identifier(messageId);
    identifier(doneLabelId);
    identifier(sourceLabelId);
    if (
      !/^Label_/.test(doneLabelId) || !/^Label_/.test(sourceLabelId) ||
      doneLabelId === sourceLabelId
    ) throw new GmailError("invalid_label");
    const result = await this.request(`/messages/${messageId}/modify`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        addLabelIds: [doneLabelId],
        removeLabelIds: [sourceLabelId],
      }),
    });
    if (identifier(result.id) !== messageId) {
      throw new GmailError("invalid_provider_response");
    }
  }
}
