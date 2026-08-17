import { MNEMONICS } from "../src/abi.mjs";
import { invalidCases, systematicInvalidRecords, validCases } from "./cases.mjs";
import { azmBytes, azmRejects, createHarness, extent } from "./support.mjs";

const harness = await createHarness();
const s = harness.symbols;
const valid = validCases();
const negative = invalidCases().filter(({ source }) => azmRejects(source));
const encodings = new Set(valid.map(({ source }) => azmBytes(source).map((b) => b.toString(16).padStart(2, "0")).join("")));
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
    repository: "/Users/johnhardy/projects/debug80",
    branch: "main",
    head: "b4046badd29b1dd1bc146029728bacaa5e5fe603",
    azmTree: "7889245c380334768f62805e73c13e979aa9f8c8",
    runtimeTree: "a921abc89dcbd88211dd008e705b69d646cfb9bb",
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
    azmSupportedFraction: `${valid.length}/${valid.length} of the frozen AZM form census`,
    unsupportedAzmForms: [],
  },
  execution: harness.statistics,
  wholeAssembler: {
    classification: "Projected",
    bytes: { low: 9249, high: 11849 },
    kibibytes: { low: 9.0, high: 11.6 },
    basis: "Measured 3234-byte core plus a historical projected 6000-8600 remaining resident bytes; see docs/phase-1-report.md",
  },
  gates: { target: 3000, reviewAbove: 3500, rejectAbove: 5000 },
};

console.log(JSON.stringify(result, null, 2));
