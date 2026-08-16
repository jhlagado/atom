import { createStatementsHarness } from "./statements-support.mjs";

const h = await createStatementsHarness();
h.parsePublished("LD A,$01");

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
