import { GmailClient, GmailError, refreshAccessToken } from "./gmail.ts";
import { poll, type Route } from "./poll.ts";
import { Database } from "./database.ts";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const label = /^Label_[A-Za-z0-9_-]{1,250}$/;
function secret(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new GmailError("not_configured");
  return value;
}
function safeEqual(a: string, b: string): boolean {
  let diff = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) {
    diff |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  }
  return diff === 0;
}
function config(): {
  user: string;
  email: string;
  done: string;
  routes: Route[];
} {
  const user = secret("GMAIL_OWNER_USER_ID"),
    email = secret("GMAIL_EXPECTED_ADDRESS").toLowerCase(),
    done = secret("GMAIL_DONE_LABEL_ID");
  if (
    !uuid.test(user) || !label.test(done) || !/^[^\s@]+@gmail\.com$/.test(email)
  ) throw new GmailError("not_configured");
  let values: unknown;
  try {
    values = JSON.parse(secret("GMAIL_ROUTES_JSON"));
  } catch {
    throw new GmailError("not_configured");
  }
  if (!Array.isArray(values) || values.length < 1 || values.length > 3) {
    throw new GmailError("not_configured");
  }
  const routes: Route[] = values.map((v: unknown) => {
    if (!v || typeof v !== "object" || Array.isArray(v)) {
      throw new GmailError("not_configured");
    }
    const r = v as Record<string, unknown>;
    if (
      typeof r.labelId !== "string" || !label.test(r.labelId) ||
      r.labelId === done || typeof r.accountId !== "string" ||
      !uuid.test(r.accountId) ||
      (r.bankCode !== "ameria_am" && r.bankCode !== "alfa_ru")
    ) throw new GmailError("not_configured");
    return { labelId: r.labelId, accountId: r.accountId, bankCode: r.bankCode };
  });
  if (new Set(routes.map((r) => r.labelId)).size !== routes.length) {
    throw new GmailError("not_configured");
  }
  return { user, email, done, routes };
}
function reply(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
}
Deno.serve(async (req) => {
  if (req.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  let db: Database | undefined;
  try {
    const url = secret("SUPABASE_URL"),
      service = secret("SUPABASE_SERVICE_ROLE_KEY");
    if (
      !safeEqual(req.headers.get("authorization") ?? "", `Bearer ${service}`)
    ) return reply({ error: "unauthorized" }, 401);
    const cfg = config();
    db = new Database(url, service, cfg.user);
    for (const route of cfg.routes) await db.checkRoute(route);
    const access = await refreshAccessToken({
      clientId: secret("GMAIL_CLIENT_ID"),
      clientSecret: secret("GMAIL_CLIENT_SECRET"),
      refreshToken: secret("GMAIL_REFRESH_TOKEN"),
    });
    const mail = new GmailClient(access);
    if (await mail.profile() !== cfg.email) {
      throw new GmailError("mailbox_mismatch");
    }
    const stats = await poll(mail, db, cfg.routes, cfg.done);
    await db.record(
      stats.scanned,
      stats.prepared,
      stats.failed,
      stats.errorCode ?? null,
    );
    return reply(stats);
  } catch (e) {
    const code = e instanceof GmailError ? e.code : "collector_unavailable";
    // Never log Gmail responses, message contents, addresses or credentials.
    console.error("gmail collector:", code);
    if (db) {
      try {
        await db.record(0, 0, 0, code);
      } catch {
        console.error("gmail collector: log_unavailable");
      }
    }
    return reply({ error: code }, 503);
  }
});
