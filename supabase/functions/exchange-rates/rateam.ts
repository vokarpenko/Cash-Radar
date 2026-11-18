/** Extract only ACBA's non-cash buy quotes from Rate.am's public page. */
export function parseRateAm(html: string): { asOf: string; rates: Record<string, string> } {
  const chunks: string[] = [];
  const re = /self\.__next_f\.push\((\[1,"(?:\\.|[^"\\])*"])\)/g;
  for (const match of html.matchAll(re)) {
    const value = JSON.parse(match[1]);
    if (typeof value[1] === "string") chunks.push(value[1]);
  }
  const records = new Map<string, unknown>();
  for (const line of chunks.join("").split("\n")) {
    const m = /^([0-9a-f]+):(\{.*\})$/.exec(line);
    if (!m) continue;
    try { records.set(m[1], JSON.parse(m[2])); } catch { /* Ignore unrelated RSC records. */ }
  }
  function object(value: unknown): Record<string, unknown> {
    if (typeof value === "string" && /^\$[0-9a-f]+$/.test(value)) value = records.get(value.slice(1));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid Rate.am data");
    return value as Record<string, unknown>;
  }
  const bankMap = [...records.values()].find((x) => x && typeof x === "object" && !Array.isArray(x) && "acba-bank" in x);
  const bank = object(object(bankMap)["acba-bank"]);
  const rates = object(bank.rates);
  const updated = bank.lastUpdated;
  if (typeof updated !== "number" || !Number.isFinite(updated) || updated < 946684800000 || updated > Date.now() + 86400000) throw new Error("Invalid quote date");
  const result: Record<string, string> = { AMD: "1" };
  for (const [local, code] of [["USD", "USD"], ["EUR", "EUR"], ["RUB", "RUR"]]) {
    const quote = object(object(rates[code]).CLEARING).buy;
    if (typeof quote !== "string" || !/^\d{1,8}(?:\.\d{1,8})?$/.test(quote) || Number(quote) <= 0) throw new Error("Missing quote");
    result[local] = quote;
  }
  return { asOf: new Date(updated).toISOString(), rates: result };
}
