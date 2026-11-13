import {
  CategorizationError,
  type Group,
  isEligiblePublicName,
  MAX_GROUPS,
  queryGemini,
} from "./core.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
  "Content-Type": "application/json; charset=utf-8",
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const groupId = /^[a-f0-9]{32}$/;
function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: cors });
}
class Problem extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") {
    return reply({ error: "Метод не поддерживается." }, 405);
  }
  const url = Deno.env.get("SUPABASE_URL"),
    anon = Deno.env.get("SUPABASE_ANON_KEY"),
    service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    key = Deno.env.get("GEMINI_API_KEY");
  if (!url || !anon || !service || !key) {
    return reply({ error: "AI-категоризация не настроена." }, 503);
  }
  const authorization = req.headers.get("authorization") ?? "";
  let userId: string | undefined;
  let token: string | undefined;
  const serviceHeaders = {
    apikey: service,
    Authorization: `Bearer ${service}`,
    "Content-Type": "application/json",
  };
  try {
    if (!/^Bearer [A-Za-z0-9_.-]+$/.test(authorization)) {
      throw new Problem(401, "Войдите в аккаунт заново.");
    }
    const auth = await fetch(`${url}/auth/v1/user`, {
      headers: { apikey: anon, Authorization: authorization },
    });
    if (!auth.ok) throw new Problem(401, "Войдите в аккаунт заново.");
    const user = await auth.json();
    if (typeof user.id !== "string" || !uuid.test(user.id)) {
      throw new Problem(401, "Войдите в аккаунт заново.");
    }
    userId = user.id;
    if (Number(req.headers.get("content-length") ?? "0") > 4096 || !req.body) {
      throw new Problem(400, "Некорректный запрос.");
    }
    const reader = req.body.getReader();
    const parts: Uint8Array[] = [];
    let total = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        total += value.length;
        if (total > 4096) {
          await reader.cancel();
          throw new Problem(400, "Некорректный запрос.");
        }
        parts.push(value);
      }
    } finally {
      reader.releaseLock();
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const part of parts) {
      bytes.set(part, offset);
      offset += part.length;
    }
    let body: Record<string, unknown>;
    try {
      body = JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(bytes),
      );
    } catch {
      throw new Problem(400, "Некорректный запрос.");
    }
    if (
      !body || typeof body !== "object" || typeof body.batch_id !== "string" ||
      !uuid.test(body.batch_id) || !Array.isArray(body.groups) ||
      !body.groups.length || body.groups.length > MAX_GROUPS
    ) throw new Problem(400, "Выберите до 10 названий.");
    const selected = body.groups as Array<Record<string, unknown>>;
    if (
      selected.some((x) =>
        !x || typeof x.group_id !== "string" || !groupId.test(x.group_id) ||
        typeof x.merchant !== "string" || !isEligiblePublicName(x.merchant)
      ) || new Set(selected.map((x) => x.group_id)).size !== selected.length
    ) throw new Problem(400, "Проверьте выбранные названия.");
    token = crypto.randomUUID();
    const reserve = await fetch(`${url}/rest/v1/rpc/ai_reserve`, {
      method: "POST",
      headers: serviceHeaders,
      body: JSON.stringify({ p_user: userId, p_token: token }),
    });
    if (!reserve.ok || await reserve.json() !== true) {
      token = undefined;
      throw new Problem(429, "Запрос уже выполняется. Повторите позже.");
    }
    const candidates = await fetch(`${url}/rest/v1/rpc/ai_import_candidates`, {
      method: "POST",
      headers: {
        apikey: anon,
        Authorization: authorization,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_batch_id: body.batch_id }),
    });
    if (!candidates.ok) throw new Problem(403, "Импорт недоступен.");
    const rows = await candidates.json();
    if (!Array.isArray(rows)) {
      throw new Problem(503, "Не удалось проверить импорт.");
    }
    const groups: Group[] = selected.map((selection) => {
      const row = rows.find((r: Record<string, unknown>) =>
        r.group_id === selection.group_id && r.merchant === selection.merchant
      );
      if (!row || !["income", "expense"].includes(row.kind)) {
        throw new Problem(409, "Список изменился. Проверьте названия ещё раз.");
      }
      return { groupId: row.group_id, merchant: row.merchant, kind: row.kind };
    });
    const result = await queryGemini(key, groups);
    const save = await fetch(`${url}/rest/v1/rpc/ai_store_results`, {
      method: "POST",
      headers: serviceHeaders,
      body: JSON.stringify({
        p_user: userId,
        p_batch: body.batch_id,
        p_token: token,
        p_results: result.suggestions,
        p_model: result.model,
      }),
    });
    if (!save.ok) {
      throw new Problem(
        503,
        "Не удалось сохранить результат. Повторите позже.",
      );
    }
    return reply({ ...await save.json(), model: result.model });
  } catch (error) {
    if (error instanceof Problem) {
      return reply({ error: error.message }, error.status);
    }
    if (error instanceof CategorizationError) {
      return reply({ error: error.message }, 503);
    }
    return reply({ error: "AI-категоризация временно недоступна." }, 503);
  } finally {
    if (userId && token) {
      try {
        await fetch(`${url}/rest/v1/rpc/ai_release`, {
          method: "POST",
          headers: serviceHeaders,
          body: JSON.stringify({ p_user: userId, p_token: token }),
        });
      } catch { /* The lock also expires automatically. */ }
    }
  }
});
