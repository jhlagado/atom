// Build the checker's model of a program: its statements with their effects,
// the contract each routine declares, and where every jump and call goes.
//
// A ;@ROUTINE line gives the contract of the next global label:
//   ;@ROUTINE IN A,HL OUT A,CARRY MAYBE-OUT DE CLOBBERS BC,ZERO
// IN lists what the routine reads, OUT what it returns, MAYBE-OUT what it
// returns on some paths, and CLOBBERS what it may change. Every other unit is
// kept. A camelCase name is a memory variable, recorded but not checked.
// A ;@EXPECTOUT line before a CALL names outputs the caller relies on.

import { contractUnits, effects } from "./effects.mjs";
import { readProgram } from "./source.mjs";

const SECTIONS = new Set(["IN", "OUT", "MAYBE-OUT", "CLOBBERS"]);

// Parse the words after ;@ROUTINE into sets of units.
export function parseContract(text, where) {
  const contract = { in: new Set(), out: new Set(), maybe: new Set(), clobbers: new Set(), memory: [] };
  const key = { IN: "in", OUT: "out", "MAYBE-OUT": "maybe", CLOBBERS: "clobbers" };
  let section = null;
  for (const word of text.split(/\s+/).filter(Boolean)) {
    const upper = word.toUpperCase();
    if (SECTIONS.has(upper)) {
      section = key[upper];
      continue;
    }
    if (!section) throw new Error(`${where}: contract word ${word} has no section`);
    for (const name of word.split(",").filter(Boolean)) {
      const units = contractUnits(name);
      if (!units && /^[a-z]/.test(name)) {
        contract.memory.push(name);
        continue;
      }
      if (!units) throw new Error(`${where}: unknown contract unit ${name}`);
      units.forEach((unit) => contract[section].add(unit));
    }
  }
  return contract;
}

// Every unit the routine may change: outputs as well as clobbers.
export function changes(contract) {
  return new Set([...contract.out, ...contract.maybe, ...contract.clobbers]);
}

export function buildProgram(root) {
  const statements = readProgram(root);
  const globals = new Map();
  const locals = new Map();
  let scope = null;
  let pendingContract = null;
  let pendingExpect = null;

  statements.forEach((s, index) => {
    const where = `${s.file}:${s.line}`;
    if (s.note) {
      const [kind, ...rest] = s.note.split(/\s+/);
      if (kind.toUpperCase() === "ROUTINE") pendingContract = parseContract(rest.join(" "), where);
      if (kind.toUpperCase() === "EXPECTOUT") pendingExpect = parseContract(`OUT ${rest.join(" ")}`, where).out;
      return;
    }
    if (s.label && s.global) {
      // A second label on the same address shares the first one's contract.
      const alias = scope && !pendingContract && statements[globals.get(scope.toUpperCase())];
      const shared = alias && !statements.slice(globals.get(scope.toUpperCase()), index).some((t) => t.op);
      scope = s.label;
      globals.set(s.label.toUpperCase(), index);
      s.contract = pendingContract ?? (shared ? alias.contract : null);
      pendingContract = null;
    } else if (s.label && s.op === "EQU") {
      globals.set(s.label.toUpperCase(), index);
      s.contract = pendingContract;
      pendingContract = null;
    } else if (s.label) {
      locals.set(`${scope}${s.label}`.toUpperCase(), index);
    }
    s.scope = scope;
    if (s.op && s.op !== "EQU") {
      s.effect = effects(s.op, s.args);
      if (pendingExpect) s.expect = pendingExpect;
      pendingExpect = null;
    }
  });

  // Resolve a jump or call target to a statement index, or null for an
  // address the program does not label.
  const resolve = (s, target) => {
    const name = target.trim().toUpperCase();
    const index = name.startsWith(".") ? locals.get(`${s.scope}${name}`.toUpperCase()) : globals.get(name);
    return index ?? null;
  };

  statements.forEach((s) => {
    if (s.effect?.target) s.to = resolve(s, s.effect.target);
  });

  const routines = [...globals.values()]
    .filter((index) => statements[index].contract && statements[index].op !== "EQU")
    .map((index) => {
      const s = statements[index];
      return { name: s.label, index, contract: s.contract, at: `${s.file}:${s.line}` };
    });

  return { statements, globals, routines };
}
