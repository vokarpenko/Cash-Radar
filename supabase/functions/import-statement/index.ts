import { handleImport } from "./handler.ts";

Deno.serve((req) => handleImport(req));
