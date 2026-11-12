import { XMLParser, XMLValidator } from "npm:fast-xml-parser@5.12.0";
import { ImportFormatError } from "./parser.ts";

const MAX_EXPANDED = 8 * 1024 * 1024;
const MAX_XML = 4 * 1024 * 1024;
const requiredFiles = new Set([
  "xl/sharedStrings.xml",
  "xl/worksheets/sheet1.xml",
]);
function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const b of bytes) {
    crc ^= b;
    for (let bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}
const badFile = () =>
  new ImportFormatError(
    "Не удалось безопасно прочитать XLSX. Проверьте формат файла.",
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
      if (
        data.length !== expanded ||
        crc32(data) !== view.getUint32(at + 16, true)
      ) throw badFile();
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
export async function readXlsx(
  bytes: Uint8Array,
): Promise<{ shared: string[]; rows: Map<number, Record<string, string>> }> {
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
  return { shared, rows };
}
