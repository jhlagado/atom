import { createStatementsHarness } from "./statements-support.mjs";

const h = await createStatementsHarness();
h.parsePublished("LD A,$01");

h.reset();
const first = h.pack("First").key;
h.declareGlobalLabel(first, 0x4000);
const local = h.pack("_Local").key;
h.declare(local, 0x4001);
h.find(local);
const second = h.pack("Second").key;
h.declareGlobalLabel(second, 0x4010);
h.find(second);

h.reset();
h.declareGlobalLabel(h.pack("First").key, 0x4000);
const unresolved = h.reference(h.pack("_Forward").key);
h.declareGlobalLabel(h.pack("Second").key, 0x4010);
h.declare(h.pack("_Forward").key, 0x4002);
h.declareGlobalLabel(first, 0x5000);

h.reset({ symbolBytes: 7 });
h.declareGlobalLabel(h.pack("Bound").key, 0x4000);

h.reset();
h.declareGlobalLabel(h.pack("First").key, 0x4000);
const stale = h.reference(h.pack("_Target").key);
h.pendingAdd(stale.ix, 0x5001);
h.declare(h.pack("_Target").key, 0x4100);
h.declareGlobalLabel(h.pack("Second").key, 0x4200);

h.reset();
h.advanceScope();
h.declare(h.pack("_Local").key, 0x4000);
h.advanceScope();

const s = h.symbols;
const extent = (start, end) => s[end] - s[start];
const codeThroughParser =
  extent("AtomEncoderCoreStart", "AtomEncoderCoreEnd") +
  extent("AtomSymbolCodeStart", "AtomSymbolCodeEnd") +
  extent("AtomTokenizerCodeStart", "AtomTokenizerCodeEnd") +
  extent("AtomExpressionCodeStart", "AtomExpressionCodeEnd") +
  extent("AtomPatchCodeStart", "AtomPatchCodeEnd") +
  extent("AtomParserCodeStart", "AtomParserCodeEnd");
const workspaceThroughParser =
  extent("AtomEncoderWorkspaceStart", "AtomEncoderWorkspaceEnd") +
  extent("AtomSymbolWorkspaceStart", "AtomSymbolWorkspaceEnd") +
  extent("AtomTokenizerWorkspaceStart", "AtomTokenizerWorkspaceEnd") +
  extent("AtomExpressionWorkspaceStart", "AtomExpressionWorkspaceEnd") +
  extent("AtomParserWorkspaceStart", "AtomParserWorkspaceEnd");

console.log(JSON.stringify({
  labels: {
    componentsAndExecution: "Measured in the Phase 2g proof image.",
    currentResidentWithOutput: "Projected by adding the separately Measured 359-byte output code and 21-byte output workspace.",
  },
  components: {
    symbolCodeAndTables: extent("AtomSymbolCodeStart", "AtomSymbolCodeEnd"),
    globalLabelTransactionIncrement: extent("AtomSymbolCodeStart", "AtomSymbolCodeEnd") - 723,
    parserCodeAndTables: extent("AtomParserCodeStart", "AtomParserCodeEnd"),
    parserWorkspace: extent("AtomParserWorkspaceStart", "AtomParserWorkspaceEnd"),
    statementContinuationIncrement: extent("AtomParserCodeStart", "AtomParserCodeEnd") - 2035,
  },
  integrated: {
    codeAndTablesThroughParser: codeThroughParser,
    fixedWorkspaceThroughParser: workspaceThroughParser,
    projectedCurrentResidentCodeAndTablesWithOutput: codeThroughParser + 359,
    projectedCurrentFixedWorkspaceWithOutput: workspaceThroughParser + 21,
    marginTo16KiBCodeAndTables: 0x4000 - (codeThroughParser + 359),
  },
  execution: h.statistics,
}, null, 2));
