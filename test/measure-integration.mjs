import { validCases } from "./cases.mjs";
import { createIntegrationHarness } from "./integration-support.mjs";

const h = await createIntegrationHarness();
const patchableClasses = new Set([48, 49, 50, 51, 52, 54]);
let patchable = 0;
let unpatchable = 0;

for (const item of validCases()) {
  h.reset();
  h.parse(item.source);
  h.encodeParsed(item.source);
  for (let operand = 0; operand < 3; operand += 1) {
    h.locate(operand);
    if (patchableClasses.has(item.record[1 + operand])) patchable += 1;
    else unpatchable += 1;
  }
}

h.reset();
for (const [name, value] of [["Value", 17], ["Table", 0x2000], ["Target", 0x4070], ["Disp", 3]]) h.declare(name, value);
for (const source of [
  "LD A,vAlUe+1", "LD HL,Value*2", "LD A,(Table+2)", "LD (Table-1),HL",
  "JR Target+1", "LD (IX+Disp*2),$10+2", "LD HL,$+2", "RST 4*2",
  "BIT 1+1,A", "IM 1+1",
]) {
  h.parse(source);
  h.encodeParsed(source);
}

for (const source of ["JP Forward+5", "JR Forward-3", "ADD A,Forward", "LD A,(Forward+2)"]) {
  h.reset();
  h.parse(source);
  h.queueReferences(0x4000);
}
h.reset();
h.parse("LD (IX+Disp),Forward");
h.queueReferences(0x4000);
for (const source of ["INC Forward", "BIT Forward,A", "RST Forward", "LD A,Forward*2"]) {
  h.reset();
  h.parse(source);
}

const s = h.symbols;
console.log(JSON.stringify({
  labels: "All byte, instruction, cycle, and census counts are Measured in the Phase 2e proof image.",
  coverage: {
    concreteFormsParsedAndEncoded: validCases().length,
    patchableOperandSitesLocated: patchable,
    unpatchableOperandSitesRejected: unpatchable,
    resolvedExpressionForms: 10,
    forwardMetadataForms: 5,
    invalidForwardForms: 4,
  },
  components: {
    deferredExpressionCode: s.AtomExpressionCodeEnd - s.AtomExpressionCodeStart,
    deferredExpressionWorkspace: s.AtomExpressionWorkspaceEnd - s.AtomExpressionWorkspaceStart,
    patchLocatorCode: s.AtomPatchCodeEnd - s.AtomPatchCodeStart,
    symbolicParserCodeAndTable: s.AtomParserCodeEnd - s.AtomParserCodeStart,
    symbolicParserWorkspace: s.AtomParserWorkspaceEnd - s.AtomParserWorkspaceStart,
    referenceBuildList: s.AtomParserReferences - s.AtomParserReferenceBuild,
    publicReferenceList: s.AtomParserWorkspaceEnd - s.AtomParserReferences,
  },
  integrated: {
    codeAndTables:
      (s.AtomEncoderCoreEnd - s.AtomEncoderCoreStart) +
      (s.AtomSymbolCodeEnd - s.AtomSymbolCodeStart) +
      (s.AtomTokenizerCodeEnd - s.AtomTokenizerCodeStart) +
      (s.AtomExpressionCodeEnd - s.AtomExpressionCodeStart) +
      (s.AtomPatchCodeEnd - s.AtomPatchCodeStart) +
      (s.AtomParserCodeEnd - s.AtomParserCodeStart),
    fixedWorkspace:
      (s.AtomEncoderWorkspaceEnd - s.AtomEncoderWorkspaceStart) +
      (s.AtomSymbolWorkspaceEnd - s.AtomSymbolWorkspaceStart) +
      (s.AtomTokenizerWorkspaceEnd - s.AtomTokenizerWorkspaceStart) +
      (s.AtomExpressionWorkspaceEnd - s.AtomExpressionWorkspaceStart) +
      (s.AtomParserWorkspaceEnd - s.AtomParserWorkspaceStart),
  },
  execution: h.statistics,
}, null, 2));
