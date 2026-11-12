import { Buffer } from "node:buffer";
import office from "npm:officecrypto-tool@0.0.19";
import { parseAcbaXlsx } from "../functions/import-statement/acba.ts";
import { decryptAcba } from "../functions/import-statement/encrypted.ts";
import { ImportFormatError } from "../functions/import-statement/parser.ts";
const fixture = await Deno.readFile(
  new URL("./fixtures/acba_synthetic.xlsx", import.meta.url),
);
const cats = [{ id: "income", name: "Прочие доходы", kind: "income" }, {
  id: "expense",
  name: "Прочие расходы",
  kind: "expense",
}];
function equal(a: unknown, b: unknown) {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw Error(`Expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
  }
}
Deno.test("ACBA parses postings and a separate commission while excluding daily balances", async () => {
  const p = await parseAcbaXlsx(fixture, "AMD", cats);
  equal(p.errorCount, 0);
  equal(p.items.length, 2);
  equal(p.items.map((x) => x.transaction_type), ["income", "expense"]);
  equal(p.items[1].commission_amount, "2.50");
  equal(p.items[1].commission_category_id, "expense");
  equal(p.items[1].raw_description, "Synthetic purchase · Synthetic merchant");
});
Deno.test("ACBA rejects a discrepancy between entries and closing balance", async () => {
  const broken = await Deno.readFile(
    new URL("./fixtures/acba_unbalanced_synthetic.xlsx", import.meta.url),
  );
  const p = await parseAcbaXlsx(broken, "AMD", cats);
  equal(p.errorCount, 1);
  equal(p.errors[0].row, 19);
});
Deno.test("encrypted ACBA file decrypts only with the supplied password", async () => {
  const encrypted = new Uint8Array(
    office.encrypt(Buffer.from(fixture), {
      password: "synthetic-only",
      type: "standard",
    }),
  );
  const plain = await decryptAcba(encrypted, "synthetic-only");
  equal(Array.from(plain), Array.from(fixture));
  const p = await parseAcbaXlsx(plain, "AMD", cats);
  equal(p.errorCount, 0);
  for (const password of ["", "incorrect"]) {
    let rejected = false;
    try {
      await decryptAcba(encrypted, password);
    } catch (e) {
      rejected = e instanceof ImportFormatError;
    }
    equal(rejected, true);
  }
});

Deno.test("pending-block markers prevent confirmation until the format is known", async () => {
  const bytes = await Deno.readFile(
    new URL("./fixtures/acba_pending_synthetic.xlsx", import.meta.url),
  );
  const result = await parseAcbaXlsx(bytes, "AMD", cats);
  equal(result.errorCount, 1);
});
