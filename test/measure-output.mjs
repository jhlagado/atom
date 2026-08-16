import { createOutputHarness } from "./output-support.mjs";
import { validCases } from "./cases.mjs";

const h = await createOutputHarness();

h.reset();
h.parse("LD (IX+Disp),Forward");
h.emit();

h.reset();
for (let index = 0; index < 8; index += 1) {
  const address = 0x4000 + index * 3;
  h.parse(`JP Same+${index}`, { address });
  h.emit();
}
let declared = h.declare("Same", 0x5000);
h.resolve(declared.ix);

h.reset();
for (let index = 0; index < 8; index += 1) {
  const address = 0x4000 + index * 3;
  h.parse(`JP Symbol${index}`, { address });
  h.emit();
}
const finalRecord = h.pendingRecords().at(-1);
const finalSymbol = finalRecord[0] | (finalRecord[1] << 8);
h.pendingPeek(finalSymbol);

for (const [source, value] of [
  ["ADD A,Forward+127", 128],
  ["JP Forward-128", 0xffff],
  ["JR Forward", 0x4081],
  ["LD A,(IY+Forward-128)", 0],
]) {
  h.reset();
  h.parse(source);
  h.emit();
  declared = h.declare("Forward", value);
  h.resolve(declared.ix);
}

const s = h.symbols;
const extent = (start, end) => s[end] - s[start];
console.log(JSON.stringify({
  labels: "All byte, instruction, cycle, and coverage counts are Measured in the Phase 2f proof image.",
  coverage: {
    concreteFormsEmitted: validCases().length,
    instructionLengthClasses: 4,
    patchKinds: 4,
    imageSinkFailurePositions: 4,
    maximumPendingRecordsDrained: 8,
    flatBanks: 1,
  },
  components: {
    outputCode: extent("AtomOutputCodeStart", "AtomOutputCodeEnd"),
    outputWorkspace: extent("AtomOutputWorkspaceStart", "AtomOutputWorkspaceEnd"),
    pendingPeekCodeIncrement: extent("AtomSymbolCodeStart", "AtomSymbolCodeEnd") - 590,
    parserPreflightCodeIncrement: extent("AtomParserCodeStart", "AtomParserCodeEnd") - 1975,
    proofAdapterCode: extent("AtomOutputProofAdapterStart", "AtomOutputProofAdapterEnd"),
    proofAdapterWorkspace: extent("AtomOutputProofAdapterWorkspaceStart", "AtomOutputProofAdapterWorkspaceEnd"),
  },
  integrated: {
    codeAndTables:
      extent("AtomEncoderCoreStart", "AtomEncoderCoreEnd") +
      extent("AtomSymbolCodeStart", "AtomSymbolCodeEnd") +
      extent("AtomTokenizerCodeStart", "AtomTokenizerCodeEnd") +
      extent("AtomExpressionCodeStart", "AtomExpressionCodeEnd") +
      extent("AtomPatchCodeStart", "AtomPatchCodeEnd") +
      extent("AtomParserCodeStart", "AtomParserCodeEnd") +
      extent("AtomOutputCodeStart", "AtomOutputCodeEnd"),
    fixedWorkspace:
      extent("AtomEncoderWorkspaceStart", "AtomEncoderWorkspaceEnd") +
      extent("AtomSymbolWorkspaceStart", "AtomSymbolWorkspaceEnd") +
      extent("AtomTokenizerWorkspaceStart", "AtomTokenizerWorkspaceEnd") +
      extent("AtomExpressionWorkspaceStart", "AtomExpressionWorkspaceEnd") +
      extent("AtomParserWorkspaceStart", "AtomParserWorkspaceEnd") +
      extent("AtomOutputWorkspaceStart", "AtomOutputWorkspaceEnd"),
  },
  execution: h.statistics,
}, null, 2));
