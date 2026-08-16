# Atom Phase 4 Mac host integration report

## Result

**Measured: pass.** A Mac host can now resolve and preprocess an Atom project,
load its ordered masked parts into Debug80, and run the native Z80 assembler to
one committed logical image/patch generation. The native core still performs
tokenization, symbol handling, directive processing, instruction encoding,
forward-patch decisions, final undefined checks, and lifecycle control.

The integration proof uses two physical source parts. Its entry defines a host
condition, includes a dependency, selects origin `$4000`, and contains
case-insensitive instructions, a forward private branch, a string and binary
`DB`, a `DW`, and filled `DS`. The native result contains ten IMAGE bytes, one
mid-stream PATCH byte, and the expected final cursor. A second fresh run has
identical operations, bytes, instruction count, cycle count, and service trace.

## Resident account

Phase 3 measured 12,484 code/table bytes and 550 fixed workspace bytes. The Mac
image adds six four-byte fail-closed service stubs.

| Native account | Classification | Bytes |
| --- | --- | ---: |
| Phase 3 assembler and driver | Measured | 12,484 |
| Six host service stubs | Measured | 24 |
| **Code and immutable tables** | **Measured** | **12,508** |
| Fixed workspace | Measured | 550 |
| **Linked resident extent** | **Measured** | **13,058** |

The code/table margin below 16 KiB is **Measured: 3,876 bytes**. Because the
current link places fixed workspace between code components, the physical
linked extent is the stricter Mac-image account. Its margin below `$4000` is
**Measured: 3,326 bytes**.

The service stubs belong to the Mac link and fail with `$FF` if Debug80 does not
intercept them. They do not estimate the eventual TEC operating adapter.

## Caller-owned host RAM

| Allocation | Classification | Bytes | Capacity |
| --- | --- | ---: | ---: |
| Maximum build plus 16 part descriptors | Measured | 95 | 16 parts |
| Source window | Measured | 24,576 | 24 KiB source |
| Symbol arena | Measured | 13,312 | 1,664 records |
| Pending arena | Measured | 2,560 | 426 complete records |
| Proof stack | Measured | 256 | one bounded call stack |

The complete Phase 4 proof map covers all 65,536 addresses without a gap or
overlap. Source and descriptor bytes remain unchanged, code/table ranges are
read-only in Debug80, and two-sided stack canaries survive every completed
call. The TEC-1 map remains deployment work; these host allocations prove the
interface at useful capacities without claiming that the same simultaneous
RAM layout fits the target machine.

## Execution measurement

The named two-part integration case executes **Measured: 28,092 Z80
instructions and 278,219 T-states**, about **Measured: 69.6 ms at 4 MHz**. It
makes thirteen intercepted service calls: begin, ten IMAGE operations, one
PATCH, and commit. Host service work has no Z80 cycle charge in this account.

## Failure and diagnostic evidence

The proofs distinguish source, output, runtime, and internal failures. A final
undefined name reports its unpacked name, logical file, part ordinal, byte
offset, line, and column after host directive masking. A syntax error in an
included source names the included file.

An injected sink status and a thrown JavaScript service both return through the
native failure path and end with one abort. A runtime budget failure aborts an
already open host generation. Descending IMAGE output, a duplicate or invalid
PATCH target, a nonzero bank, and an intermediate or final logical extent
outside the target range all fail before a generation reaches the caller. The
host retains an earlier uninitialized `DS` high-water mark when a later `ORG`
moves the final cursor backward.

## Remaining work

The API returns a committed logical generation in memory. Phase 5 must add a
pinned distributable native image, an installable command, deterministic NOBJ,
binary, Intel HEX, listing, and D8 rendering, and atomic multi-artifact
publication. Atom-to-AZM source translation and native self-assembly remain
Phase 6 work.

## Reproduction

```sh
npm run annotate:contracts
npm run test:host
npm test
npm run measure:driver
npm run measure:host-native
```
