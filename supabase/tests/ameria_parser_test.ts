import { parseAmeriaXlsx } from "../functions/import-statement/ameria.ts";
import { ImportFormatError } from "../functions/import-statement/parser.ts";
const fixture = await Deno.readFile(
  new URL("./fixtures/ameria_synthetic.xlsx", import.meta.url),
);
const categories = [{ id: "1", name: "Прочие доходы", kind: "income" }, {
  id: "2",
  name: "Прочие расходы",
  kind: "expense",
}];
function equal(a: unknown, b: unknown) {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw Error(`Expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
  }
}
Deno.test("Ameria XLSX parses transactions and preserves both currencies, direction and closing-balance continuation", async () => {
  const result = await parseAmeriaXlsx(fixture, "AMD", categories);
  equal(result.errorCount, 0);
  equal(result.items.length, 3);
  equal(result.items.map((x) => x.row_number), [21, 22, 24]);
  equal(result.items[0].transaction_type, "income");
  equal(result.items[0].amount, "1000.00");
  equal(result.items[1].transaction_type, "expense");
  equal(result.items[1].amount, "12.34");
  equal(result.items[1].currency, "USD");
  equal(result.items[1].account_amount, "4800.00");
  equal(result.items[1].raw_data.continuation_balance, "10 000,00");
  equal(result.items[1].raw_description, "Synthetic merchant");
});
Deno.test("wrong account currency, damaged archive and missing categories are rejected", async () => {
  for (
    const [data, currency] of [[fixture, "USD"], [
      fixture.subarray(0, 80),
      "AMD",
    ]] as const
  ) {
    let rejected = false;
    try {
      await parseAmeriaXlsx(data, currency, categories);
    } catch (e) {
      rejected = e instanceof ImportFormatError;
    }
    equal(rejected, true);
  }
  const result = await parseAmeriaXlsx(fixture, "AMD", []);
  equal(result.errorCount, 3);
  equal(result.items.length, 0);
});

Deno.test("unknown unposted rows and rows without dates are reported", async () => {
  const bytes = await Deno.readFile(
    new URL("./fixtures/ameria_errors_synthetic.xlsx", import.meta.url),
  );
  const result = await parseAmeriaXlsx(bytes, "AMD", categories);
  equal(result.items.length, 3);
  equal(result.errors.map((e) => e.row), [26, 27]);
});
