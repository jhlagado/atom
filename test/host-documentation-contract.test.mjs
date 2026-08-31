import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";

const executable = fileURLToPath(new URL("../bin/atom.mjs", import.meta.url));

const activeDocuments = [
  "README.md",
  "docs/architecture.md",
  "docs/command-line.md",
  "docs/cpm22.md",
  "docs/desktop-host-integration.md",
  "docs/host-source-preparation.md",
  "docs/language-reference.md",
  "docs/limits.md",
  "docs/native-driver-abi.md",
  "docs/output-abi.md",
  "docs/release-checklist.md",
  "docs/tec-1-deployment.md",
  "docs/tokenizer-abi.md",
  "docs/tool-services.md",
];

function run(arguments_) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [executable, ...arguments_], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (status) => resolve({ status, stdout, stderr }));
  });
}

async function readDocuments(filenames) {
  return new Map(await Promise.all(filenames.map(async (filename) => [
    filename,
    await fs.readFile(filename, "utf8"),
  ])));
}

test("desktop CLI help and package documentation describe the same contract", async () => {
  const help = await run(["--help"]);
  assert.equal(help.status, 0, help.stderr);

  const documents = await readDocuments([
    "README.md",
    "docs/command-line.md",
    "docs/codebase/appendices/c-public-surface-and-abi-reference.md",
  ]);
  const commandGuide = documents.get("docs/command-line.md");
  const apiAppendix = documents.get("docs/codebase/appendices/c-public-surface-and-abi-reference.md");

  for (const fragment of [
    "atom [options] <input.asm> [output...]",
    "atom --project <project.json> [output...]",
    "atom self-host [output...]",
    "With no output, Atom writes build/<input>.bin.",
  ]) {
    assert.match(help.stdout, new RegExp(fragment.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }

  for (const option of ["--project", "--output", "--target", "-DNAME", "--help", "--version"]) {
    assert.ok(commandGuide.includes(option), `command-line.md omits ${option}`);
    assert.ok(apiAppendix.includes(option), `the public-surface appendix omits ${option}`);
  }

  const suffixLine = help.stdout.match(/^Output suffixes: (.+)$/m);
  assert.ok(suffixLine, "CLI help has no output-suffix contract");
  for (const suffix of suffixLine[1].split(/\s+/)) {
    assert.ok(commandGuide.includes(suffix), `command-line.md omits ${suffix}`);
    assert.ok(apiAppendix.includes(suffix), `the public-surface appendix omits ${suffix}`);
  }

  assert.match(documents.get("README.md"), /With no explicit output, Atom\s+writes `build\/main\.bin`/);
  assert.match(commandGuide, /Output selection is affirmative/);
  assert.match(commandGuide, /There is no\s+default bundle of artifacts/);
});

test("native CP/M command forms remain explicit in package documentation", async () => {
  const documents = await readDocuments(["docs/command-line.md", "docs/cpm22.md"]);
  for (const [filename, source] of documents) {
    for (const command of ["ATOM", "ATOM SOURCE", "ATOM SOURCE OUTPUT"]) {
      assert.ok(source.includes(command), `${filename} omits ${command}`);
    }
    assert.ok(source.includes("INPUT.ASM"), `${filename} omits the default input`);
    assert.ok(source.includes("OUTPUT.COM"), `${filename} omits the default output`);
    for (const suffix of [".COM", ".BIN", ".HEX"]) {
      assert.ok(source.includes(suffix), `${filename} omits ${suffix}`);
    }
  }
});

test("active documentation uses platform terms rather than machine-specific desktop history", async () => {
  const documents = await readDocuments(activeDocuments);
  for (const [filename, source] of documents) {
    assert.doesNotMatch(source, /\bMac\b/, `${filename} uses Mac where desktop or Node is the contract`);
    assert.doesNotMatch(source, /\bspell(?:ing|ings|ed)\b/i, `${filename} uses imprecise format terminology`);
  }
  await assert.rejects(fs.access("docs/mac-host-integration.md"));
  await fs.access("docs/desktop-host-integration.md");
});
