import { createRequire } from "node:module";

const metadata = createRequire(import.meta.url)("../../package.json");

export const ATOM_VERSION = metadata.version;
