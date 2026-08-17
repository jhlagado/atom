import fs from "node:fs";

import { createIntegrationHarness } from "./integration-support.mjs";

const manifest = JSON.parse(fs.readFileSync("proofs/phase-2c.json", "utf8"));

export const PARSER_STATUS = Object.freeze({
  OK: 0,
  EOF: 1,
  LEXICAL: 2,
  EXPECTED_MNEMONIC: 3,
  UNKNOWN_MNEMONIC: 4,
  EXPECTED_OPERAND: 5,
  UNKNOWN_OPERAND: 6,
  EXPECTED_DELIMITER: 7,
  TOO_MANY_OPERANDS: 8,
  INVALID_FORM: 9,
  VALUE_RANGE: 10,
  RELATIVE_RANGE: 11,
  INTERNAL: 12,
  EXPRESSION: 13,
  UNPATCHABLE: 14,
  SYMBOL: 15,
  REFERENCE_CAPACITY: 16,
  PART_CAPACITY: 17,
});

export async function createParserHarness() {
  const checked = await createIntegrationHarness({ proofManifest: manifest });
  const base = checked.symbols;
  const symbols = Object.freeze({
    ...base,
    AtomParserProofSourceStart: base.AtomIntegrationProofSourceStart,
    AtomParserSourceBefore: base.AtomIntegrationSourceBefore,
    AtomParserSource: base.AtomIntegrationSource,
    AtomParserSourceLimit: base.AtomIntegrationSourceLimit,
    AtomParserSourceAfter: base.AtomIntegrationSourceAfter,
    AtomParserProofSourceEnd: base.AtomIntegrationProofSourceEnd,
    AtomParserProofRecordStart: base.AtomIntegrationProofRecordStart,
    AtomParserRecordBefore: base.AtomIntegrationRecordBefore,
    AtomParserRecord: base.AtomIntegrationRecord,
    AtomParserRecordAfter: base.AtomIntegrationRecordAfter,
    AtomParserProofRecordEnd: base.AtomIntegrationProofRecordEnd,
    AtomParserProofOutputStart: base.AtomIntegrationProofOutputStart,
    AtomParserOutputBefore: base.AtomIntegrationOutputBefore,
    AtomParserOutput: base.AtomIntegrationOutput,
    AtomParserOutputAfter: base.AtomIntegrationOutputAfter,
    AtomParserProofOutputEnd: base.AtomIntegrationProofOutputEnd,
  });
  return {
    ...checked,
    symbols,
    manifest,
    parse(source, options) {
      checked.reset();
      return checked.parse(source, options);
    },
  };
}
