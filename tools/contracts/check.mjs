// Check every routine against its ;@ROUTINE contract.
//
// Two analyses run over each routine's control flow.
//
// The forward analysis follows what each unit holds: its value on entry, a
// copy of another unit's entry value, or something written at a known line.
// Copies, PUSH and POP, EX and simple memory cells all carry values, so a
// register saved in another register and copied back counts as kept. At every
// exit, a unit that no longer holds its entry value must be one the contract
// lets the routine change.
//
// The backward analysis finds which units are still needed at each point. A
// CALL that clobbers a unit the caller still needs is a conflict, and a unit
// needed on entry that is not an input is an undeclared input.
//
// Atom reports failure with carry set. On a path that returns with carry set
// only CARRY is an output; the others are meaningless there, so they need not
// survive to that exit.
//
// A call to a label with no contract, such as a private subroutine, uses a
// summary inferred from its body: what it reads first and what it may change.

import { FLAGS, UNITS } from "./effects.mjs";
import { buildProgram, changes } from "./program.mjs";

const ORIGINAL = (unit) => `=${unit}`;
const NAMES = { CF: "CARRY", ZF: "ZERO", SF: "SIGN", PF: "PARITY", HF: "HALFCARRY", IXH: "IX", IXL: "IX", IYH: "IY", IYL: "IY" };
const FAILURE_OUT = new Set(["CF"]);
const EVERYTHING = { in: new Set(), out: new Set(), maybe: new Set(UNITS), clobbers: new Set(), memory: [] };

// Name units the way contracts write them.
export function unitNames(units) {
  return [...new Set([...units].map((u) => NAMES[u] ?? u))].join(",");
}

const where = (s) => `${s.file}:${s.line}`;
const expand = (units) => units.flatMap((u) => (u === "F" ? FLAGS : [u]));
const locsOf = (value) => (value.startsWith("w:") ? value.slice(2).split(" ") : []);
const cellKey = (text) => text.toUpperCase().replace(/\s+/g, "");

// Join two values that reach the same statement by different paths.
function joinValue(a, b, at) {
  if (a === b) return a;
  const locs = new Set([...locsOf(a), ...locsOf(b)]);
  if (!locs.size) locs.add(at);
  return `w:${[...locs].sort().join(" ")}`;
}

function entryState() {
  const v = {};
  for (const unit of UNITS) v[unit] = ORIGINAL(unit);
  return { v, stack: [], mem: new Map(), carry: null };
}

const cloneState = (s) => ({
  v: { ...s.v },
  stack: s.stack && s.stack.map((e) => ({ ...e })),
  mem: new Map(s.mem),
  carry: s.carry,
});

function joinState(a, b, at) {
  const v = {};
  for (const unit of UNITS) v[unit] = joinValue(a.v[unit], b.v[unit], at);
  let stack = null;
  if (a.stack && b.stack && a.stack.length === b.stack.length) {
    stack = a.stack.map((e, i) => {
      const f = b.stack[i];
      if (e.units.join() !== f.units.join()) return { units: e.units, vals: e.units.map(() => `w:${at}`) };
      return { units: e.units, vals: e.vals.map((x, j) => joinValue(x, f.vals[j], at)) };
    });
  }
  const mem = new Map();
  for (const [key, vals] of a.mem) if (b.mem.get(key)?.join() === vals.join()) mem.set(key, vals);
  return { v, stack, mem, carry: a.carry === b.carry ? a.carry : null };
}

const sameState = (a, b) =>
  a.carry === b.carry &&
  UNITS.every((u) => a.v[u] === b.v[u]) &&
  JSON.stringify(a.stack) === JSON.stringify(b.stack) &&
  JSON.stringify([...a.mem]) === JSON.stringify([...b.mem]);

// Run one statement forward. Returns the state after it.
function step(s, state, report) {
  const at = where(s);
  const e = s.effect;
  const pre = state.v;
  const out = cloneState(state);
  if (!e) return out;
  for (const unit of e.writes) out.v[unit] = `w:${at}`;
  for (const [to, from] of e.moves) out.v[to] = pre[from];
  if (e.push) {
    const units = expand(e.push);
    out.stack?.push({ units, vals: units.map((u) => pre[u]) });
  }
  if (e.pop) {
    const units = expand(e.pop);
    const entry = out.stack ? out.stack.pop() : null;
    if (out.stack && !entry) {
      report("stack", "POP below the routine's entry stack");
      out.stack = null;
    }
    if (entry && entry.units.length === units.length) units.forEach((u, i) => (out.v[u] = entry.vals[i]));
  }
  if (e.exTop && out.stack?.length) {
    const top = out.stack[out.stack.length - 1];
    if (top.units.length === e.exTop.length) {
      e.exTop.forEach((u, i) => (out.v[u] = top.vals[i]));
      top.vals = e.exTop.map((u) => pre[u]);
    }
  }
  if (e.store) out.mem.set(cellKey(e.store[0]), e.store[1].map((u) => pre[u]));
  if (e.load) {
    const vals = state.mem.get(cellKey(e.load[0]));
    if (vals?.length === e.load[1].length) e.load[1].forEach((u, i) => (out.v[u] = vals[i]));
  }
  if (e.stack === "unknown") out.stack = null;
  if (e.stack === "fresh") out.stack = [];
  if (e.writes.includes("CF")) out.carry = carryAfter(s, state.carry);
  return out;
}

// The carry flag after an instruction that writes it, when it is known.
function carryAfter(s, before) {
  if (s.op === "SCF") return 1;
  if (s.op === "CCF") return before == null ? null : 1 - before;
  if (["AND", "OR", "XOR"].includes(s.op)) return 0;
  if ((s.op === "SUB" || s.op === "CP") && s.args.length === 1 && s.args[0].toUpperCase() === "A") return 0;
  return null;
}

// The state on one side of a conditional on carry.
function onCarry(state, cond, taken) {
  if (cond !== "C" && cond !== "NC") return state;
  const out = cloneState(state);
  out.carry = (cond === "C") === taken ? 1 : 0;
  return out;
}

export function checkProgram(root) {
  const program = buildProgram(root);
  const { statements } = program;
  const findings = [];
  const seen = new Set();
  const inferred = new Map();

  // The contract a call or tail to this statement relies on.
  const contractAt = (index) => {
    if (index == null) return null;
    const s = statements[index];
    if (s.contract) return s.contract;
    if (s.op === "EQU") return null;
    return infer(index);
  };

  // Infer a summary for a label with no contract: the units it reads before
  // writing, and every unit it may change, as a possible output.
  const infer = (index) => {
    if (inferred.has(index)) return inferred.get(index) ?? EVERYTHING;
    inferred.set(index, null);
    const s = statements[index];
    const result = analyse({ name: s.label, index, contract: EVERYTHING, inferred: true });
    const maybe = new Set([...result.changed].filter((u) => !result.always.has(u)));
    const summary = { in: result.inputs, out: result.always, maybe, clobbers: new Set(), memory: [] };
    inferred.set(index, summary);
    return summary;
  };

  // Apply a callee's contract: every unit it may change gets a new value.
  const applyCall = (state, contract, at) => {
    for (const unit of contract ? changes(contract) : UNITS) state.v[unit] = `w:${at}`;
    state.mem = new Map();
    state.carry = null;
  };

  function analyse(routine) {
    const changed = new Set();
    let always = null;
    const states = new Map([[routine.index, entryState()]]);
    const work = [routine.index];
    const succ = new Map();
    const exits = new Map();
    let reporting = false;

    const add = (kind, s, message) => {
      if (!reporting) return;
      if (routine.inferred && kind !== "conflict" && kind !== "expect") return;
      const key = `${kind} ${where(s)} ${message}`;
      if (seen.has(key)) return;
      seen.add(key);
      findings.push({ kind, at: where(s), routine: routine.name, message });
    };

    // Check the state at an exit against the contract.
    const checkExit = (s, state, how) => {
      if (!reporting) return;
      const allowed = changes(routine.contract);
      const bad = new Map();
      const here = UNITS.filter((u) => state.v[u] !== ORIGINAL(u));
      always = new Set(always ? here.filter((u) => always.has(u)) : here);
      for (const unit of UNITS) {
        if (state.v[unit] === ORIGINAL(unit)) continue;
        changed.add(unit);
        if (allowed.has(unit)) continue;
        const locs = locsOf(state.v[unit]);
        const name = NAMES[unit] ?? unit;
        if (!bad.has(name)) bad.set(name, new Set());
        for (const loc of locs.length ? locs : [`a copy of ${state.v[unit].slice(1)}`]) bad.get(name).add(loc);
      }
      if (bad.size) {
        const names = [...bad.keys()].join(",");
        const locs = [...new Set([...bad.values()].flatMap((l) => [...l]))].join(", ");
        add("changes", s, `${how} with ${names} changed (${locs}), which the contract keeps`);
      }
      if (state.stack?.length) add("stack", s, `${how} with ${state.stack.length} word(s) still pushed`);
    };

    // An edge of the routine's flow graph. Reaching another contracted
    // routine's label is a tail call, which ends this routine.
    const flowTo = (from, to, state, how) => {
      if (to == null || to >= statements.length) return;
      const target = statements[to];
      if (to !== routine.index && target.global && target.contract) {
        const tail = cloneState(state);
        applyCall(tail, target.contract, where(statements[from]));
        checkExit(statements[from], tail, `${how} to ${target.label}`);
        exits.set(from, { kind: "tail", to, failure: state.carry === 1 });
        return;
      }
      succ.get(from).push(to);
      if (reporting) return;
      const old = states.get(to);
      const next = old ? joinState(old, state, where(target)) : state;
      if (!old || !sameState(old, next)) {
        states.set(to, next);
        work.push(to);
      }
    };

    // Follow one statement's effect and its edges.
    const visit = (index) => {
      const s = statements[index];
      const e = s.effect;
      const report = (kind, message) => add(kind, s, message);
      succ.set(index, []);
      const after = step(s, states.get(index), report);
      if (!e) {
        flowTo(index, index + 1, after, "falls");
        return;
      }
      switch (e.flow) {
        case "next":
          flowTo(index, index + 1, after, "falls");
          break;
        case "stop":
          report("flow", `runs into data (${s.op})`);
          break;
        case "jump":
        case "branch":
          if (s.to == null) {
            exits.set(index, { kind: "away" });
            if (!/^\$?0+$/.test(e.target)) report("flow", `jumps to ${e.target}, which has no label`);
          } else {
            flowTo(index, s.to, onCarry(after, e.cond, true), e.flow === "jump" ? "jumps" : "branches");
          }
          if (e.flow === "branch") flowTo(index, index + 1, onCarry(after, e.cond, false), "falls");
          break;
        case "call":
        case "callIf": {
          const contract = contractAt(s.to);
          if (!contract) report("callee", `calls ${e.target}, which has no contract`);
          if (s.expect && contract) {
            const missing = [...s.expect].filter((u) => !contract.out.has(u) && !contract.maybe.has(u));
            if (missing.length) report("expect", `expects ${unitNames(missing)} from ${e.target}, which does not return it`);
          }
          const called = cloneState(after);
          applyCall(called, contract, where(s));
          flowTo(index, index + 1, e.flow === "call" ? called : joinState(after, called, where(s)), "falls");
          break;
        }
        case "ret":
          checkExit(s, after, "returns");
          exits.set(index, { kind: "ret", failure: after.carry === 1 });
          break;
        case "retIf": {
          const leaving = onCarry(after, e.cond, true);
          checkExit(s, leaving, "returns");
          exits.set(index, { kind: "ret", failure: leaving.carry === 1 });
          flowTo(index, index + 1, onCarry(after, e.cond, false), "falls");
          break;
        }
        case "indirect":
          report("flow", "jumps through a register, which the checker cannot follow");
          exits.set(index, { kind: "away" });
          break;
      }
    };

    // Settle every statement's state, then visit each once more to report.
    while (work.length) visit(work.pop());
    reporting = true;
    for (const index of states.keys()) visit(index);

    // Backward liveness over the same graph.
    const contract = routine.contract;
    const exitLive = routine.inferred ? new Set() : new Set([...contract.out, ...contract.maybe]);
    const depth = (index) => states.get(index)?.stack?.length ?? null;
    const live = new Map();
    const order = [...states.keys()].sort((a, b) => b - a);
    const conflicts = new Map();
    let moving = true;
    while (moving) {
      moving = false;
      for (const index of order) {
        const s = statements[index];
        const e = s.effect;
        const after = new Set();
        for (const to of succ.get(index) ?? []) for (const u of live.get(to) ?? []) after.add(u);
        const exit = exits.get(index);
        if (exit?.kind === "ret" || exit?.kind === "away") {
          for (const u of exitLive) if (!exit.failure || FAILURE_OUT.has(u)) after.add(u);
        }
        const before = new Set(after);
        if (exit?.kind === "tail") {
          const callee = statements[exit.to].contract;
          const needed = [...exitLive].filter((u) => !exit.failure || FAILURE_OUT.has(u));
          const lost = needed.filter((u) => callee.clobbers.has(u) && !callee.out.has(u));
          if (lost.length) conflicts.set(where(s), { s, units: lost, callee: statements[exit.to].label });
          for (const u of needed) if (!callee.out.has(u)) before.add(u);
          for (const u of callee.in) before.add(u);
        }
        if (e) {
          if (e.flow === "call" || e.flow === "callIf") {
            const callee = contractAt(s.to);
            if (callee) {
              const lost = [...after].filter((u) => callee.clobbers.has(u) && !callee.out.has(u) && !callee.maybe.has(u));
              if (lost.length) conflicts.set(where(s), { s, units: lost, callee: e.target });
              if (e.flow === "call") for (const u of callee.out) before.delete(u);
              for (const u of callee.in) before.add(u);
            }
          }
          const d = depth(index);
          if (e.push && d != null) {
            const units = expand(e.push);
            const slots = units.map((_, i) => `s${d}.${i}`);
            slots.forEach((slot) => before.delete(slot));
            units.forEach((u, i) => after.has(slots[i]) && before.add(u));
          } else if (e.pop && d != null && d > 0) {
            const units = expand(e.pop);
            units.forEach((u) => before.delete(u));
            units.forEach((u, i) => after.has(u) && before.add(`s${d - 1}.${i}`));
          } else if (e.exTop && d != null && d > 0) {
            const slots = e.exTop.map((_, i) => `s${d - 1}.${i}`);
            [...e.exTop, ...slots].forEach((u) => before.delete(u));
            e.exTop.forEach((u, i) => {
              if (after.has(u)) before.add(slots[i]);
              if (after.has(slots[i])) before.add(u);
            });
          } else {
            for (const u of e.writes) before.delete(u);
          }
          // An instruction with no effect beyond its registers needs its
          // operands only when a result that depends on them is still needed.
          const pure = e.flow === "next" && !e.memWrite && !e.push && !e.pop && !e.exTop && e.writes.length;
          const constant = new Set(e.constant ?? []);
          const needed = !pure || e.writes.some((u) => after.has(u) && !constant.has(u));
          // A plain copy or exchange reads a source only if its destination
          // is still needed.
          const copies = pure && e.moves.length && e.writes.every((u) => e.moves.some(([to]) => to === u));
          if (copies) {
            for (const [to, from] of e.moves) if (after.has(to)) before.add(from);
          } else if (needed && (!e.push || d == null)) {
            for (const u of e.reads) before.add(u);
          }
        }
        const old = live.get(index);
        if (!old || old.size !== before.size || [...before].some((u) => !old.has(u))) {
          live.set(index, before);
          moving = true;
        }
      }
    }
    for (const { s, units, callee } of conflicts.values()) {
      add("conflict", s, `needs ${unitNames(units)} after ${callee}, which clobbers it`);
    }
    const inputs = new Set([...(live.get(routine.index) ?? [])].filter((u) => UNITS.includes(u)));
    const undeclared = [...inputs].filter((u) => !contract.in.has(u) && !contract.maybe.has(u));
    const firstRead = new Map();
    for (const index of [...states.keys()].sort((a, b) => a - b)) {
      const s = statements[index];
      const callee = s.effect && /call/.test(s.effect.flow) ? contractAt(s.to) : null;
      for (const u of undeclared) {
        if (firstRead.has(u) || !live.get(index)?.has(u)) continue;
        if (s.effect?.reads.includes(u) || callee?.in.has(u)) firstRead.set(u, where(s));
      }
    }
    const read = undeclared.filter((u) => firstRead.has(u));
    const through = undeclared.filter((u) => !firstRead.has(u));
    if (read.length) {
      const at = [...new Set(read.map((u) => firstRead.get(u)))].join(", ");
      add("input", statements[routine.index], `reads ${unitNames(read)} before writing (${at}), but its contract has no such input`);
    }
    if (through.length) {
      add("partial", statements[routine.index], `can return without setting ${unitNames(through)}, so it may be MAYBE-OUT`);
    }
    return { changed, always: always ?? new Set(), inputs };
  }

  // Contracts that allow more than the routine does.
  const loose = [];
  for (const routine of program.routines) {
    const { changed } = analyse(routine);
    const unused = [...changes(routine.contract)].filter((u) => !changed.has(u) && !routine.contract.out.has(u));
    if (unused.length) loose.push({ kind: "loose", at: routine.at, routine: routine.name, message: `may change ${unitNames(unused)} but never does` });
  }
  return { findings, loose, routines: program.routines.length };
}
