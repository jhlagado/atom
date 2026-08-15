import { createExpressionHarness } from "./expression-support.mjs";

const h = await createExpressionHarness();
const values = [0, 1, 2, 7, 127, 128, 255, 256, 32767, 32768, 65534, 65535];
const concrete = new Set([
  "0", "65535", "-1", "-32768", "1+2*3", "(1+2)*3", "20-5-3",
  "100/5/2", "100%9", "-7/3", "-7%3", "1|2^3&6", "1<<5+2",
  "256>>4", "~1&$FF", "255*257", "65535/255", "$+2", "+(2+3)", "~~0",
]);
for (const left of values) {
  for (const right of values) {
    if (left + right <= 65535) concrete.add(`${left}+${right}`);
    if (left - right >= -32768) concrete.add(`${left}-${right}`);
    if (left * right <= 65535) concrete.add(`${left}*${right}`);
    if (right !== 0) {
      concrete.add(`${left}/${right}`);
      concrete.add(`${left} % ${right}`);
    }
    concrete.add(`${left}&${right}`);
    concrete.add(`${left}^${right}`);
    concrete.add(`${left}|${right}`);
  }
  for (const count of [0, 1, 7, 8, 15]) {
    if (left * 2 ** count <= 65535) concrete.add(`${left}<<${count}`);
    concrete.add(`${left}>>${count}`);
  }
}

const signedValues = [-32768, -255, -2, -1, 0, 1, 2, 255, 32767];
const signedConcrete = new Set();
for (const left of signedValues) {
  for (const right of signedValues) {
    for (const [operator, value] of [["+", left + right], ["-", left - right], ["*", left * right]]) {
      if (value >= -32768 && value <= 65535) signedConcrete.add(`(${left})${operator}(${right})`);
    }
    if (right !== 0) {
      signedConcrete.add(`(${left})/(${right})`);
      signedConcrete.add(`(${left}) % (${right})`);
    }
    for (const operator of ["&", "^", "|"]) signedConcrete.add(`(${left})${operator}(${right})`);
  }
  for (const count of [0, 1, 7, 15]) {
    const shifted = left * 2 ** count;
    if (shifted >= -32768 && shifted <= 65535) signedConcrete.add(`(${left})<<${count}`);
    signedConcrete.add(`(${left})>>${count}`);
  }
}
for (const source of signedConcrete) concrete.add(source);

for (const source of concrete) {
  h.reset();
  h.evaluate(source);
}
for (const source of [
  "1/0", "1 % 0", "1+", "(1+2", "65535+1", "-32769", "1<<24",
  "65535*65535", "1+$10000", `${"(".repeat(17)}1${")".repeat(17)}`,
]) {
  h.reset();
  h.evaluate(source);
}
h.reset();
h.declare("Base", 0x1234);
h.evaluate("bAsE+2");
h.evaluate("Forward+(2*3)");
const unresolved = h.evaluate("Target-3");
h.queue(unresolved.ix, -3, 0x4567, 2);

const s = h.symbols;
console.log(JSON.stringify({
  labels: "All byte, instruction, cycle, and corpus counts are Measured in the Phase 2d proof image.",
  coverage: {
    concreteAzmDifferentialCases: concrete.size,
    explicitFailureCases: 10,
    caseInsensitiveDefinedSymbolCases: 1,
    affineForwardSymbolCases: 2,
    pendingRecordHandoffs: 1,
  },
  expression: {
    ruleCode: s.AtomExpressionRuleCodeEnd - s.AtomExpressionCodeStart,
    immutableTables: s.AtomExpressionCodeEnd - s.AtomExpressionRuleCodeEnd,
    codeAndTables: s.AtomExpressionCodeEnd - s.AtomExpressionCodeStart,
    fixedWorkspace: s.AtomExpressionWorkspaceEnd - s.AtomExpressionWorkspaceStart,
    valueStack: s.AtomExpressionOperatorStack - s.AtomExpressionValueStack,
    operatorStack: s.AtomExpressionWorkspaceEnd - s.AtomExpressionOperatorStack,
  },
  integrated: {
    codeAndTables:
      (s.AtomEncoderCoreEnd - s.AtomEncoderCoreStart) +
      (s.AtomSymbolCodeEnd - s.AtomSymbolCodeStart) +
      (s.AtomTokenizerCodeEnd - s.AtomTokenizerCodeStart) +
      (s.AtomParserCodeEnd - s.AtomParserCodeStart) +
      (s.AtomExpressionCodeEnd - s.AtomExpressionCodeStart),
    fixedWorkspace:
      (s.AtomEncoderWorkspaceEnd - s.AtomEncoderWorkspaceStart) +
      (s.AtomSymbolWorkspaceEnd - s.AtomSymbolWorkspaceStart) +
      (s.AtomTokenizerWorkspaceEnd - s.AtomTokenizerWorkspaceStart) +
      (s.AtomParserWorkspaceEnd - s.AtomParserWorkspaceStart) +
      (s.AtomExpressionWorkspaceEnd - s.AtomExpressionWorkspaceStart),
  },
  execution: h.statistics,
}, null, 2));
