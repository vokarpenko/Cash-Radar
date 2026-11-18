import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { parseRateAm } from "../functions/exchange-rates/rateam.ts";
function page(records: string) { return `<script>self.__next_f.push(${JSON.stringify([1, records])})</script>`; }
Deno.test("reads only ACBA non-cash buy quotes, including RUB alias", () => {
  const t = Date.now();
  const html = page(`a:{"acba-bank":"$b","ameriabank":"$z"}\nb:{"lastUpdated":${t},"rates":"$c"}\nc:{"USD":"$d","EUR":"$e","RUR":"$f"}\nd:{"CLEARING":{"buy":"358","sell":"363"},"CASH":{"buy":"999"}}\ne:{"CLEARING":{"buy":"390","sell":"401"}}\nf:{"CLEARING":{"buy":"4.31","sell":"4.5"}}\n`);
  assertEquals(parseRateAm(html), { asOf: new Date(t).toISOString(), rates: { AMD: "1", USD: "358", EUR: "390", RUB: "4.31" } });
});
Deno.test("rejects malformed or incomplete quotes", () => {
  assertThrows(() => parseRateAm(page('a:{"acba-bank":"$b"}\nb:{"lastUpdated":0,"rates":{}}\n')));
  assertThrows(() => parseRateAm("<html>no data</html>"));
});
