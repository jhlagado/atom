import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";

import { bootMachine, createDisk } from "@jhlagado/triptych-headless";

// Atom must build itself on CP/M from the files in src/z80, exactly as they
// are. The sources need more than a floppy, so this runs on a Triptych 2 MB
// disk, and the result must match the ATOM.COM that Node builds.
test("ATOM.COM builds itself on CP/M", async (t) => {
  const atomCom = await readFile("assets/atom-cpm22.com");
  const names = (await readdir("src/z80")).filter((name) => name.endsWith(".asm"));
  const files = [["ATOM.COM", atomCom]];
  for (const name of names) files.push([name.toUpperCase(), await readFile(`src/z80/${name}`)]);

  const machine = bootMachine([createDisk(files).image()]);
  t.after(() => machine.close());
  // Count what the same disk activity would cost on a 3.5-inch drive.
  machine.setDiskTiming({ profile: "3in-dsdd" });
  const start = machine.tstates();
  const reply = machine.run("ATOM CPM22 NEWATOM.COM");
  assert.match(reply, /NEWATOM\.COM written/, reply);

  const built = machine.disk(0).readFile("NEWATOM.COM");
  // CP/M stores whole 128-byte records, so the file ends in padding.
  assert.equal(built.length, Math.ceil(atomCom.length / 128) * 128);
  assert.deepEqual(Buffer.from(built.subarray(0, atomCom.length)), atomCom);
  const tstates = machine.tstates() - start;
  const disk = machine.diskTimingReport();
  t.diagnostic(`${names.length} source files, ${(tstates / 1e9).toFixed(2)} billion T-states, ${(tstates / 4e6 / 60).toFixed(1)} minutes at 4 MHz`);
  t.diagnostic(`3.5-inch disk time ${(disk.diskMs / 60000).toFixed(1)} minutes: ${disk.recordReads} record reads, ${disk.recordWrites} writes, ${disk.seeks} seeks`);
});
