// This fixture uses only a synthetic test password and synthetic transactions.
import { Buffer } from "node:buffer";
import office from "npm:officecrypto-tool@0.0.19";
const folder = new URL("./", import.meta.url);
const plain = await Deno.readFile(new URL("acba_synthetic.xlsx", folder));
const encrypted = office.encrypt(Buffer.from(plain), { password: "synthetic-only", type: "standard" });
await Deno.writeFile(new URL("acba_encrypted_synthetic.xlsx", folder), encrypted);
