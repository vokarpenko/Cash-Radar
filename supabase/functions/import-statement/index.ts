import {
  type Category,
  detectFormat,
  ImportFormatError,
  parseCashRadarCsv,
} from "./parser.ts";

const maxBytes = 1024 * 1024;
const maxRequestBytes = Math.ceil(maxBytes * 4 / 3) + 16384;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}
function response(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}
async function readJson(req: Request): Promise<Record<string, unknown>> {
  const length = Number(req.headers.get("content-length") ?? "0");
  if (length > maxRequestBytes || !req.body) {
    throw new HttpError(413, "Файл слишком большой. Максимум — 1 МиБ.");
  }
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.length;
      if (total > maxRequestBytes) {
        await reader.cancel();
        throw new HttpError(413, "Файл слишком большой. Максимум — 1 МиБ.");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const buffer = new Uint8Array(total);
  let at = 0;
  for (const chunk of chunks) {
    buffer.set(chunk, at);
    at += chunk.length;
  }
  try {
    const parsed = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(buffer),
    );
    if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") {
      throw Error();
    }
    return parsed;
  } catch {
    throw new HttpError(400, "Некорректный запрос.");
  }
}
function decodeFile(value: unknown): Uint8Array {
  if (
    typeof value !== "string" ||
    value.length > Math.ceil(maxBytes * 4 / 3) + 4 ||
    !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(
      value,
    )
  ) throw new HttpError(400, "Не удалось прочитать файл.");
  try {
    const decoded = atob(value);
    if (!decoded.length || decoded.length > maxBytes) {
      throw new HttpError(413, "Файл пуст или превышает 1 МиБ.");
    }
    const bytes = new Uint8Array(decoded.length);
    for (let i = 0; i < decoded.length; i++) bytes[i] = decoded.charCodeAt(i);
    return bytes;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(400, "Не удалось прочитать файл.");
  }
}
async function digest(bytes: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest(
    "SHA-256",
    bytes as Uint8Array<ArrayBuffer>,
  );
  return Array.from(
    new Uint8Array(hash),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}
function fileName(value: unknown): string {
  const cleaned =
    (typeof value === "string" ? value.split(/[\\/]/).pop() ?? "" : "")
      .replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, 160);
  return cleaned || "statement.csv";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") {
    return response({ error: "Метод не поддерживается." }, 405);
  }
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authorization = req.headers.get("authorization") ?? "";
    if (!url || !anon || !service) {
      throw new HttpError(503, "Импорт временно недоступен.");
    }
    if (!/^Bearer [A-Za-z0-9_.-]+$/.test(authorization)) {
      throw new HttpError(401, "Войдите в аккаунт заново.");
    }
    const userResponse = await fetch(`${url}/auth/v1/user`, {
      headers: { apikey: anon, Authorization: authorization },
    });
    if (!userResponse.ok) throw new HttpError(401, "Войдите в аккаунт заново.");
    const user = await userResponse.json();
    if (typeof user.id !== "string" || !uuid.test(user.id)) {
      throw new HttpError(401, "Войдите в аккаунт заново.");
    }
    const body = await readJson(req);
    if (typeof body.account_id !== "string" || !uuid.test(body.account_id)) {
      throw new HttpError(400, "Выберите счёт.");
    }
    const bytes = decodeFile(body.file_base64);
    const format = detectFormat(bytes);
    if (format === "pdf") {
      throw new HttpError(
        422,
        "PDF распознан; поддержка банковских PDF-выписок появится на следующем этапе.",
      );
    }
    if (format === "xlsx") {
      throw new HttpError(
        422,
        "XLSX/ZIP распознан; банковские XLSX-выписки будут добавлены на следующих этапах.",
      );
    }
    if (format !== "csv") {
      throw new HttpError(
        422,
        "Формат не распознан. Сейчас поддерживается CashRadar CSV с установленными заголовками.",
      );
    }
    const headers = { apikey: service, Authorization: `Bearer ${service}` };
    const accountUrl = new URL(`${url}/rest/v1/accounts`);
    accountUrl.search = new URLSearchParams({
      select: "id,currency,bank_id,is_active",
      id: `eq.${body.account_id}`,
      user_id: `eq.${user.id}`,
      limit: "1",
    }).toString();
    const accountResponse = await fetch(accountUrl, { headers });
    if (!accountResponse.ok) {
      throw new HttpError(503, "Не удалось проверить счёт.");
    }
    const accounts = await accountResponse.json();
    if (
      !Array.isArray(accounts) || accounts.length !== 1 ||
      !accounts[0].is_active
    ) throw new HttpError(400, "Активный счёт не найден.");
    const account = accounts[0];
    const hash = await digest(bytes);
    const existingUrl = new URL(`${url}/rest/v1/import_batches`);
    existingUrl.search = new URLSearchParams({
      select: "id,status",
      user_id: `eq.${user.id}`,
      file_sha256: `eq.${hash}`,
      status: "in.(ready,completed)",
      limit: "1",
    }).toString();
    const existingResponse = await fetch(existingUrl, { headers });
    if (!existingResponse.ok) {
      throw new HttpError(503, "Не удалось проверить повторную загрузку.");
    }
    const existing = await existingResponse.json();
    if (existing.length) {
      return response({
        id: existing[0].id,
        status: existing[0].status,
        duplicate: true,
      });
    }
    const categoriesUrl = new URL(`${url}/rest/v1/categories`);
    categoriesUrl.search = new URLSearchParams({
      select: "id,name,kind",
      user_id: `eq.${user.id}`,
    }).toString();
    const categoryResponse = await fetch(categoriesUrl, { headers });
    if (!categoryResponse.ok) {
      throw new HttpError(503, "Не удалось загрузить категории.");
    }
    const categories: Category[] = await categoryResponse.json();
    const parsed = parseCashRadarCsv(bytes, account.currency, categories);
    const objectPath = `${user.id}/${hash}.csv`;
    const encodedPath = objectPath.split("/").map(encodeURIComponent).join("/");
    const upload = await fetch(
      `${url}/storage/v1/object/statements/${encodedPath}`,
      {
        method: "POST",
        headers: {
          ...headers,
          "Content-Type": "text/csv",
          "x-upsert": "false",
        },
        body: bytes as Uint8Array<ArrayBuffer>,
      },
    );
    if (!upload.ok) {
      if (upload.status !== 409 && upload.status !== 400) {
        throw new HttpError(503, "Не удалось сохранить оригинал файла.");
      }
      // A retry can encounter an object saved before a transient DB failure. Verify it.
      const old = await fetch(
        `${url}/storage/v1/object/authenticated/statements/${encodedPath}`,
        { headers },
      );
      if (!old.ok) {
        throw new HttpError(503, "Не удалось проверить сохранённый файл.");
      }
      const oldBytes = new Uint8Array(await old.arrayBuffer());
      if (oldBytes.length !== bytes.length || await digest(oldBytes) !== hash) {
        throw new HttpError(503, "Не удалось проверить сохранённый файл.");
      }
    }
    const registered = await fetch(
      `${url}/rest/v1/rpc/register_statement_import`,
      {
        method: "POST",
        headers: { ...headers, "Content-Type": "application/json" },
        body: JSON.stringify({
          p_user_id: user.id,
          p_account_id: account.id,
          p_currency: account.currency,
          p_filename: fileName(body.filename),
          p_sha256: hash,
          p_items: parsed.items,
          p_errors: parsed.errors,
          p_error_count: parsed.errorCount,
        }),
      },
    );
    if (!registered.ok) {
      throw new HttpError(
        503,
        "Не удалось подготовить импорт. Проверьте счёт и повторите попытку.",
      );
    }
    return response(await registered.json());
  } catch (error) {
    if (error instanceof HttpError) {
      return response({ error: error.message }, error.status);
    }
    if (error instanceof ImportFormatError) {
      return response({ error: error.message }, 422);
    }
    return response(
      { error: "Не удалось обработать файл. Повторите попытку." },
      500,
    );
  }
});
