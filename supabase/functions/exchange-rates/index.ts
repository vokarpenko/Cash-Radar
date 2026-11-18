import { parseRateAm } from "./rateam.ts";
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
  "Content-Type": "application/json; charset=utf-8",
};
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL"), anon = Deno.env.get("SUPABASE_ANON_KEY");
  const auth = req.headers.get("authorization") ?? "";
  if (!url || !anon || !/^Bearer [A-Za-z0-9_.-]+$/.test(auth)) return reply({ error: "Unauthorized" }, 401);
  try {
    const user = await fetch(`${url}/auth/v1/user`, { headers: { apikey: anon, Authorization: auth }, signal: AbortSignal.timeout(10000) });
    if (!user.ok) return reply({ error: "Unauthorized" }, 401);
    // No user data or operation details are sent to Rate.am.
    const response = await fetch("https://www.rate.am/ru/armenian-dram-exchange-rates/banks", { signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error("Rate source unavailable");
    const length = Number(response.headers.get("content-length") ?? 0);
    if (length > 4000000) throw new Error("Rate source response too large");
    const html = await response.text();
    if (html.length > 4000000) throw new Error("Rate source response too large");
    return reply({ source: "rate.am / ACBA", ...parseRateAm(html) });
  } catch {
    return reply({ error: "Не удалось загрузить курсы ACBA с Rate.am." }, 503);
  }
});
