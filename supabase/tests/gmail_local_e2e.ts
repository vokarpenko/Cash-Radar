// Explicitly local-only integration test. Google is replaced with a synthetic mailbox.
import { Database } from "../functions/gmail-collector/database.ts";
import {
  type Mailbox,
  poll,
  type Route,
} from "../functions/gmail-collector/poll.ts";
const base = Deno.env.get("SUPABASE_URL") ?? "";
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
if (base !== "http://127.0.0.1:54321" || !key) {
  throw Error("Requires local Supabase on 127.0.0.1:54321");
}
const headers = {
  apikey: key,
  Authorization: `Bearer ${key}`,
  "content-type": "application/json",
};
async function api(path: string, method = "GET", body?: unknown): Promise<any> {
  const res = await fetch(base + path, {
    method,
    headers: { ...headers, Prefer: "return=representation" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  if (!res.ok) {
    throw Error(`local endpoint failed (${res.status}): ${path.split("?")[0]}`);
  }
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}
function assert(v: unknown, m: string): asserts v {
  if (!v) throw Error(m);
}
const bytes = await Deno.readFile(
  new URL("./fixtures/alfa_synthetic.xlsx", import.meta.url),
);
const hash = Array.from(
  new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
  (b) => b.toString(16).padStart(2, "0"),
).join("");
const userId = crypto.randomUUID(), accountId = crypto.randomUUID();
let created = false;
try {
  await api("/auth/v1/admin/users", "POST", {
    id: userId,
    email: `gmail-collector-${userId}@example.test`,
    password: "synthetic-only-password-123",
    email_confirm: true,
  });
  created = true;
  const bank = await api("/rest/v1/banks?select=id&code=eq.alfa_ru");
  await api("/rest/v1/accounts", "POST", {
    id: accountId,
    user_id: userId,
    name: "Synthetic collector account",
    account_type: "bank",
    currency: "RUB",
    bank_id: bank[0].id,
    initial_balance: "0",
  });
  const route: Route = { labelId: "Label_in", accountId, bankCode: "alfa_ru" };
  const db = new Database(base, key, userId);
  await db.checkRoute(route);
  let currentId = "synthetic_message_1", marks = 0;
  const mail: Mailbox = {
    list: () => Promise.resolve({ ids: [currentId] }),
    message: (id) =>
      Promise.resolve({
        id,
        attachments: [{
          partId: "0",
          attachmentId: "a".repeat(404),
          filename: "synthetic.xlsx",
          size: bytes.length,
        }],
      }),
    attachment: () => Promise.resolve(bytes),
    mark: () => {
      marks++;
      return Promise.resolve();
    },
  };
  const first = await poll(mail, db, [route], "Label_done");
  assert(
    first.prepared === 1 && first.failed === 0 && first.marked === 1,
    "collector did not prepare synthetic statement",
  );
  const replay = await poll(mail, db, [route], "Label_done");
  assert(
    replay.prepared === 0 && replay.failed === 0 && marks === 2,
    "message retry was not idempotent",
  );
  currentId = "synthetic_message_2";
  const duplicate = await poll(mail, db, [route], "Label_done");
  assert(
    duplicate.prepared === 1 && duplicate.failed === 0,
    "duplicate attachment was not reused",
  );
  const batches = await api(
    `/rest/v1/import_batches?select=id,status&user_id=eq.${userId}`,
  );
  const transactions = await api(
    `/rest/v1/transactions?select=id&user_id=eq.${userId}`,
  );
  const jobs = await api(
    `/rest/v1/gmail_import_jobs?select=status,batch_id&user_id=eq.${userId}`,
  );
  assert(
    batches.length === 1 && batches[0].status === "ready" &&
      transactions.length === 0,
    "automatic import created transactions or duplicate batches",
  );
  assert(
    jobs.length === 2 &&
      jobs.every((j: any) =>
        j.status === "complete" && j.batch_id === batches[0].id
      ),
    "collector jobs not recorded",
  );
  await db.record(3, 2, 0, null);
  const logs = await api(
    `/rest/v1/gmail_collector_runs?select=scanned,prepared&user_id=eq.${userId}`,
  );
  assert(
    logs.length === 1 && logs[0].scanned === 3,
    "collector run was not recorded",
  );
  let rejected = false;
  try {
    await db.prepare(
      route,
      new Uint8Array([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]),
      "encrypted.xlsx",
    );
  } catch {
    rejected = true;
  }
  assert(rejected, "encrypted attachment was accepted");
  console.log(
    "Local Gmail collector: synthetic preparation, duplicate delivery, private job state and no auto-confirmation passed.",
  );
} finally {
  if (created) {
    await api("/storage/v1/object/statements", "DELETE", {
      prefixes: [`${userId}/${hash}.xlsx`],
    });
    await api(`/auth/v1/admin/users/${userId}`, "DELETE");
  }
}
