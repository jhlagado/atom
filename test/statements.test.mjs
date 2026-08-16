import assert from "node:assert/strict";
import test from "node:test";

import { validCases } from "./cases.mjs";
import { createStatementsHarness } from "./statements-support.mjs";

const h = await createStatementsHarness();

test("published mnemonic continuation preserves the existing parser record", () => {
  const item = validCases().find(({ source }) => source === "LD A,$01");
  assert.ok(item);
  const parsed = h.parsePublished(item.source);
  assert.equal(parsed.carry, 0);
  assert.deepEqual(h.record(), Array.from(item.record));
});
