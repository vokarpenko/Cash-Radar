import {
  GmailClient,
  GmailError,
  refreshAccessToken,
} from "../functions/gmail-collector/gmail.ts";
function assert(v: unknown, message = "assertion failed"): asserts v {
  if (!v) throw Error(message);
}
function response(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}
async function rejects(f: () => Promise<unknown>, code: string) {
  try {
    await f();
  } catch (e) {
    assert(e instanceof GmailError && e.code === code, `wrong error ${e}`);
    return;
  }
  throw Error(`expected ${code}`);
}
Deno.test("Gmail requests bounded pages, traverses multipart XLSX and adds only the chosen label", async () => {
  const calls: { url: string; method: string; body?: string }[] = [];
  const fetcher = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    calls.push({
      url,
      method: init?.method ?? "GET",
      body: typeof init?.body === "string" ? init.body : undefined,
    });
    assert(
      new Headers(init?.headers).get("authorization") ===
        "Bearer local-access-token",
    );
    if (url.includes("/messages?")) {
      return Promise.resolve(
        response({ messages: [{ id: "msg_1" }], nextPageToken: "next_1" }),
      );
    }
    if (url.includes("/attachments/")) {
      return Promise.resolve(response({ data: "AQID", size: 3 }));
    }
    if (url.endsWith("/modify")) {
      return Promise.resolve(response({ id: "msg_1" }));
    }
    return Promise.resolve(
      response({
        id: "msg_1",
        payload: {
          parts: [{
            filename: "",
            parts: [{
              partId: "2",
              filename: "synthetic.xlsx",
              body: { attachmentId: "attach_1", size: 3 },
            }, { filename: "image.png", body: {} }],
          }],
        },
      }),
    );
  }) as typeof fetch;
  const gmail = new GmailClient("local-access-token", fetcher);
  const page = await gmail.list("Label_1");
  assert(page.ids[0] === "msg_1" && page.nextPageToken === "next_1");
  const msg = await gmail.message("msg_1");
  assert(
    msg.attachments.length === 1 &&
      msg.attachments[0].filename === "synthetic.xlsx",
  );
  const bytes = await gmail.attachment(msg.id, msg.attachments[0]);
  assert(bytes.join(",") === "1,2,3");
  await gmail.mark(msg.id, "Label_done", "Label_1");
  assert(
    calls.every((c) =>
      c.url.startsWith("https://gmail.googleapis.com/gmail/v1/users/me/")
    ),
  );
  assert(calls[0].url.includes("labelIds=Label_1"));
  assert(
    calls[3].body ===
      '{"addLabelIds":["Label_done"],"removeLabelIds":["Label_1"]}',
  );
});
Deno.test("Gmail rejects oversized and malformed attachments, and does not leak response content", async () => {
  const fake = (data: unknown, status = 200) =>
    ((_input: RequestInfo | URL, _init?: RequestInit) =>
      Promise.resolve(response(data, status))) as typeof fetch;
  const large = new GmailClient(
    "token",
    fake({
      id: "a",
      payload: {
        partId: "1",
        filename: "x.xlsx",
        body: { attachmentId: "b", size: 1048577 },
      },
    }),
  );
  await rejects(() => large.message("a"), "invalid_attachment_size");
  const unsupported = new GmailClient(
    "token",
    fake({
      id: "a",
      payload: {
        parts: [{
          partId: "1",
          filename: "statement.pdf",
          body: { attachmentId: "b", size: 3 },
        }, {
          partId: "2",
          filename: "statement.xlsx",
          body: { attachmentId: "c", size: 3 },
        }],
      },
    }),
  );
  await rejects(() => unsupported.message("a"), "unsupported_attachment");
  const broken = new GmailClient("token", fake({ data: "AA", size: 2 }));
  await rejects(
    () =>
      broken.attachment("a", {
        partId: "1",
        attachmentId: "b",
        filename: "x.xlsx",
        size: 2,
      }),
    "invalid_attachment",
  );
  const failed = new GmailClient(
    "token",
    fake({ private: "not-for-logs" }, 429),
  );
  await rejects(() => failed.list("Label_1"), "rate_limited");
  await rejects(() => failed.list("../bad"), "invalid_provider_response");
});
Deno.test("OAuth refresh sends credentials only to Google and reduces failures to safe codes", async () => {
  const credentials = {
    clientId: "client",
    clientSecret: "secret",
    refreshToken: "refresh",
  };
  const good = ((input: RequestInfo | URL, init?: RequestInit) => {
    assert(String(input) === "https://oauth2.googleapis.com/token");
    assert(init?.method === "POST");
    return Promise.resolve(response({ access_token: "access" }));
  }) as typeof fetch;
  assert(await refreshAccessToken(credentials, good) === "access");
  const denied =
    ((_input: RequestInfo | URL, _init?: RequestInit) =>
      Promise.resolve(
        response({ error: "invalid_grant", details: "sensitive" }, 400),
      )) as typeof fetch;
  await rejects(
    () => refreshAccessToken(credentials, denied),
    "authorization_expired",
  );
});
