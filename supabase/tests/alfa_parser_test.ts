import { parseAlfaXlsx } from "../functions/import-statement/alfa.ts";
import { ImportFormatError } from "../functions/import-statement/parser.ts";
const cats = [{ id: "income", name: "Прочие доходы", kind: "income" }, {
  id: "expense",
  name: "Прочие расходы",
  kind: "expense",
}];
const fixture = (name: string) =>
  Deno.readFile(new URL(`./fixtures/${name}`, import.meta.url));
function assert(value: unknown, message: string) {
  if (!value) throw Error(message);
}
Deno.test("Alfa parses signed account amounts, posting date, bank code and MCC", async () => {
  const p = await parseAlfaXlsx(
    await fixture("alfa_synthetic.xlsx"),
    "RUB",
    cats,
  );
  assert(p.errorCount === 0 && p.items.length === 4, "wrong rows or errors");
  const x = p.items[0];
  assert(
    x.transaction_type === "expense" && x.amount === "200.00" &&
      x.currency === "RUB" && x.account_amount === "200.00",
    "incorrect account amount",
  );
  assert(
    x.transaction_date === "2026-11-01" &&
      x.raw_data.posting_date === "2026-11-02",
    "posting date not preserved",
  );
  assert(
    x.raw_data.mcc === "5411" &&
      x.raw_data.bank_operation_code === "SYNTHETIC-A",
    "MCC or bank code not preserved",
  );
  assert(
    x.raw_data.original_currency_not_provided === "true",
    "missing amount provenance",
  );
  assert(
    p.items[1].transaction_type === "income" && p.items[1].amount === "1000.00",
    "incoming amount wrong",
  );
});
Deno.test("Alfa blocks pending, mismatched totals and malformed MCC", async () => {
  for (
    const name of [
      "alfa_pending_synthetic.xlsx",
      "alfa_unbalanced_synthetic.xlsx",
      "alfa_bad_mcc_synthetic.xlsx",
    ]
  ) {
    const p = await parseAlfaXlsx(await fixture(name), "RUB", cats);
    assert(p.errorCount > 0, `${name} must not be confirmed`);
  }
});
Deno.test("Alfa rejects wrong currency, other bank and missing categories", async () => {
  for (
    const [name, curr] of [["alfa_synthetic.xlsx", "USD"], [
      "ameria_synthetic.xlsx",
      "AMD",
    ]]
  ) {
    let rejected = false;
    try {
      await parseAlfaXlsx(await fixture(name), curr, cats);
    } catch (e) {
      if (e instanceof ImportFormatError) rejected = true;
      else throw e;
    }
    assert(rejected, `${name} accepted incorrectly`);
  }
  const p = await parseAlfaXlsx(
    await fixture("alfa_synthetic.xlsx"),
    "RUB",
    [],
  );
  assert(p.errorCount > 0, "missing default categories accepted");
});
