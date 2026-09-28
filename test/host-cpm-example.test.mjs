import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

test("the standalone CP/M hello source assembles to its expected COM image", async () => {
  const outputDirectory = await mkdtemp(join(tmpdir(), "atom-cpm-example-"));
  try {
    const outputPath = join(outputDirectory, "HELLO.COM");
    const output = execFileSync(
      process.execPath,
      [join(repositoryRoot, "bin/atom.mjs"), "hello.asm", outputPath],
      {
        cwd: join(repositoryRoot, "examples/cpm"),
        encoding: "utf8",
      },
    );
    const image = await readFile(outputPath);

    assert.match(output, /Atom assembled 1 part\(s\), 27 byte\(s\)\./);
    assert.deepEqual(
      image,
      Buffer.from([
        0x11, 0x09, 0x01, // LD DE,MESSAGE
        0x0e, 0x09, // LD C,9
        0xcd, 0x05, 0x00, // CALL 5
        0xc9, // RET
        ...Buffer.from("HELLO FROM ATOM\r\n$", "ascii"),
      ]),
    );
  } finally {
    await rm(outputDirectory, { recursive: true, force: true });
  }
});
