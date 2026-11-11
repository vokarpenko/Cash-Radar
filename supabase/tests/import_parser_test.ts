import {
  detectFormat,
  ImportFormatError,
  parseCashRadarCsv,
} from "../functions/import-statement/parser.ts";
const encode = (text: string) => new TextEncoder().encode(text);
const head = "date,type,amount,currency,account_amount,category,description\n";
const cats = [{ id: "1", name: "Продукты", kind: "expense" }, {
  id: "2",
  name: "Зарплата",
  kind: "income",
}];
function assert(value: unknown, msg = "assertion failed"): asserts value {
  if (!value) throw Error(msg);
}
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
Deno.test("recognises signatures and only the explicit CSV schema", () => {
  equal(detectFormat(encode("%PDF-1.7")), "pdf");
  equal(detectFormat(new Uint8Array([0x50, 0x4b, 3, 4])), "xlsx");
  equal(detectFormat(encode("\uFEFF" + head)), "csv");
  equal(detectFormat(encode("wrong,file\n1,2")), "unknown");
  equal(detectFormat(new Uint8Array([255, 254])), "unknown");
});
Deno.test("parses quotes, comma decimal and two-currency rows without rounding", () => {
  const csv = head +
    '2026-11-11,expense,"12,34",EUR,5000.01,Продукты,"Кофе, и ""торт"""\n2026-11-12,income,10.00,AMD,,Зарплата,Доход\n';
  const r = parseCashRadarCsv(encode(csv), "AMD", cats);
  equal(r.errorCount, 0);
  equal(r.items.length, 2);
  equal(r.items[0].amount, "12.34");
  equal(r.items[0].account_amount, "5000.01");
  equal(r.items[0].raw_description, 'Кофе, и "торт"');
  equal(r.items[1].account_amount, "10.00");
  equal(r.items[0].raw_data.amount, "12,34");
});
Deno.test("reports invalid dates, money, categories and account amounts without raw values", () => {
  const csv = head + [
    "2026-02-30,expense,1,AMD,,Продукты,x",
    "2026-01-01,expense,0.001,AMD,,Продукты,x",
    "2026-01-01,expense,1,EUR,,Продукты,x",
    "2026-01-01,expense,1,AMD,2,Продукты,x",
    "2026-01-01,expense,1,AMD,,Неизвестная,x",
  ].join("\n");
  const r = parseCashRadarCsv(encode(csv), "AMD", cats);
  equal(r.items.length, 0);
  equal(r.errorCount, 5);
  equal(r.errors.map((e) => e.row), [2, 3, 4, 5, 6]);
  assert(!JSON.stringify(r.errors).includes("Неизвестная"));
});
Deno.test("refuses malformed CSV and oversized row counts", () => {
  for (
    const csv of [
      head + '2026-01-01,expense,1,AMD,,Продукты,"unfinished',
      head + Array(501).fill("2026-01-01,expense,1,AMD,,Продукты,x").join("\n"),
    ]
  ) {
    let threw = false;
    try {
      parseCashRadarCsv(encode(csv), "AMD", cats);
    } catch (e) {
      threw = e instanceof ImportFormatError;
    }
    assert(threw);
  }
});
Deno.test("duplicate or foreign categories do not resolve", () => {
  const row = head + "2026-01-01,expense,1,AMD,,Продукты,x";
  equal(parseCashRadarCsv(encode(row), "AMD", []).errorCount, 1);
  equal(
    parseCashRadarCsv(encode(row), "AMD", [...cats, { ...cats[0], id: "3" }])
      .errorCount,
    1,
  );
});
Deno.test("reports physical lines after blanks and multiline quoted fields", () => {
  const csv = head +
    '\n2026-01-01,expense,1,AMD,,Продукты,"первая\nвторая"\n2026-02-30,expense,1,AMD,,Продукты,x\n';
  const r = parseCashRadarCsv(encode(csv), "AMD", cats);
  equal(r.items[0].row_number, 3);
  equal(r.errors[0].row, 5);
  let threw = false;
  try {
    parseCashRadarCsv(
      encode(head + '2026-01-01,expense,1,AMD,,Продукты,"a\u0000b"'),
      "AMD",
      cats,
    );
  } catch (e) {
    threw = e instanceof ImportFormatError;
  }
  assert(threw);
});
