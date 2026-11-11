import { XMLParser, XMLValidator } from "npm:fast-xml-parser@5.12.0";
import {
  type Category,
  type ImportError,
  ImportFormatError,
  type ImportItem,
  type ParsedImport,
} from "./parser.ts";

const MAX_EXPANDED = 8 * 1024 * 1024;
const MAX_XML = 4 * 1024 * 1024;
const requiredFiles = new Set([
  "xl/sharedStrings.xml",
  "xl/worksheets/sheet1.xml",
]);
const badFile = () =>
  new ImportFormatError(
    "Не удалось безопасно прочитать XLSX Ameria. Проверьте формат файла.",
  );

// Read the central directory first; only expand known XML entries with a hard streaming limit.
async function readXmlEntries(bytes: Uint8Array): Promise<Map<string, string>> {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let end = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
    if (
      view.getUint32(i, true) === 0x06054b50 &&
      i + 22 + view.getUint16(i + 20, true) === bytes.length
    ) {
      end = i;
      break;
    }
  }
  if (end < 0) throw badFile();
  const count = view.getUint16(end + 10, true),
    start = view.getUint32(end + 16, true);
  if (
    view.getUint16(end + 4, true) || view.getUint16(end + 6, true) ||
    count !== view.getUint16(end + 8, true) || count > 200 ||
    start + view.getUint32(end + 12, true) !== end
  ) throw badFile();
  const files = new Map<string, string>();
  let at = start, expandedTotal = 0;
  for (let i = 0; i < count; i++) {
    if (at + 46 > end || view.getUint32(at, true) !== 0x02014b50) {
      throw badFile();
    }
    const flags = view.getUint16(at + 8, true),
      method = view.getUint16(at + 10, true),
      compressed = view.getUint32(at + 20, true),
      expanded = view.getUint32(at + 24, true);
    const nameLen = view.getUint16(at + 28, true),
      extra = view.getUint16(at + 30, true),
      comment = view.getUint16(at + 32, true),
      offset = view.getUint32(at + 42, true);
    const next = at + 46 + nameLen + extra + comment;
    if (
      next > end || (flags & 1) || ![0, 8].includes(method) ||
      expanded === 0xffffffff || compressed === 0xffffffff ||
      offset === 0xffffffff
    ) throw badFile();
    const name = new TextDecoder().decode(
      bytes.subarray(at + 46, at + 46 + nameLen),
    );
    expandedTotal += expanded;
    if (expandedTotal > MAX_EXPANDED || expanded > MAX_XML) throw badFile();
    if (requiredFiles.has(name)) {
      if (
        files.has(name) || offset + 30 > start ||
        view.getUint32(offset, true) !== 0x04034b50 ||
        view.getUint16(offset + 8, true) !== method
      ) throw badFile();
      const localNameLen = view.getUint16(offset + 26, true),
        localExtra = view.getUint16(offset + 28, true);
      const localName = new TextDecoder().decode(
        bytes.subarray(offset + 30, offset + 30 + localNameLen),
      );
      const from = offset + 30 + localNameLen + localExtra;
      if (localName !== name || from + compressed > start) throw badFile();
      const compressedBytes = bytes.slice(from, from + compressed);
      let data: Uint8Array;
      if (method === 0) data = compressedBytes;
      else {
        const reader = new Blob([compressedBytes as Uint8Array<ArrayBuffer>])
          .stream().pipeThrough(new DecompressionStream("deflate-raw"))
          .getReader();
        const chunks: Uint8Array[] = [];
        let total = 0;
        try {
          while (true) {
            const { value, done } = await reader.read();
            if (done) break;
            total += value.length;
            if (total > expanded || total > MAX_XML) {
              await reader.cancel();
              throw badFile();
            }
            chunks.push(value);
          }
        } catch {
          throw badFile();
        }
        data = new Uint8Array(total);
        let pos = 0;
        for (const chunk of chunks) {
          data.set(chunk, pos);
          pos += chunk.length;
        }
      }
      if (data.length !== expanded) throw badFile();
      let xml: string;
      try {
        xml = new TextDecoder("utf-8", { fatal: true }).decode(data);
      } catch {
        throw badFile();
      }
      if (/<!DOCTYPE|<!ENTITY|<!\[CDATA\[/i.test(xml)) throw badFile();
      let depth = 0;
      for (const tag of xml.matchAll(/<([^!?][^>]*?)>/g)) {
        if (tag[1].startsWith("/")) depth--;
        else if (!tag[1].endsWith("/")) depth++;
        if (depth < 0 || depth > 80) throw badFile();
      }
      if (depth !== 0 || XMLValidator.validate(xml) !== true) throw badFile();
      files.set(name, xml);
    }
    at = next;
  }
  if (at !== end || !files.has("xl/worksheets/sheet1.xml")) throw badFile();
  return files;
}
const array = (v: any): any[] =>
  v === undefined ? [] : Array.isArray(v) ? v : [v];
function textOf(v: any): string {
  if (v === undefined || v === null) return "";
  if (typeof v === "string" || typeof v === "number") return String(v);
  return String(v["#text"] ?? "");
}
function money(value: string, sign: "" | "+" | "-"): string | null {
  const s = value.trim().replace(/[\s\u00a0\u202f]/g, "");
  if (sign && !s.startsWith(sign)) return null;
  const digits = sign ? s.slice(1) : s;
  if (!/^\d{1,18}(?:[.,]\d{1,2})?$/.test(digits)) return null;
  const [whole, fraction = ""] = digits.replace(",", ".").split(".");
  if (/^0+$/.test(whole) && (!fraction || /^0+$/.test(fraction))) return null;
  return `${whole.replace(/^0+(?=\d)/, "")}.${fraction.padEnd(2, "0")}`;
}
function date(value: string): string | null {
  const m = /^(\d{2})\.(\d{2})\.(\d{4})$/.exec(value.trim());
  if (!m) return null;
  const result = `${m[3]}-${m[2]}-${m[1]}`;
  const d = new Date(`${result}T00:00:00Z`);
  return result >= "1900-01-01" && result <= "2100-12-31" &&
      !isNaN(d.valueOf()) && d.toISOString().slice(0, 10) === result
    ? result
    : null;
}
export async function parseAmeriaXlsx(
  bytes: Uint8Array,
  accountCurrency: string,
  categories: Category[],
): Promise<ParsedImport> {
  const files = await readXmlEntries(bytes);
  const parser = new XMLParser({
    ignoreAttributes: false,
    parseTagValue: false,
    trimValues: false,
  });
  let shared: string[], rows: Map<number, Record<string, string>>;
  try {
    const table = files.has("xl/sharedStrings.xml")
      ? parser.parse(files.get("xl/sharedStrings.xml")!).sst
      : {};
    shared = array(table?.si).map((v) =>
      v.t !== undefined
        ? textOf(v.t)
        : array(v.r).map((r) => textOf(r.t)).join("")
    );
    const sheet =
      parser.parse(files.get("xl/worksheets/sheet1.xml")!).worksheet;
    rows = new Map();
    for (const row of array(sheet?.sheetData?.row)) {
      const number = Number(row["@_r"]);
      if (
        !Number.isInteger(number) || number < 1 || number > 1048576 ||
        rows.has(number)
      ) throw badFile();
      const cells: Record<string, string> = {};
      for (const cell of array(row.c)) {
        const match = /^([A-Z]{1,3})(\d+)$/.exec(cell["@_r"] ?? "");
        if (
          !match || Number(match[2]) !== number ||
          Object.hasOwn(cells, match[1]) || cell.f !== undefined
        ) throw badFile();
        let value = textOf(cell.v);
        if (cell["@_t"] === "s") {
          if (!/^\d+$/.test(value) || Number(value) >= shared.length) {
            throw badFile();
          }
          value = shared[Number(value)];
        } else if (cell["@_t"] === "inlineStr") value = textOf(cell.is?.t);
        if (value.length > 8192) throw badFile();
        cells[match[1]] = value;
      }
      rows.set(number, cells);
    }
  } catch (e) {
    if (e instanceof ImportFormatError) throw e;
    throw badFile();
  }
  const hasBank = shared.some((s) => /ameriabank/i.test(s));
  let header = 0;
  for (const [num, cells] of rows) {
    const prior = rows.get(num - 1);
    if (
      cells.A?.trim() === "Date" && cells.B?.trim() === "Amount" &&
      cells.C?.trim() === "Currency" && cells.D?.trim() === "Credit" &&
      cells.F?.trim() === "Debit" &&
      prior?.D?.trim() === "Amount in card currency" &&
      prior?.O?.trim() === "Transaction details"
    ) {
      if (header) throw badFile();
      header = num;
    }
  }
  if (!hasBank || !header) {
    throw new ImportFormatError(
      "Формат XLSX не соответствует поддерживаемой выписке Ameria.",
    );
  }
  let cardCurrency: string | undefined;
  for (const cells of rows.values()) {
    if (cells.O?.trim() === "Currency") {
      cardCurrency = cells.Q?.trim().toUpperCase();
    }
  }
  if (!cardCurrency || cardCurrency !== accountCurrency) {
    throw new ImportFormatError(
      "Валюта карты в выписке не совпадает с валютой выбранного счёта.",
    );
  }
  const items: ImportItem[] = [], errors: ImportError[] = [];
  let errorCount = 0, transactionCount = 0, started = false;
  const addError = (row: number, message: string) => {
    errorCount++;
    if (errors.length < 100) errors.push({ row, message });
  };
  for (const [num, cells] of rows) {
    if (num <= header) continue;
    if (!cells.A?.trim()) {
      if (
        cells.B?.trim() || cells.C?.trim() || cells.D?.trim() || cells.F?.trim()
      ) {
        transactionCount++;
        if (transactionCount > 500) {
          throw new ImportFormatError(
            "Допускается не более 500 строк операций.",
          );
        }
        addError(num, "Не указана дата операции.");
      }
      continue;
    }
    const txDate = date(cells.A);
    if (!txDate) {
      if (
        cells.B?.trim() || cells.C?.trim() || cells.D?.trim() || cells.F?.trim()
      ) {
        transactionCount++;
        if (transactionCount > 500) {
          throw new ImportFormatError(
            "Допускается не более 500 строк операций.",
          );
        }
        addError(num, "Некорректная дата операции.");
        started = true;
        continue;
      }
      if (started) break;
      continue;
    }
    started = true;
    transactionCount++;
    if (transactionCount > 500) {
      throw new ImportFormatError("Допускается не более 500 строк операций.");
    }
    const currency = (cells.C ?? "").trim().toUpperCase(),
      amount = money(cells.B ?? "", "");
    const hasCredit = !!cells.D?.trim(), hasDebit = !!cells.F?.trim();
    // Ameria's release of a card hold has no posting and must not change the ledger.
    if (
      !hasCredit && !hasDebit &&
      /^Ապասառեցում(?=$|[\s(:])/iu.test((cells.O ?? "").trim())
    ) continue;
    const type = hasCredit ? "income" : "expense";
    const accountAmount = hasCredit === hasDebit
      ? null
      : money(hasCredit ? cells.D : cells.F, hasCredit ? "+" : "-");
    const name = type === "income" ? "Прочие доходы" : "Прочие расходы";
    const matches = categories.filter((c) =>
      c.kind === type &&
      c.name.trim().toLocaleLowerCase("ru") === name.toLocaleLowerCase("ru")
    );
    let error = "";
    if (!amount || !["AMD", "RUB", "USD", "EUR"].includes(currency)) {
      error = "Некорректная сумма или валюта операции.";
    } else if (!accountAmount) {
      error = "Не удалось определить приход или расход и сумму в валюте карты.";
    } else if (currency === accountCurrency && amount !== accountAmount) {
      error = "Суммы в одинаковой валюте не совпадают.";
    } else if (matches.length !== 1) {
      error = `Нужна одна категория «${name}» соответствующего типа.`;
    } else if ((cells.O ?? "").trim().length > 500) {
      error = "Описание длиннее 500 символов.";
    }
    if (error) {
      addError(num, error);
      continue;
    }
    items.push({
      row_number: num,
      transaction_date: txDate,
      transaction_type: type,
      amount: amount!,
      currency,
      account_amount: accountAmount!,
      category_id: matches[0].id,
      raw_description: (cells.O ?? "").trim() || null,
      raw_data: {
        ...cells,
        ...(rows.get(num + 1)?.A?.trim() ? {} : {
          continuation_balance: rows.get(num + 1)?.L ?? "",
          continuation_details: rows.get(num + 1)?.O ?? "",
        }),
      },
    });
  }
  if (!transactionCount) addError(header, "В выписке нет операций.");
  return { items, errors, errorCount };
}
