import { readXlsx } from "./xlsx.ts";
import {
  type Category,
  type ImportError,
  ImportFormatError,
  type ImportItem,
  type ParsedImport,
} from "./parser.ts";

function amount(
  raw: string,
  sign: "" | "+" | "-",
  allowZero = false,
): string | null {
  let s = raw.trim().replace(/[\u00a0\u202f\s]/g, "");
  if (sign && !s.startsWith(sign)) return null;
  if (sign) s = s.slice(1);
  if (!/^(?:\d{1,3}(?:,\d{3})+|\d{1,18})(?:\.\d{1,2})?$/.test(s)) return null;
  const [integer, fraction = ""] = s.replaceAll(",", "").split(".");
  if (integer.length > 18) return null;
  if (
    !allowZero && /^0+$/.test(integer) && (!fraction || /^0+$/.test(fraction))
  ) return null;
  return `${integer.replace(/^0+(?=\d)/, "")}.${fraction.padEnd(2, "0")}`;
}
function day(raw: string): string | null {
  const m = /^(\d{2})\.(\d{2})\.(\d{4})$/.exec(raw.trim());
  if (!m) return null;
  const iso = `${m[3]}-${m[2]}-${m[1]}`, date = new Date(`${iso}T00:00:00Z`);
  return iso >= "1900-01-01" && iso <= "2100-12-31" &&
      !Number.isNaN(date.valueOf()) && date.toISOString().slice(0, 10) === iso
    ? iso
    : null;
}
const cents = (value: string) => BigInt(value.replace(".", ""));
function balance(raw: string): string | null {
  const s = raw.trim();
  const negative = s.startsWith("-");
  const parsed = amount(negative ? s.slice(1) : s, "", true);
  return parsed === null ? null : negative ? `-${parsed}` : parsed;
}

export async function parseAcbaXlsx(
  bytes: Uint8Array,
  accountCurrency: string,
  categories: Category[],
): Promise<ParsedImport> {
  const { shared, rows } = await readXlsx(bytes);
  const acba = shared.some((s) => /acba|ակբա/iu.test(s));
  let header = 0;
  for (const [num, cell] of rows) {
    const prior = rows.get(num - 1);
    if (
      cell.C?.trim() === "Գործարքի ամսաթիվ" &&
      cell.F?.trim() === "Գործարքի գումարը" && cell.G?.trim() === "Արժույթ" &&
      cell.I?.trim() === "Մուտք" && cell.K?.trim() === "Ելք" &&
      prior?.X?.trim() === "Գործարքի նկարագրություն" &&
      prior?.AI?.trim() === "Գործարքի միջնորդավճար"
    ) {
      if (header) {
        throw new ImportFormatError(
          "В выписке найдено несколько таблиц операций.",
        );
      }
      header = num;
    }
  }
  if (!acba || !header) {
    throw new ImportFormatError(
      "Формат XLSX не соответствует поддерживаемой выписке ACBA.",
    );
  }
  let summary: Record<string, string> | undefined,
    summaryLine = 0,
    accountCode: string | undefined;
  for (const [num, cell] of rows) {
    if (
      /ԿԱՏԱՐՎԱԾ ԳՈՐԾԱՐՔՆԵՐԻ ՎԵՐԱԲԵՐՅԱԼ ԱՄՓՈՓ ՏԵՂԵԿԱՏՎՈՒԹՅՈՒՆ/u.test(
        cell.D ?? "",
      )
    ) {
      if (summary) {
        throw new ImportFormatError("Неоднозначный итог выписки ACBA.");
      }
      const match = /\(([A-Z]{3})\s*\)/.exec(cell.D ?? "");
      accountCode = match?.[1];
      summary = rows.get(num + 2);
      summaryLine = num + 2;
    }
  }
  if (accountCode !== accountCurrency) {
    throw new ImportFormatError(
      "Валюта карты в выписке не совпадает с валютой выбранного счёта.",
    );
  }
  if (!summary) {
    throw new ImportFormatError("Не найдены контрольные остатки ACBA.");
  }
  const starting = balance(summary.D ?? ""),
    ending = balance(summary.AJ ?? "");
  if (starting === null || ending === null) {
    throw new ImportFormatError(
      "Не удалось прочитать контрольные остатки ACBA.",
    );
  }
  const items: ImportItem[] = [], errors: ImportError[] = [];
  let errorCount = 0, count = 0, started = false, delta = 0n;
  const addError = (row: number, message: string) => {
    errorCount++;
    if (errors.length < 100) errors.push({ row, message });
  };
  const fallbackExpense = categories.filter((c) =>
    c.kind === "expense" &&
    c.name.trim().toLocaleLowerCase("ru") === "прочие расходы"
  );
  for (const [num, cell] of rows) {
    if (num <= header) continue;
    // Closing balance rows have no transaction date/amount and must not change the ledger.
    if (
      !cell.C?.trim() && !cell.F?.trim() && !cell.G?.trim() &&
      !cell.I?.trim() && !cell.K?.trim()
    ) {
      if (cell.V?.trim()) continue;
      if (started) break;
      continue;
    }
    count++;
    started = true;
    if (count > 500) {
      throw new ImportFormatError("Допускается не более 500 строк операций.");
    }
    const transactionDate = day(cell.C ?? "");
    const credit = !!cell.I?.trim(), debit = !!cell.K?.trim();
    const type = credit ? "income" : "expense";
    const accountAmount = credit === debit
      ? null
      : amount(credit ? cell.I : cell.K, credit ? "+" : "-");
    const originalGiven = !!cell.F?.trim() || !!cell.G?.trim();
    const currency = originalGiven
      ? (cell.G ?? "").trim().toUpperCase()
      : accountCurrency;
    const originalAmount = originalGiven
      ? amount(cell.F ?? "", "")
      : accountAmount;
    const feeRaw = (cell.AI ?? "").trim();
    const fee = !feeRaw || feeRaw === "կիրառելի չէ"
      ? null
      : amount(feeRaw, "-", true);
    const categoryName = type === "income" ? "Прочие доходы" : "Прочие расходы";
    const matches = categories.filter((c) =>
      c.kind === type &&
      c.name.trim().toLocaleLowerCase("ru") ===
        categoryName.toLocaleLowerCase("ru")
    );
    const description = [cell.X?.trim(), cell.AD?.trim()].filter(Boolean).join(
      " · ",
    );
    let error = "";
    if (!transactionDate) error = "Не удалось определить дату операции.";
    else if (!accountAmount) {
      error = "Не удалось определить приход или расход по карте.";
    } else if (
      !originalAmount || !["AMD", "RUB", "USD", "EUR"].includes(currency)
    ) error = "Некорректная сумма или валюта операции.";
    else if (currency === accountCurrency && originalAmount !== accountAmount) {
      error = "Суммы в одинаковой валюте не совпадают.";
    } else if (feeRaw && feeRaw !== "կիրառելի չէ" && fee === null) {
      error = "Не удалось определить комиссию.";
    } else if (fee && fee !== "0.00" && fallbackExpense.length !== 1) {
      error = "Для комиссии требуется категория «Прочие расходы».";
    } else if (matches.length !== 1) {
      error = `Нужна одна категория «${categoryName}» соответствующего типа.`;
    } else if (description.length > 500) {
      error = "Описание длиннее 500 символов.";
    }
    if (error) {
      addError(num, error);
      continue;
    }
    const commission = fee && fee !== "0.00" ? fee : undefined;
    delta += (credit ? 1n : -1n) * cents(accountAmount!);
    if (commission) delta -= cents(commission);
    items.push({
      row_number: num,
      transaction_date: transactionDate!,
      transaction_type: type,
      amount: originalAmount!,
      currency,
      account_amount: accountAmount!,
      category_id: matches[0].id,
      raw_description: description || null,
      raw_data: { ...cell },
      ...(commission
        ? {
          commission_amount: commission,
          commission_category_id: fallbackExpense[0].id,
        }
        : {}),
    });
  }
  if (!count) addError(header, "В выписке нет операций.");
  if (!errorCount && cents(starting) + delta !== cents(ending)) {
    addError(
      summaryLine,
      "Сумма операций и комиссий не совпадает с итоговым остатком выписки.",
    );
  }
  // Until a real example establishes the separate pending-block format, do not silently import it.
  if (
    [
      ...shared,
      ...Array.from(rows.values()).flatMap((row) => Object.values(row)),
    ].some((s) =>
      /չձևակերպված|չհաստատված|չհաշվառված|pending\s+transactions/iu.test(s)
    )
  ) {
    addError(
      header,
      "Найдены неподтверждённые операции: этот блок пока не поддерживается.",
    );
  }
  return { items, errors, errorCount };
}
