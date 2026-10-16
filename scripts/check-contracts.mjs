#!/usr/bin/env node
// Check Atom's ;@ROUTINE register contracts against the code.
//
//   node scripts/check-contracts.mjs [--loose] [--json] [--strict] [root.asm ...]
//
// With no roots it checks every build: ATOM.COM, the Node core and the
// named-object harness. Shared files are reported once. --loose adds
// contracts that allow more than the routine does. --strict exits with
// status 1 when anything is reported.

import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { checkProgram } from "../tools/contracts/check.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, "..", "src", "z80");
const ROOTS = ["cpm22.asm", "atom.asm", "nobj.asm"];

const KINDS = [
  ["changes", "Changes a unit its contract keeps"],
  ["conflict", "Needs a unit across a call that clobbers it"],
  ["input", "Reads a unit that is not an input"],
  ["expect", "Expects an output the callee does not return"],
  ["stack", "Leaves the stack unbalanced"],
  ["callee", "Calls a routine with no contract"],
  ["flow", "Control flow the checker cannot follow"],
  ["partial", "Returns an output only on some paths"],
  ["loose", "Allows more than the routine does"],
];

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const roots = args.filter((a) => !a.startsWith("--"));
const files = roots.length ? roots : ROOTS.map((name) => join(source, name));

const seen = new Set();
const report = [];
let routines = 0;
for (const file of files) {
  const result = checkProgram(file);
  routines += result.routines;
  for (const finding of [...result.findings, ...(flag("--loose") ? result.loose : [])]) {
    const key = `${finding.kind} ${finding.at} ${finding.message}`;
    if (seen.has(key)) continue;
    seen.add(key);
    report.push(finding);
  }
}

if (flag("--json")) {
  console.log(JSON.stringify(report, null, 2));
} else {
  for (const [kind, title] of KINDS) {
    const found = report.filter((f) => f.kind === kind);
    if (!found.length) continue;
    console.log(`\n${title} (${found.length})`);
    for (const f of found) console.log(`  ${f.at}: ${f.routine}: ${f.message}`);
  }
  console.log(`\n${report.length} findings across ${files.length} build(s).`);
}
process.exitCode = flag("--strict") && report.length ? 1 : 0;
