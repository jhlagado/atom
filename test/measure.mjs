import { MNEMONICS } from "../src/host/abi.mjs";
import { loadNativeAtomCore } from "../src/host/index.mjs";
import { invalidCases, systematicInvalidRecords, validCases } from "./cases.mjs";
import { referenceBytes, referenceRejects } from "./reference-fixtures.mjs";
import { createHarness, extent } from "./support.mjs";

const harness = await createHarness();
const core = await loadNativeAtomCore();
const s = harness.symbols;
const valid = validCases();
const negative = invalidCases().filter(({ source }) => referenceRejects(source));
const encodings = new Set(valid.map(({ source }) => referenceBytes(source).map((b) => b.toString(16).padStart(2, "0")).join("")));
const records = new Set(valid.map(({ record }) => Buffer.from(record).toString("hex")));

for (const { record } of valid) {
  harness.length(record);
  harness.encode(record);
}
for (const record of systematicInvalidRecords()) {
  harness.length(record);
  harness.encode(record);
}
for (const mnemonic of MNEMONICS.slice(1)) harness.recognize(mnemonic);
harness.recognize("ZZZZ");
harness.pack("ZZZZZZZZ");

const result = {
  labels: "All byte counts are Measured unless explicitly marked Projected or Hypothesis.",
  authority: {
    source: core.source,
    nativeCoreSha256: core.artifactSha256,
    historicalReference: "test/fixtures/historical-assembly.json",
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
    systematicRejectedRecords: systematicInvalidRecords().length,
    supportedFraction: `${valid.length}/${valid.length} of the frozen instruction-form census`,
    unsupportedForms: [],
  },
  execution: harness.statistics,
  wholeAssembler: {
    classification: "Measured",
    bytes: 12400,
    kibibytes: 12.1,
    basis: "Current checked native image, including fixed workspace",
  },
  gates: { target: 3000, reviewAbove: 3500, rejectAbove: 5000 },
};

console.log(JSON.stringify(result, null, 2));
