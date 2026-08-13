import { MNEMONICS } from "../src/abi.mjs";
import { invalidCases, validCases } from "./cases.mjs";
import { azmBytes, azmRejects, createHarness, extent } from "./support.mjs";

const harness = await createHarness();
const s = harness.symbols;
const valid = validCases();
const negative = invalidCases().filter(({ source }) => azmRejects(source));
const encodings = new Set(valid.map(({ source }) => azmBytes(source).map((b) => b.toString(16).padStart(2, "0")).join("")));
const records = new Set(valid.map(({ record }) => Buffer.from(record).toString("hex")));

const result = {
  labels: "All byte counts are Measured unless explicitly marked Projected or Hypothesis.",
  authority: {
    repository: "/Users/johnhardy/projects/debug80",
    branch: "main",
    head: "f0c6643c145bdcfddf11255116ad39ec9836bc9f",
  },
  resident: {
    total: extent(s, "ZapEncoderCoreStart", "ZapEncoderCoreEnd"),
    code: extent(s, "ZapEncoderCodeStart", "ZapEncoderCodeEnd"),
    immutable: extent(s, "ZapEncoderImmutableStart", "ZapEncoderImmutableEnd"),
    ruleEncodingCode: extent(s, "ZapRuleEncodingCodeStart", "ZapRuleEncodingCodeEnd"),
    validationCode: extent(s, "ZapValidationCodeStart", "ZapValidationCodeEnd"),
    radix40Code: extent(s, "ZapRadix40CodeStart", "ZapRadix40CodeEnd"),
    recognitionCode: extent(s, "ZapRecognitionCodeStart", "ZapRecognitionCodeEnd"),
    opcodeTables: extent(s, "ZapOpcodeTableStart", "ZapOpcodeTableEnd"),
    mnemonicTable: extent(s, "ZapMnemonicTable", "ZapMnemonicTableEnd"),
    ldValidationCode: extent(s, "ZapLdValidationStart", "ZapLdValidationEnd"),
    ldEncodingCode: extent(s, "ZapLdEncodingStart", "ZapLdEncodingEnd"),
    ldDirectTotal:
      extent(s, "ZapLdValidationStart", "ZapLdValidationEnd") +
      extent(s, "ZapLdEncodingStart", "ZapLdEncodingEnd"),
    recognitionExclusive:
      extent(s, "ZapRecognitionCodeStart", "ZapRecognitionCodeEnd") +
      extent(s, "ZapMnemonicTable", "ZapMnemonicTableEnd"),
    recognitionIncludingSharedPacker:
      extent(s, "ZapRecognitionCodeStart", "ZapRecognitionCodeEnd") +
      extent(s, "ZapMnemonicTable", "ZapMnemonicTableEnd") +
      extent(s, "ZapRadix40CodeStart", "ZapRadix40CodeEnd"),
  },
  workspace: extent(s, "ZapEncoderWorkspaceStart", "ZapEncoderWorkspaceEnd"),
  coverage: {
    mnemonicSpellings: MNEMONICS.length - 1,
    validSourceCases: valid.length,
    normalizedRecords: records.size,
    uniqueByteSequences: encodings.size,
    rejectedSourceCases: negative.length,
    azmSupportedFraction: "1/1 of the explicitly modelled AZM instruction-form grammar",
    unsupportedAzmForms: [],
  },
  wholeAssembler: {
    classification: "Projected",
    bytes: { low: 9968, high: 12568 },
    kibibytes: { low: 9.7, high: 12.3 },
    basis: "Measured 3968-byte core plus a projected 6000-8600 remaining resident bytes; see docs/phase-1-report.md",
  },
  gates: { target: 3000, reviewAbove: 3500, rejectAbove: 5000 },
};

console.log(JSON.stringify(result, null, 2));
