export type Category = { id: string; name: string; kind: string };
export type ImportItem = {
  row_number: number;
  transaction_date: string;
  transaction_type: string;
  amount: string;
  currency: string;
  account_amount: string;
  category_id: string;
  raw_description: string | null;
  raw_data: Record<string, string>;
  commission_amount?: string;
  commission_category_id?: string;
};
export type ImportError = { row: number; message: string };
export type ParsedImport = {
  items: ImportItem[];
  errors: ImportError[];
  errorCount: number;
};
export class ImportFormatError extends Error {}

const header = [
  "date",
  "type",
  "amount",
  "currency",
  "account_amount",
  "category",
  "description",
];
const currencies = new Set(["AMD", "RUB", "USD", "EUR"]);
const limitRows = 500;

export function detectFormat(
  bytes: Uint8Array,
): "pdf" | "xlsx" | "encrypted_xlsx" | "csv" | "unknown" {
  if (
    bytes.length >= 5 && new TextDecoder().decode(bytes.slice(0, 5)) === "%PDF-"
  ) return "pdf";
  if (
    bytes.length >= 8 &&
    [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1].every((v, i) =>
      bytes[i] === v
    )
  ) return "encrypted_xlsx";
  if (
    bytes.length >= 4 && bytes[0] === 0x50 && bytes[1] === 0x4b &&
    bytes[2] === 3 && bytes[3] === 4
  ) return "xlsx";
  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes)
      .replace(/^\uFEFF/, "");
    const first = text.split(/\r?\n/, 1)[0];
    return first === header.join(",") ? "csv" : "unknown";
  } catch {
    return "unknown";
  }
}

function parseRows(text: string): Array<{ values: string[]; line: number }> {
  if (text.includes("\u0000")) {
    throw new ImportFormatError("CSV содержит недопустимый символ.");
  }
  const rows: Array<{ values: string[]; line: number }> = [];
  let row: string[] = [], field = "", quoted = false, closed = false;
  let line = 1, recordStart = 1;
  function pushField() {
    row.push(field);
    field = "";
    closed = false;
  }
  function pushRow() {
    pushField();
    if (row.some((x) => x.length > 0)) {
      rows.push({ values: row, line: recordStart });
    }
    row = [];
    if (rows.length > limitRows + 1) {
      throw new ImportFormatError("Допускается не более 500 строк операций.");
    }
  }
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        field += c;
        if (c === "\n" || (c === "\r" && text[i + 1] !== "\n")) line++;
      }
    } else if (c === ",") pushField();
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      pushRow();
      line++;
      recordStart = line;
    } else if (c === '"' && field.length === 0 && !closed) quoted = true;
    else {
      if (closed || c === '"' || c === "\u0000") {
        throw new ImportFormatError("Некорректное оформление CSV.");
      }
      field += c;
    }
    if (field.length > 8192 || row.length > header.length) {
      throw new ImportFormatError(
        "CSV содержит слишком длинное поле или лишние столбцы.",
      );
    }
  }
  if (quoted) throw new ImportFormatError("В CSV не закрыты кавычки.");
  if (row.length || field.length || closed) pushRow();
  return rows;
}
function decimal(input: string): string | null {
  const s = input.trim().replace(",", ".");
  if (!/^\d{1,18}(?:\.\d{1,2})?$/.test(s)) return null;
  const [whole, fraction = ""] = s.split(".");
  if (/^0+$/.test(whole) && (!fraction || /^0+$/.test(fraction))) return null;
  return s;
}
function canonicalDecimal(s: string): string {
  const [whole, fraction = ""] = s.split(".");
  return `${whole.replace(/^0+(?=\d)/, "")}.${fraction.padEnd(2, "0")}`;
}
function validDate(s: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s) || s < "1900-01-01" || s > "2100-12-31") {
    return false;
  }
  const [year, month, day] = s.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day;
}

export function parseCashRadarCsv(
  bytes: Uint8Array,
  accountCurrency: string,
  categories: Category[],
): ParsedImport {
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes).replace(
      /^\uFEFF/,
      "",
    );
  } catch {
    throw new ImportFormatError("Файл должен быть в кодировке UTF-8.");
  }
  const rows = parseRows(text);
  if (
    !rows.length || rows[0].values.length !== header.length ||
    rows[0].values.some((v, i) => v !== header[i])
  ) {
    throw new ImportFormatError(
      "Заголовки не соответствуют формату CashRadar CSV.",
    );
  }
  const items: ImportItem[] = [], errors: ImportError[] = [];
  let errorCount = 0;
  function addError(row: number, message: string) {
    errorCount++;
    if (errors.length < 100) errors.push({ row, message });
  }
  for (let i = 1; i < rows.length; i++) {
    const values = rows[i].values, row = rows[i].line;
    if (values.length !== header.length) {
      addError(row, "Неверное количество столбцов.");
      continue;
    }
    const [
      rawDate,
      rawType,
      rawAmount,
      rawCurrency,
      rawAccountAmount,
      rawCategory,
      rawDescription,
    ] = values;
    const date = rawDate.trim(),
      type = rawType.trim().toLowerCase(),
      currency = rawCurrency.trim().toUpperCase();
    const amount = decimal(rawAmount);
    const accountAmount = rawAccountAmount.trim()
      ? decimal(rawAccountAmount)
      : (currency === accountCurrency ? amount : null);
    const matches = categories.filter((c) =>
      c.kind === type &&
      c.name.trim().toLocaleLowerCase("ru") ===
        rawCategory.trim().toLocaleLowerCase("ru")
    );
    let error: string | null = null;
    if (!validDate(date)) {
      error = "Дата должна быть в формате ГГГГ-ММ-ДД и быть действительной.";
    } else if (!["income", "expense"].includes(type)) {
      error = "Тип должен быть income или expense.";
    } else if (!currencies.has(currency)) {
      error = "Валюта должна быть AMD, RUB, USD или EUR.";
    } else if (!amount) {
      error =
        "Сумма должна быть положительной и иметь не более двух знаков после запятой.";
    } else if (!accountAmount) {
      error = "Укажите корректную фактическую сумму по счёту.";
    } else if (
      currency === accountCurrency &&
      canonicalDecimal(amount) !== canonicalDecimal(accountAmount)
    ) error = "Для одинаковых валют суммы должны совпадать.";
    else if (matches.length !== 1) {
      error = matches.length === 0
        ? "Категория этого типа не найдена."
        : "Название категории неоднозначно.";
    } else if (rawDescription.trim().length > 500) {
      error = "Описание длиннее 500 символов.";
    }
    if (error) {
      addError(row, error);
      continue;
    }
    items.push({
      row_number: row,
      transaction_date: date,
      transaction_type: type,
      amount: amount!,
      currency,
      account_amount: accountAmount!,
      category_id: matches[0].id,
      raw_description: rawDescription.trim() || null,
      raw_data: Object.fromEntries(
        header.map((name, idx) => [name, values[idx]]),
      ),
    });
  }
  if (rows.length === 1) addError(1, "В файле нет операций.");
  return { items, errors, errorCount };
}
