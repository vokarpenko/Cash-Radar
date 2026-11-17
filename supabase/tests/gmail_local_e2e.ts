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
const acbaBytes = await Deno.readFile(
  new URL("./fixtures/acba_encrypted_synthetic.xlsx", import.meta.url),
);
const acbaHash = Array.from(
  new Uint8Array(await crypto.subtle.digest("SHA-256", acbaBytes)),
  (b) => b.toString(16).padStart(2, "0"),
).join("");
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
  const acbaBank = await api("/rest/v1/banks?select=id&code=eq.acba_am");
  const acbaAccountId = crypto.randomUUID();
  await api("/rest/v1/accounts", "POST", {
    id: acbaAccountId,
    user_id: userId,
    name: "Synthetic ACBA",
    account_type: "bank",
    currency: "AMD",
    bank_id: acbaBank[0].id,
    initial_balance: "0",
  });
  const acbaRoute: Route = {
    labelId: "Label_acba",
    accountId: acbaAccountId,
    bankCode: "acba_am",
  };
  const wrong = new Database(base, key, userId, "incorrect-synthetic-password");
  const good = new Database(base, key, userId, "synthetic-only");
  await good.checkRoute(acbaRoute);
  let missingPassword = false;
  try {
    await db.prepare(acbaRoute, acbaBytes, "acba.xlsx");
  } catch (e) {
    missingPassword = e instanceof Error &&
      e.message === "acba_password_missing";
  }
  assert(missingPassword, "missing ACBA password was not detected");
  const acbaMail: Mailbox = {
    list: () => Promise.resolve({ ids: ["synthetic_acba"] }),
    message: (id) =>
      Promise.resolve({
        id,
        attachments: [{
          partId: "0",
          attachmentId: "synthetic_acba_attachment",
          filename: "acba.xlsx",
          size: acbaBytes.length,
        }],
      }),
    attachment: () => Promise.resolve(acbaBytes),
    mark: () => {
      marks++;
      return Promise.resolve();
    },
  };
  const marksBefore = marks;
  const failed = await poll(acbaMail, wrong, [acbaRoute], "Label_done");
  assert(
    failed.failed === 1 && failed.errorCode === "acba_password_invalid" &&
      marks === marksBefore,
    "wrong password did not block ACBA message",
  );
  const failedJob = await api(
    `/rest/v1/gmail_import_jobs?select=id,error_code&user_id=eq.${userId}&status=eq.failed`,
  );
  assert(
    failedJob.length === 1 &&
      failedJob[0].error_code === "acba_password_invalid",
    "wrong password error was not recorded safely",
  );
  await api(`/rest/v1/gmail_import_jobs?id=eq.${failedJob[0].id}`, "PATCH", {
    updated_at: "2000-01-01T00:00:00Z",
  });
  const acbaResult = await poll(acbaMail, good, [acbaRoute], "Label_done");
  assert(
    acbaResult.prepared === 1 && acbaResult.marked === 1 &&
      acbaResult.failed === 0,
    "ACBA retry did not succeed",
  );
  const acbaBatches = await api(
    `/rest/v1/import_batches?select=id,status,row_count,object_path&user_id=eq.${userId}&account_id=eq.${acbaAccountId}`,
  );
  assert(
    acbaBatches.length === 1 && acbaBatches[0].status === "ready" &&
      acbaBatches[0].row_count === 2,
    "wrong ACBA preview",
  );
  const stored = await fetch(
    base +
      `/storage/v1/object/authenticated/statements/${userId}/${acbaHash}.xlsx`,
    { headers },
  );
  assert(stored.ok, "encrypted original missing");
  const storedBytes = new Uint8Array(await stored.arrayBuffer());
  assert(
    storedBytes.length === acbaBytes.length &&
      storedBytes.every((b, i) => b === acbaBytes[i]),
    "encrypted original was not preserved",
  );
  const safeJobs = await api(
    `/rest/v1/gmail_import_jobs?select=*&user_id=eq.${userId}`,
  );
  assert(
    !JSON.stringify(safeJobs).includes("synthetic-only"),
    "password leaked into job records",
  );
  const allTransactions = await api(
    `/rest/v1/transactions?select=id&user_id=eq.${userId}`,
  );
  assert(allTransactions.length === 0, "ACBA was automatically confirmed");
  let rejected = false;
  try {
    await good.prepare(route, acbaBytes, "encrypted.xlsx");
  } catch {
    rejected = true;
  }
  assert(rejected, "encrypted statement accepted on wrong bank");
  const retry = await poll(acbaMail, good, [acbaRoute], "Label_done");
  assert(
    retry.prepared === 0 && retry.failed === 0,
    "repeated ACBA message was not idempotent",
  );
  console.log(
    "Local Gmail collector: Alfa and encrypted ACBA, invalid-password retry, encrypted storage and duplicate delivery passed.",
  );
} finally {
  if (created) {
    await api("/storage/v1/object/statements", "DELETE", {
      prefixes: [`${userId}/${hash}.xlsx`, `${userId}/${acbaHash}.xlsx`],
    });
    await api(`/auth/v1/admin/users/${userId}`, "DELETE");
  }
}
