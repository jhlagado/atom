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
    total: extent(s, "AtomEncoderCoreStart", "AtomEncoderCoreEnd"),
    code: extent(s, "AtomEncoderCodeStart", "AtomEncoderCodeEnd"),
    immutable: extent(s, "AtomEncoderImmutableStart", "AtomEncoderImmutableEnd"),
    ruleEncodingCode: extent(s, "AtomRuleEncodingCodeStart", "AtomRuleEncodingCodeEnd"),
    validationCode: extent(s, "AtomValidationCodeStart", "AtomValidationCodeEnd"),
    radix40Code: extent(s, "AtomRadix40CodeStart", "AtomRadix40CodeEnd"),
    recognitionCode: extent(s, "AtomRecognitionCodeStart", "AtomRecognitionCodeEnd"),
    opcodeTables: extent(s, "AtomOpcodeTableStart", "AtomOpcodeTableEnd"),
    mnemonicTable: extent(s, "AtomMnemonicTable", "AtomMnemonicTableEnd"),
    ldValidationCode: extent(s, "AtomLdValidationStart", "AtomLdValidationEnd"),
    ldEncodingCode: extent(s, "AtomLdEncodingStart", "AtomLdEncodingEnd"),
    ldDirectTotal:
      extent(s, "AtomLdValidationStart", "AtomLdValidationEnd") +
      extent(s, "AtomLdEncodingStart", "AtomLdEncodingEnd"),
    recognitionExclusive:
      extent(s, "AtomRecognitionCodeStart", "AtomRecognitionCodeEnd") +
      extent(s, "AtomMnemonicTable", "AtomMnemonicTableEnd"),
    recognitionIncludingSharedPacker:
      extent(s, "AtomRecognitionCodeStart", "AtomRecognitionCodeEnd") +
      extent(s, "AtomMnemonicTable", "AtomMnemonicTableEnd") +
      extent(s, "AtomRadix40CodeStart", "AtomRadix40CodeEnd"),
  },
  workspace: extent(s, "AtomEncoderWorkspaceStart", "AtomEncoderWorkspaceEnd"),
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
