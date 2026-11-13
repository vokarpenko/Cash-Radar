import {
  type Group,
  isEligiblePublicName,
  preparePrompt,
  queryGemini,
  validateResults,
} from "../functions/categorize-merchant/core.ts";
const assert = (v: unknown, message = "assertion failed") => {
  if (!v) throw Error(message);
};
const fail = (f: () => unknown) => {
  try {
    f();
  } catch {
    return;
  }
  throw Error("invalid input accepted");
};
const groups: Group[] = [{
  groupId: "private-group-id",
  merchant: "Imaginary Grocer",
  kind: "expense",
}];
const good = [{
  id: "1",
  category: "groceries",
  confidence: 0.95,
  unambiguous: true,
  reason: "clear",
}];
Deno.test("only reviewed names and no local IDs in prompt", () => {
  const p = preparePrompt(groups).prompt;
  assert(p.includes("Imaginary Grocer"));
  assert(!p.includes("private-group-id"));
  for (
    const s of [
      "name@example.com",
      "visa 1234",
      "123456789",
      "https://example.com",
      "example.com",
      "A\nB",
    ]
  ) assert(!isEligiblePublicName(s), s);
  fail(() => preparePrompt([...groups, ...groups]));
});
Deno.test("strict results reject invalid, unrelated or contradictory output", () => {
  assert(validateResults(good, groups)[0].groupId === "private-group-id");
  for (
    const value of [
      [],
      [{ ...good[0], id: "2" }],
      [{ ...good[0], category: "nonsense" }],
      [{ ...good[0], category: "salary" }],
      [{ ...good[0], confidence: 3 }],
      [{ ...good[0], extra: "data" }],
      [{ ...good[0], reason: "ambiguous" }],
    ]
  ) fail(() => validateResults(value, groups));
});
Deno.test("Gemini receives only minimal data and validated output is returned", async () => {
  const fake = (async (_url: string | URL | Request, options?: RequestInit) => {
    const body = JSON.parse(options!.body as string);
    assert(!JSON.stringify(body).includes("private-group-id"));
    assert(JSON.stringify(body).includes("Imaginary Grocer"));
    return new Response(
      JSON.stringify({
        candidates: [{
          finishReason: "STOP",
          content: { parts: [{ text: JSON.stringify(good) }] },
        }],
      }),
      { status: 200 },
    );
  }) as typeof fetch;
  const result = await queryGemini("local-test-secret", groups, fake);
  assert(
    result.model === "gemini-4-hydrogen" && result.suggestions.length === 1 &&
      result.suggestions[0].category === "groceries",
  );
});
Deno.test("Gemini failure is safe and does not leak response", async () => {
  const fake =
    (async () =>
      new Response("private response", { status: 429 })) as typeof fetch;
  try {
    await queryGemini("local-test-secret", groups, fake);
    throw Error("should fail");
  } catch (e) {
    assert(
      e instanceof Error && e.message.includes("Лимит") &&
        !e.message.includes("private"),
    );
  }
});

Deno.test("429 on Hydrogen falls back once to Flash and records the actual model", async () => {
  const urls: string[] = [];
  const fake = (async (url: string | URL | Request) => {
    urls.push(String(url));
    if (urls.length === 1) return new Response("limit", { status: 429 });
    return new Response(
      JSON.stringify({
        candidates: [{
          finishReason: "STOP",
          content: { parts: [{ text: JSON.stringify(good) }] },
        }],
      }),
      { status: 200 },
    );
  }) as typeof fetch;
  const result = await queryGemini("local-test-secret", groups, fake);
  assert(
    urls.length === 2 && urls[0].includes("gemini-4-hydrogen") &&
      urls[1].includes("gemini-3.8-flash"),
  );
  assert(
    result.model === "gemini-3.8-flash" &&
      result.suggestions[0].category === "groceries",
  );
});
Deno.test("other errors do not cause a fallback request", async () => {
  let calls = 0;
  const fake = (async () => {
    calls++;
    return new Response("failure", { status: 503 });
  }) as typeof fetch;
  try {
    await queryGemini("local-test-secret", groups, fake);
    throw Error("should fail");
  } catch (e) {
    assert(e instanceof Error && e.message.includes("отклонил"));
  }
  assert(calls === 1);
});
Deno.test("limit on both models stops after two calls", async () => {
  let calls = 0;
  const fake = (async () => {
    calls++;
    return new Response("limit", { status: 429 });
  }) as typeof fetch;
  try {
    await queryGemini("local-test-secret", groups, fake);
    throw Error("should fail");
  } catch (e) {
    assert(e instanceof Error && e.message.includes("обеих"));
  }
  assert(calls === 2);
});
