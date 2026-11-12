import { readXlsx } from "./xlsx.ts";
import {
  type Category,
  type ImportError,
  ImportFormatError,
  type ImportItem,
  type ParsedImport,
} from "./parser.ts";

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
  const { shared, rows } = await readXlsx(bytes);
  const badFile = () =>
    new ImportFormatError("Не удалось прочитать XLSX Ameria.");
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
