// Build the checker's model of a program: its statements with their effects,
// the contract each routine declares, and where every jump and call goes.
//
// A ;@ROUTINE line gives the contract of the next label, global or local:
//   ;@ROUTINE IN A,HL OUT A,CARRY MAYBE-OUT DE CLOBBERS BC,ZERO
// IN lists what the routine reads, OUT what it returns, MAYBE-OUT what it
// returns on some paths, FAIL-OUT what it returns with carry set, and
// CLOBBERS what it may change. Every other unit is kept. A camelCase name is
// a memory variable, recorded but not checked.
// A ;@SERVICE line has the same form. It is the contract of a host service
// entry: callers rely on it, but the entry's own body is a replaceable stub,
// so it is not checked against it.
// A ;@EXPECTOUT line before a CALL names outputs the caller relies on.
// A ;@DISPATCH line before a jump names the table of DW labels it reaches.
// On JP (HL) the jump goes to one of them. On a jump to a routine, that
// routine selects one of them after doing what its contract says. With no
// table, the caller supplies it, so the indirect jump is not followed.
// ;@DISPATCH TO a,b names the labels directly, for a jump made by RET.

import { contractUnits, effects } from "./effects.mjs";
import { readProgram } from "./source.mjs";

const SECTIONS = new Set(["IN", "OUT", "MAYBE-OUT", "FAIL-OUT", "CLOBBERS"]);

// Parse the words after ;@ROUTINE into sets of units.
export function parseContract(text, where) {
  const contract = { in: new Set(), out: new Set(), maybe: new Set(), fail: new Set(), clobbers: new Set(), memory: [] };
  const key = { IN: "in", OUT: "out", "MAYBE-OUT": "maybe", "FAIL-OUT": "fail", CLOBBERS: "clobbers" };
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
  return new Set([...contract.out, ...contract.maybe, ...(contract.fail ?? []), ...contract.clobbers]);
}

export function buildProgram(root) {
  const statements = readProgram(root);
  const globals = new Map();
  const locals = new Map();
  let scope = null;
  let pendingContract = null;
  let pendingExpect = null;
  let pendingDispatch = null;

  statements.forEach((s, index) => {
    const where = `${s.file}:${s.line}`;
    if (s.note) {
      const [kind, ...rest] = s.note.split(/\s+/);
      if (kind.toUpperCase() === "ROUTINE" || kind.toUpperCase() === "SERVICE") {
        pendingContract = parseContract(rest.join(" "), where);
        pendingContract.service = kind.toUpperCase() === "SERVICE";
      }
      if (kind.toUpperCase() === "EXPECTOUT") pendingExpect = parseContract(`OUT ${rest.join(" ")}`, where).out;
      if (kind.toUpperCase() === "DISPATCH") {
        pendingDispatch = rest[0]?.toUpperCase() === "TO"
          ? { labels: rest.slice(1).join("").split(",").filter(Boolean) }
          : { table: rest[0] ?? null };
      }
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
      s.contract = pendingContract;
      pendingContract = null;
    }
    s.scope = scope;
    if (s.op && s.op !== "EQU") {
      s.effect = effects(s.op, s.args);
      if (pendingExpect) s.expect = pendingExpect;
      if (pendingDispatch) s.dispatch = pendingDispatch;
      pendingExpect = null;
      pendingDispatch = null;
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

  const routines = [...globals.values(), ...locals.values()]
    .filter((index) => statements[index].contract && statements[index].op !== "EQU" && !statements[index].contract.service)
    .sort((a, b) => a - b)
    .map((index) => {
      const s = statements[index];
      const name = s.global ? s.label : `${s.scope}${s.label}`;
      return { name, index, contract: s.contract, at: `${s.file}:${s.line}` };
    });

  // The labels a dispatch table lists: its DW lines, up to the next label or
  // instruction.
  const table = (s, name) => {
    const start = resolve(s, name);
    if (start == null) return null;
    const targets = [];
    for (let index = start; index < statements.length; index += 1) {
      const t = statements[index];
      if (index > start && (t.label || (t.op && t.op !== "DW"))) break;
      if (t.op === "DW") targets.push(...t.args.map((arg) => resolve(t, arg)));
      else if (t.op) break;
    }
    return targets;
  };

  statements.forEach((s, index) => {
    if (s.dispatch?.table) {
      s.dispatch.targets = table(s, s.dispatch.table);
      if (!s.dispatch.targets) throw new Error(`${s.file}:${s.line}: dispatch table ${s.dispatch.table} has no label`);
    }
    if (s.dispatch?.labels) {
      s.dispatch.targets = s.dispatch.labels.map((label) => resolve(s, label));
      if (s.dispatch.targets.includes(null)) throw new Error(`${s.file}:${s.line}: a dispatch label is undefined`);
    }
    s.index = index;
  });

  return { statements, globals, routines };
}
