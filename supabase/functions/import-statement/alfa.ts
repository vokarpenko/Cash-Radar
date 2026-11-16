import { readXlsx } from "./xlsx.ts";
import {
  type Category,
  type ImportError,
  ImportFormatError,
  type ImportItem,
  type ParsedImport,
} from "./parser.ts";

// This account statement provides signed account-currency amounts only.
// No purchase currency, exchange rate, or original card amount is inferred.
function currency(value: string): string {
  const code = value.trim().toUpperCase();
  return code === "RUR" ? "RUB" : code;
}
function date(value: string): string | null {
  const m = /^(\d{2})\.(\d{2})\.(\d{4})$/.exec(value.trim());
  if (!m) return null;
  const iso = `${m[3]}-${m[2]}-${m[1]}`;
  const parsed = new Date(`${iso}T00:00:00Z`);
  return iso >= "1900-01-01" && iso <= "2100-12-31" &&
      !Number.isNaN(parsed.valueOf()) &&
      parsed.toISOString().slice(0, 10) === iso
    ? iso
    : null;
}
function cents(value: string, expectedCurrency?: string): bigint | null {
  let input = value.trim().replace(/−/g, "-");
  const suffix = /\s*([A-Za-z]{3})$/.exec(input);
  if (suffix) {
    if (!expectedCurrency || currency(suffix[1]) !== expectedCurrency) {
      return null;
    }
    input = input.slice(0, suffix.index).trim();
  }
  const match =
    /^([+-]?)((?:\d{1,3}(?:[\s\u00a0\u202f]\d{3})+)|\d{1,18})(?:[,.](\d{1,2}))?$/
      .exec(input);
  if (!match) return null;
  const digits = match[2].replace(/[\s\u00a0\u202f]/g, "");
  if (digits.length > 18) return null;
  const amount = BigInt(digits) * 100n +
    BigInt((match[3] ?? "").padEnd(2, "0"));
  if (amount >= 100000000000000000000n) return null;
  return match[1] === "-" ? -amount : amount;
}
function decimal(n: bigint): string {
  const v = n < 0n ? -n : n;
  return `${v / 100n}.${String(v % 100n).padStart(2, "0")}`;
}
function normalized(value: string): string {
  return value.trim().replace(/\s+/gu, " ").toLocaleLowerCase("ru");
}

export async function parseAlfaXlsx(
  bytes: Uint8Array,
  accountCurrency: string,
  categories: Category[],
): Promise<ParsedImport> {
  const { shared, rows } = await readXlsx(bytes);
  if (
    !shared.some((s) => /альфа[\s-]*банк/iu.test(s)) ||
    ![...rows.values()].some((r) =>
      normalized(r.A ?? "") === "выписка по счету"
    )
  ) {
    throw new ImportFormatError(
      "Формат XLSX не соответствует поддерживаемой выписке Альфа-Банка.",
    );
  }
  let header = 0;
  for (const [num, row] of rows) {
    if (
      normalized(row.A ?? "") === "дата операции" &&
      normalized(row.B ?? "") === "дата проводки" &&
      normalized(row.D ?? "") === "код" &&
      normalized(row.E ?? "") === "категория" &&
      normalized(row.L ?? "") === "описание" &&
      normalized(row.M ?? "") === "сумма в валюте счета" &&
      normalized(row.O ?? "") === "статус"
    ) {
      if (header) {
        throw new ImportFormatError(
          "В выписке найдено несколько таблиц операций.",
        );
      }
      header = num;
    }
  }
  if (!header) {
    throw new ImportFormatError("Не найдены заголовки операций Альфа-Банка.");
  }
  const meta = [...rows.values()];
  const currencyRows = meta.filter((r) =>
    normalized(r.A ?? "") === "валюта счета"
  );
  if (
    currencyRows.length !== 1 ||
    currency(currencyRows[0].C ?? "") !== accountCurrency ||
    !["RUB", "AMD", "USD", "EUR"].includes(accountCurrency)
  ) {
    throw new ImportFormatError(
      "Валюта выписки не совпадает с валютой выбранного счёта.",
    );
  }
  function summary(label: string): bigint | null {
    const found = meta.filter((r) => normalized(r.K ?? "") === label);
    return found.length === 1 ? cents(found[0].N ?? "", accountCurrency) : null;
  }
  const incoming = summary("поступления"),
    outgoing = summary("расходы"),
    pending = summary("неподтвержденные операции");
  if (
    incoming === null || outgoing === null || pending === null ||
    incoming < 0n || outgoing < 0n
  ) {
    throw new ImportFormatError(
      "Не удалось проверить итоги выписки Альфа-Банка.",
    );
  }
  const items: ImportItem[] = [], errors: ImportError[] = [];
  let errorCount = 0, rowCount = 0, positive = 0n, negative = 0n, ended = false;
  const addError = (row: number, message: string) => {
    errorCount++;
    if (errors.length < 100) errors.push({ row, message });
  };
  if (pending !== 0n) {
    addError(
      header,
      "В выписке есть неподтверждённые операции; импорт заблокирован до их проверки.",
    );
  }
  for (const [num, row] of rows) {
    if (num <= header) continue;
    const hasData = ["A", "B", "D", "E", "L", "M", "O"].some((k) =>
      (row[k] ?? "").trim()
    );
    if (!hasData) {
      if (rowCount) ended = true;
      continue;
    }
    if (
      rowCount &&
      /^\(подпись сотрудника АО «АЛЬФА-БАНК»\)$/iu.test((row.A ?? "").trim()) &&
      !(row.B ?? "").trim() && !(row.D ?? "").trim() && !(row.M ?? "").trim()
    ) {
      ended = true;
      continue;
    }
    // Footer is distinct from operation rows; never silently skip a later dated row.
    if (ended) {
      if (
        date(row.A ?? "") || (row.B ?? "").trim() || (row.D ?? "").trim() ||
        (row.M ?? "").trim()
      ) {
        addError(num, "Обнаружены данные операции после конца таблицы.");
      }
      continue;
    }
    rowCount++;
    if (rowCount > 500) {
      throw new ImportFormatError("Допускается не более 500 строк операций.");
    }
    const operationDate = date(row.A ?? ""), postingDate = date(row.B ?? "");
    const code = (row.D ?? "").trim(),
      description = (row.L ?? "").trim(),
      status = normalized(row.O ?? "");
    const value = cents(row.M ?? "");
    const type = value !== null && value > 0n ? "income" : "expense";
    const categoryName = type === "income" ? "прочие доходы" : "прочие расходы";
    const found = categories.filter((c) =>
      c.kind === type && normalized(c.name) === categoryName
    );
    const mccMatches = [
      ...description.matchAll(/(?:\bMCC|МСС)\s*[:№]?\s*(\d{4})(?!\d)/giu),
    ].map((m) => m[1]);
    let error = "";
    if (!operationDate || !postingDate) {
      error = "Не удалось определить даты операции и проводки.";
    } else if (!code || code.length > 160) {
      error = "Отсутствует или некорректен код операции.";
    } else if (!description || description.length > 500) {
      error = "Отсутствует или слишком длинное описание операции.";
    } else if (value === null || value === 0n) {
      error = "Некорректная сумма операции.";
    } else if (status && status !== "выполнен") {
      error = "Неподдерживаемый статус операции.";
    } else if (found.length !== 1) {
      error = `Нужна одна категория «${
        type === "income" ? "Прочие доходы" : "Прочие расходы"
      }».`;
    } else if (
      (/\bMCC\b|МСС/iu.test(description) && mccMatches.length === 0) ||
      new Set(mccMatches).size > 1
    ) error = "Не удалось однозначно распознать MCC.";
    if (error) {
      addError(num, error);
      continue;
    }
    if (value! > 0n) positive += value!;
    else negative -= value!;
    const amount = decimal(value!);
    items.push({
      row_number: num,
      transaction_date: operationDate!,
      transaction_type: type,
      amount,
      currency: accountCurrency,
      account_amount: amount,
      category_id: found[0].id,
      raw_description: description,
      raw_data: {
        ...row,
        posting_date: postingDate!,
        bank_operation_code: code,
        original_currency_not_provided: "true",
        ...(mccMatches.length ? { mcc: mccMatches[0] } : {}),
      },
    });
  }
  if (!rowCount) addError(header, "В выписке нет операций.");
  if (positive !== incoming || negative !== outgoing) {
    addError(header, "Суммы операций не совпадают с итогами выписки.");
  }
  return { items, errors, errorCount };
}
