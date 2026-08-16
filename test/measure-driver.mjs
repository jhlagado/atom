import { createDriverHarness } from "./driver-support.mjs";

const h = await createDriverHarness();

h.validate(Array.from({ length: 16 }, () => ""), { label: "AtomDriverValidateDescriptor 16 parts" });

const sixteen = Array.from({ length: 16 }, () => "");
sixteen[15] = [
  "Low EQU -32768",
  "High EQU 65535",
  "Calc EQU ((2+3)*4)|1",
  "LD HL,Low",
  "LD DE,High",
  "LD A,Calc",
  "",
].join("\n");
h.assemble(sixteen, { label: "AtomAssemble 16 parts and six statements" });

const definitions = Array.from({ length: 32 }, (_, index) => `S${index} EQU ${index}`).join("\n") + "\n";
h.assemble([definitions], { label: "AtomAssemble 32 definitions" });
h.finish("AtomAssembleFinish 32 definitions");

const s = h.symbols;
const extent = (start, end) => s[end] - s[start];
const integratedCode = [
  ["AtomEncoderCoreStart", "AtomEncoderCoreEnd"],
  ["AtomSymbolCodeStart", "AtomSymbolCodeEnd"],
  ["AtomTokenizerCodeStart", "AtomTokenizerCodeEnd"],
  ["AtomExpressionCodeStart", "AtomExpressionCodeEnd"],
  ["AtomPatchCodeStart", "AtomPatchCodeEnd"],
  ["AtomParserCodeStart", "AtomParserCodeEnd"],
  ["AtomOutputCodeStart", "AtomOutputCodeEnd"],
  ["AtomStatementCodeStart", "AtomStatementCodeEnd"],
  ["AtomDriverCodeStart", "AtomDriverCodeEnd"],
].reduce((sum, [start, end]) => sum + extent(start, end), 0);
const integratedWorkspace = [
  ["AtomEncoderWorkspaceStart", "AtomEncoderWorkspaceEnd"],
  ["AtomSymbolWorkspaceStart", "AtomSymbolWorkspaceEnd"],
  ["AtomTokenizerWorkspaceStart", "AtomTokenizerWorkspaceEnd"],
  ["AtomExpressionWorkspaceStart", "AtomExpressionWorkspaceEnd"],
  ["AtomParserWorkspaceStart", "AtomParserWorkspaceEnd"],
  ["AtomOutputWorkspaceStart", "AtomOutputWorkspaceEnd"],
  ["AtomStatementWorkspaceStart", "AtomStatementWorkspaceEnd"],
  ["AtomDriverWorkspaceStart", "AtomDriverWorkspaceEnd"],
].reduce((sum, [start, end]) => sum + extent(start, end), 0);

console.log(JSON.stringify({
  labels: {
    componentsAndExecution: "Measured in the linked Phase 3 multipart-driver proof image.",
  },
  components: {
    symbolCodeAndTables: extent("AtomSymbolCodeStart", "AtomSymbolCodeEnd"),
    parserCodeAndTables: extent("AtomParserCodeStart", "AtomParserCodeEnd"),
    outputCode: extent("AtomOutputCodeStart", "AtomOutputCodeEnd"),
    statementCode: extent("AtomStatementCodeStart", "AtomStatementCodeEnd"),
    driverCode: extent("AtomDriverCodeStart", "AtomDriverCodeEnd"),
    driverWorkspace: extent("AtomDriverWorkspaceStart", "AtomDriverWorkspaceEnd"),
    diagnosticMetadataIncrement: integratedCode - 11750 - extent("AtomDriverCodeStart", "AtomDriverCodeEnd"),
  },
  integrated: {
    codeAndTables: integratedCode,
    fixedWorkspace: integratedWorkspace,
    marginTo16KiBCodeAndTables: 0x4000 - integratedCode,
  },
  capacities: {
    sourceParts: s.AtomDriverPartCapacity,
    partDescriptorBytes: s.AtomDriverPartDescriptorBytes,
    buildDescriptorBytes: s.AtomDriverDescriptorBytes,
    symbolRecordBytes: s.AtomSymbolRecordBytes,
    pendingRecordBytes: s.AtomPendingRecordBytes,
  },
  execution: h.statistics,
}, null, 2));
