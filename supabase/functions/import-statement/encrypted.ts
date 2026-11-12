import CFB from "npm:cfb@1.2.2";
import office from "npm:officecrypto-tool@0.0.19";
import { Buffer } from "node:buffer";
import { ImportFormatError } from "./parser.ts";
const maximum = 1024 * 1024;

// Only the Office Standard AES-128 variant observed in ACBA's example is accepted.
// The original remains encrypted; decrypted bytes and password exist only in this request.
export async function decryptAcba(
  bytes: Uint8Array,
  password: unknown,
): Promise<Uint8Array> {
  if (typeof password !== "string" || !password || password.length > 255) {
    throw new ImportFormatError("Введите пароль от выписки ACBA.");
  }
  try {
    const compound = CFB.read(Buffer.from(bytes), { type: "buffer" });
    const rawInfo = CFB.find(compound, "/EncryptionInfo")?.content;
    const rawPackage = CFB.find(compound, "/EncryptedPackage")?.content;
    const info = rawInfo ? Buffer.from(rawInfo as Uint8Array) : null;
    const pkg = rawPackage ? Buffer.from(rawPackage as Uint8Array) : null;
    if (
      !info || !pkg || info.length < 64 || info.length > 4096 ||
      pkg.length < 24 || pkg.length > maximum + 24
    ) throw Error();
    const head = info.readUInt32LE(8);
    if (
      ![2, 3, 4].includes(info.readUInt16LE(0)) || info.readUInt16LE(2) !== 2 ||
      info.readUInt32LE(4) !== 0x24 || head < 32 || head > info.length - 64 ||
      info.readUInt32LE(20) !== 0x660e || info.readUInt32LE(24) !== 0x8004 ||
      info.readUInt32LE(28) !== 128 || info.readUInt32LE(32) !== 24
    ) throw Error();
    const size = pkg.readBigUInt64LE(0);
    if (
      size === 0n || size > BigInt(maximum) ||
      pkg.length !== 8 + Math.ceil(Number(size) / 16) * 16
    ) throw Error();
    const result = await office.decrypt(Buffer.from(bytes), { password });
    if (
      result.length !== Number(size) || result[0] !== 0x50 ||
      result[1] !== 0x4b || result[2] !== 3 || result[3] !== 4
    ) throw Error();
    return new Uint8Array(result);
  } catch (e) {
    if (e instanceof Error && e.message === "The password is incorrect") {
      throw new ImportFormatError("Неверный пароль от выписки.");
    }
    throw new ImportFormatError(
      "Не удалось расшифровать файл: формат защиты не поддерживается или файл повреждён.",
    );
  }
}
