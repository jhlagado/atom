import assert from "node:assert/strict";
import test from "node:test";

let api;
try {
  api = await import("../src/host/source-packager/index.mjs");
} catch {
  api = {};
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const generousLimits = Object.freeze({
  maxParts: 255,
  maxPathBytes: 255,
  maxBank: 255,
});

function codec() {
  assert.equal(typeof api.parseSourcePlan, "function", "parseSourcePlan export is missing");
  assert.equal(typeof api.serializeSourcePlan, "function", "serializeSourcePlan export is missing");
  return api;
}

function parseText(text, limits = generousLimits) {
  return codec().parseSourcePlan(encoder.encode(text), limits);
}

function assertPlanError(input, code, limits = generousLimits) {
  assert.throws(
    () => codec().parseSourcePlan(
      typeof input === "string" ? encoder.encode(input) : input,
      limits,
    ),
    (error) => {
      assert.equal(error?.name, "SourcePackagerError");
      assert.equal(error?.category, "plan");
      assert.equal(error?.code, code);
      return true;
    },
  );
}

test("SP1 parses complete LF and CRLF plans", () => {
  for (const newline of ["\n", "\r\n"]) {
    const text = [
      "SP1 2",
      "P 1 lib/a.asm",
      "P 0 main.asm",
      "END",
      "",
    ].join(newline);
    assert.deepEqual(parseText(text), {
      records: [
        { bank: 1, logicalIdentity: "lib/a.asm" },
        { bank: 0, logicalIdentity: "main.asm" },
      ],
    });
  }

  assert.deepEqual(parseText("SP1 1\nP 0 main.asm\nEND"), {
    records: [{ bank: 0, logicalIdentity: "main.asm" }],
  });
});

test("SP1 serialization has one canonical LF spelling", () => {
  const bytes = codec().serializeSourcePlan({
    records: [
      { bank: 1, logicalIdentity: "lib/a.asm" },
      { bank: 0, logicalIdentity: "main.asm" },
    ],
  }, generousLimits);

  assert.ok(bytes instanceof Uint8Array);
  assert.equal(decoder.decode(bytes), "SP1 2\nP 1 lib/a.asm\nP 0 main.asm\nEND\n");
  assert.deepEqual(codec().parseSourcePlan(bytes, generousLimits), {
    records: [
      { bank: 1, logicalIdentity: "lib/a.asm" },
      { bank: 0, logicalIdentity: "main.asm" },
    ],
  });
});

test("SP1 rejects noncanonical or out-of-range counts", () => {
  for (const text of [
    "SP1 0\nEND\n",
    "SP1 256\nEND\n",
    "SP1 01\nP 0 main.asm\nEND\n",
    "SP1 +1\nP 0 main.asm\nEND\n",
    "SP1 1 \nP 0 main.asm\nEND\n",
  ]) assertPlanError(text, "invalid-count");
});

test("SP1 rejects count mismatches and record-position errors", () => {
  assertPlanError("SP1 2\nP 0 main.asm\nEND\n", "count-mismatch");
  assertPlanError("SP1 1\nP 0 a.asm\nP 0 b.asm\nEND\n", "count-mismatch");
  assertPlanError("SP1 1\n\nP 0 main.asm\nEND\n", "invalid-record");
  assertPlanError("SP1 1\n# comment\nP 0 main.asm\nEND\n", "invalid-record");
  assertPlanError("SP1 1\nQ 0 main.asm\nEND\n", "invalid-record");
});

test("SP1 rejects noncanonical or out-of-range banks", () => {
  for (const [bank, code] of [
    ["00", "invalid-bank"],
    ["01", "invalid-bank"],
    ["+1", "invalid-bank"],
    ["256", "invalid-bank"],
  ]) {
    assertPlanError(`SP1 1\nP ${bank} main.asm\nEND\n`, code);
  }
});

test("SP1 rejects every forbidden logical path shape", () => {
  for (const path of [
    "",
    "/main.asm",
    "main.asm/",
    "lib//main.asm",
    ".",
    "..",
    "lib/./main.asm",
    "lib/../main.asm",
    "lib\\main.asm",
    "C:main.asm",
    "main file.asm",
    "\tmain.asm",
    "\"main.asm\"",
    "main@asm",
  ]) {
    assertPlanError(`SP1 1\nP 0 ${path}\nEND\n`, "invalid-path");
  }
});

test("SP1 rejects non-ASCII and invalid newline bytes", () => {
  assertPlanError(Uint8Array.from([
    ...encoder.encode("SP1 1\nP 0 main"),
    0x80,
    ...encoder.encode(".asm\nEND\n"),
  ]), "non-ascii");
  assertPlanError("SP1 1\rP 0 main.asm\rEND\r", "invalid-newline");
  assertPlanError("SP1 1\nP 0 main.asm\rEND\n", "invalid-newline");
});

test("SP1 requires one exact END and rejects trailing data", () => {
  assertPlanError("SP1 1\nP 0 main.asm\n", "missing-end");
  assertPlanError("SP1 1\nP 0 main.asm\nEN", "missing-end");
  assertPlanError("SP1 1\nP 0 main.asm\nend\n", "missing-end");
  assertPlanError("SP1 1\nP 0 main.asm\nEND\nP 0 later.asm\n", "trailing-data");
  assertPlanError("SP1 1\nP 0 main.asm\nEND\nX", "trailing-data");
  assertPlanError("SP1 1\nP 0 main.asm\nEND\n\n", "trailing-data");
});

test("SP1 wire capacities pass at 255 and fail at 256", () => {
  const records = Array.from({ length: 255 }, (_, index) =>
    `P 255 p${index}.asm`);
  const plan = `SP1 255\n${records.join("\n")}\nEND\n`;
  assert.equal(parseText(plan).records.length, 255);

  const path255 = `${"a".repeat(251)}.asm`;
  const path256 = `${"a".repeat(252)}.asm`;
  assert.equal(encoder.encode(path255).length, 255);
  assert.equal(encoder.encode(path256).length, 256);
  assert.equal(parseText(`SP1 1\nP 255 ${path255}\nEND\n`).records[0].bank, 255);
  assertPlanError(`SP1 1\nP 0 ${path256}\nEND\n`, "invalid-path");
  assertPlanError("SP1 256\nEND\n", "invalid-count");
  assertPlanError("SP1 1\nP 256 main.asm\nEND\n", "invalid-bank");
});

test("SP1 enforces caller capacities exactly", () => {
  const twoRecords = "SP1 2\nP 2 a.asm\nP 0 b.asm\nEND\n";
  assert.equal(parseText(twoRecords, {
    maxParts: 2,
    maxPathBytes: 5,
    maxBank: 2,
  }).records.length, 2);

  assertPlanError(twoRecords, "part-capacity", {
    maxParts: 1,
    maxPathBytes: 5,
    maxBank: 2,
  });
  assertPlanError(twoRecords, "path-capacity", {
    maxParts: 2,
    maxPathBytes: 4,
    maxBank: 2,
  });
  assertPlanError(twoRecords, "bank-capacity", {
    maxParts: 2,
    maxPathBytes: 5,
    maxBank: 1,
  });
});

test("SP1 serialization applies the same validation and capacities", () => {
  assert.throws(
    () => codec().serializeSourcePlan({ records: [] }, generousLimits),
    (error) => error?.code === "invalid-count",
  );
  assert.throws(
    () => codec().serializeSourcePlan({
      records: [{ bank: 0, logicalIdentity: "../main.asm" }],
    }, generousLimits),
    (error) => error?.code === "invalid-path",
  );
  assert.throws(
    () => codec().serializeSourcePlan({
      records: [
        { bank: 0, logicalIdentity: "a.asm" },
        { bank: 0, logicalIdentity: "b.asm" },
      ],
    }, { maxParts: 1, maxPathBytes: 255, maxBank: 255 }),
    (error) => error?.code === "part-capacity",
  );
});
