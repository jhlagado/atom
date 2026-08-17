import { createSymbolHarness } from "./symbol-support.mjs";

const h = await createSymbolHarness();

function key(name) {
  return h.pack(name).key;
}

// Longest spelling.
h.reset();
key(".ABCDEFGH");

// Eight-record global scan and exact-capacity rejection.
h.reset();
for (let index = 0; index < 8; index += 1) h.declare(key(`G${index}`), 0x4000 + index);
h.find(key("MISSING"));
h.reference(key("FORWARD"));
h.declare(key("OVERFLOW"), 0x5000);

// Eight-record private eviction scan.
h.reset();
h.advanceScope();
for (let index = 0; index < 8; index += 1) h.declare(key(`_L${index}`), 0x6000 + index);
h.advanceScope();

// Four-record pending scan and capacity rejection.
h.reset();
const first = h.reference(key("FIRST"));
const second = h.reference(key("SECOND"));
h.pendingAdd(first.ix, 0x7000, 1, 0);
h.pendingAdd(first.ix, 0x7001, 1, 1);
h.pendingAdd(first.ix, 0x7002, 1, 2);
h.pendingAdd(second.ix, 0x7003, 2, 3);
h.pendingAdd(second.ix, 0x7004, 2, 4);
h.pendingTake(second.ix);

// Atomic global-label transaction through a populated private scope.
h.reset({ symbolBytes: 16 });
h.advanceScope();
const local = h.reference(key(".LATER"));
h.declareGlobalLabel(key("NEXT"), 0x7100);
h.declare(key(".LATER"), 0x7101);
h.declareGlobalLabel(key("NEXT"), 0x7100);

// Non-destructive pending inspection and exact-capacity preflight.
h.reset({ pendingBytes: 6 });
const peeked = h.reference(key("PEEK"));
h.pendingCheckCapacity();
h.pendingAdd(peeked.ix, 0x7200, 5, 0x7a);
h.pendingPeek(peeked.ix);
h.pendingCheckCapacity();

const s = h.symbols;
console.log(JSON.stringify({
  labels: "All byte, instruction, and cycle counts are Measured for the fixed proof capacities.",
  resident: {
    code: s.AtomSymbolCodeEnd - s.AtomSymbolCodeStart,
    fixedWorkspace: s.AtomSymbolWorkspaceEnd - s.AtomSymbolWorkspaceStart,
  },
  records: { symbol: s.AtomSymbolRecordBytes, pending: s.AtomPendingRecordBytes },
  proofCapacity: { symbols: 8, pending: 4 },
  execution: h.statistics,
}, null, 2));
