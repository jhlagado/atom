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

h.assemble("Start:\n  LD A,$42\n_Loop: DJNZ _Loop\n");
h.assemble("JR Later\nNOP\nLater:\n");
h.assemble("Unknown thing\n");
h.assemble("LD BC,A\n");
h.assemble("Low EQU -32768\nHigh EQU 65535\nCalc EQU ((2+3)*4)|1\nLD HL,Low\nLD DE,High\nLD A,Calc\n");
h.assemble("Alpha EQU Beta+1\nBeta EQU 16\n");

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
const integratedCode = codeThroughParser +
  extent("AtomOutputCodeStart", "AtomOutputCodeEnd") +
  extent("AtomStatementCodeStart", "AtomStatementCodeEnd");
const integratedWorkspace = workspaceThroughParser +
  extent("AtomOutputWorkspaceStart", "AtomOutputWorkspaceEnd") +
  extent("AtomStatementWorkspaceStart", "AtomStatementWorkspaceEnd");

console.log(JSON.stringify({
  labels: {
    componentsAndExecution: "Measured in the linked Phase 2g proof image.",
  },
  components: {
    symbolCodeAndTables: extent("AtomSymbolCodeStart", "AtomSymbolCodeEnd"),
    globalLabelTransactionIncrement: extent("AtomSymbolCodeStart", "AtomSymbolCodeEnd") - 723,
    parserCodeAndTables: extent("AtomParserCodeStart", "AtomParserCodeEnd"),
    parserWorkspace: extent("AtomParserWorkspaceStart", "AtomParserWorkspaceEnd"),
    statementContinuationIncrement: extent("AtomParserCodeStart", "AtomParserCodeEnd") - 2035,
    outputCode: extent("AtomOutputCodeStart", "AtomOutputCodeEnd"),
    outputWorkspace: extent("AtomOutputWorkspaceStart", "AtomOutputWorkspaceEnd"),
    statementDispatcherCode: extent("AtomStatementCodeStart", "AtomStatementCodeEnd"),
    statementDispatcherWorkspace: extent("AtomStatementWorkspaceStart", "AtomStatementWorkspaceEnd"),
    equAndDirectiveRecognitionCodeIncrement: extent("AtomStatementCodeStart", "AtomStatementCodeEnd") - 263,
    equWorkspaceIncrement: extent("AtomStatementWorkspaceStart", "AtomStatementWorkspaceEnd") - 22,
  },
  integrated: {
    codeAndTablesThroughParser: codeThroughParser,
    fixedWorkspaceThroughParser: workspaceThroughParser,
    codeAndTables: integratedCode,
    fixedWorkspace: integratedWorkspace,
    marginTo16KiBCodeAndTables: 0x4000 - integratedCode,
  },
  execution: h.statistics,
}, null, 2));
