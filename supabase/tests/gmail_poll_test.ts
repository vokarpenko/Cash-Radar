import {
  type Mailbox,
  poll,
  type Route,
  type Store,
} from "../functions/gmail-collector/poll.ts";
import {
  type AttachmentRef,
  GmailError,
} from "../functions/gmail-collector/gmail.ts";
function check(v: unknown, m = "assertion failed"): asserts v {
  if (!v) throw Error(m);
}
const route: Route = {
  labelId: "Label_in",
  accountId: "00000000-0000-4000-8000-000000000001",
  bankCode: "alfa_ru",
};
const ref: AttachmentRef = {
  partId: "0",
  attachmentId: "att_1",
  filename: "synthetic.xlsx",
  size: 1,
};
function fake() {
  const completed = new Set<string>(),
    marked: string[] = [],
    prepared: string[] = [],
    claims = new Map<string, string>();
  let fail = false, cursor: string | undefined, saved: string | undefined;
  const mail: Mailbox = {
    list: () =>
      Promise.resolve({ ids: ["one", "two"], nextPageToken: "next_page" }),
    message: (id) => Promise.resolve({ id, attachments: [ref] }),
    attachment: (id) =>
      id === "two" && fail
        ? Promise.reject(Error("private provider error"))
        : Promise.resolve(new Uint8Array([1])),
    mark: (id, done, source) => {
      check(done === "Label_done" && source === route.labelId);
      marked.push(id);
      return Promise.resolve();
    },
  };
  const store: Store = {
    cursor: () => Promise.resolve(cursor),
    setCursor: (_label, v) => {
      saved = v;
      return Promise.resolve();
    },
    claim: (_r, id, _ref, lease) => {
      if (completed.has(id)) return Promise.resolve("complete");
      if (claims.has(id)) return Promise.resolve("busy");
      claims.set(id, lease);
      return Promise.resolve("claimed");
    },
    finish: (id, _ref, lease, batch, _err) => {
      check(claims.get(id) === lease);
      claims.delete(id);
      if (batch) completed.add(id);
      return Promise.resolve(true);
    },
    prepare: (_r, _bytes, name) => {
      prepared.push(name);
      return Promise.resolve({ batch: "batch_1" });
    },
  };
  return {
    mail,
    store,
    completed,
    marked,
    prepared,
    setFail: (b: boolean) => fail = b,
    setCursor: (v: string) => cursor = v,
    getSaved: () => saved,
  };
}
Deno.test("Gmail polling processes and marks successful mail, with idempotent repeated delivery", async () => {
  const f = fake();
  const first = await poll(f.mail, f.store, [route], "Label_done");
  check(
    first.prepared === 2 && first.marked === 2 && first.failed === 0 &&
      f.getSaved() === "next_page",
  );
  const again = await poll(f.mail, f.store, [route], "Label_done");
  check(again.prepared === 0 && again.marked === 2 && f.prepared.length === 2);
});
Deno.test("Gmail polling never marks failed attachments and retries them", async () => {
  const f = fake();
  f.setFail(true);
  const first = await poll(f.mail, f.store, [route], "Label_done");
  check(
    first.prepared === 1 && first.failed === 1 && f.marked.join(",") === "one",
  );
  f.setFail(false);
  const second = await poll(f.mail, f.store, [route], "Label_done");
  check(second.prepared === 1 && f.completed.has("two"));
});
Deno.test("Gmail polling resets an expired provider cursor and resumes next cycle", async () => {
  const f = fake();
  f.setCursor("expired");
  f.mail.list = () => Promise.reject(new GmailError("provider_error", 400));
  const stats = await poll(f.mail, f.store, [route], "Label_done");
  check(stats.failed === 1 && f.getSaved() === undefined);
});
Deno.test("Gmail polling preserves cursor when runtime expires mid-page", async () => {
  const f = fake();
  let calls = 0;
  const stats = await poll(
    f.mail,
    f.store,
    [route],
    "Label_done",
    () => ++calls > 3 ? 86_000 : 0,
  );
  check(
    stats.prepared === 0 && f.getSaved() === undefined && f.marked.length === 0,
  );
});
