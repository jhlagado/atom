import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { compile } from "@jhlagado/azm";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourcePath = path.join(repositoryRoot, "asm", "atom-host-runtime.asm");
const outputPath = path.join(repositoryRoot, "assets", "native-core.json");

const addressOf = (symbol) => symbol.address ?? symbol.value;

function artifact(result, kind) {
  const selected = result.artifacts.find((candidate) => candidate.kind === kind);
  if (selected === undefined) throw new Error(`AZM omitted the ${kind} artifact`);
  return selected;
}

async function buildArtifact() {
  const result = await compile(sourcePath, {
    emitHex: true,
    emitD8m: true,
    registerContracts: "strict",
  });
  const errors = result.diagnostics.filter(({ severity }) => severity === "error");
  if (errors.length !== 0) {
    throw new Error(`strict-contract native core failed to assemble:\n${JSON.stringify(errors, null, 2)}`);
  }
  const hexText = artifact(result, "hex").text;
  const symbols = Object.fromEntries(
    artifact(result, "d8m").json.symbols
      .flatMap((symbol) => {
        const value = addressOf(symbol);
        return value === undefined ? [] : [[symbol.name, value]];
      })
      .sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0),
  );
  const artifactSha256 = createHash("sha256")
    .update(hexText, "utf8")
    .update("\0", "utf8")
    .update(JSON.stringify(symbols), "utf8")
    .digest("hex");
  return {
    format: "atom-native-core",
    version: 1,
    source: "asm/atom-host-runtime.asm",
    hexSha256: createHash("sha256").update(hexText, "utf8").digest("hex"),
    artifactSha256,
    hexText,
    symbols,
  };
}

const rendered = `${JSON.stringify(await buildArtifact(), null, 2)}\n`;
if (process.argv.includes("--check")) {
  let committed;
  try {
    committed = await fs.readFile(outputPath, "utf8");
  } catch {
    committed = undefined;
  }
  if (committed !== rendered) {
    process.stderr.write("assets/native-core.json is stale; run npm run build:native-core\n");
    process.exitCode = 1;
  }
} else {
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  await fs.writeFile(outputPath, rendered, "utf8");
}
