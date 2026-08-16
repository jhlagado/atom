# Atom flat object stream profile 0.2

Atom uses the NOBJ append-only record model but does not claim conformance with
Nucleus NOBJ 0.1. The Nucleus `MAP` describes compiler runtime vectors,
initialized storage, BSS, and stack layout. An assembler cannot infer those
properties from an arbitrary Z80 image. Atom therefore uses a distinct minor
version and flat map revision.

All integers wider than one byte are little-endian. Every record begins with a
one-byte kind and a two-byte payload length. The record order is:

```text
BEGIN IMAGE* PATCH* MAP COMMIT EOF
```

The kinds retain the Nucleus assignments: `BEGIN=$01`, `IMAGE=$02`,
`PATCH=$03`, `MAP=$04`, and `COMMIT=$05`.

## BEGIN

The 15-byte payload has the common NOBJ shape:

| Offset | Field | Type | Atom value |
| ---: | --- | --- | --- |
| 0 | magic | 4 bytes | ASCII `NOBJ` |
| 4 | major version | u8 | 0 |
| 5 | minor version | u8 | 2 |
| 6 | flags | u8 | 0, flat image |
| 7 | runtime identity | u16 | 0 |
| 9 | bank count | u8 | 1 |
| 10 | image fill | u8 | selected fill byte |
| 11 | image base | u16 | target start |
| 13 | image capacity | u16 | target capacity |

## IMAGE and PATCH

Both payloads begin with bank `u8`, address `u16`, and one or more bytes. Atom
uses bank zero. IMAGE records retain assembly order and have monotonically
increasing, non-overlapping extents. PATCH records contain final replacement
bytes and retain symbol-resolution order. A PATCH carries no symbol name or
relocation expression.

An assembly with no initialized byte may contain no IMAGE record. `usedLength`
still includes the highest `ORG` or uninitialized `DS` extent.

## Flat MAP

Atom MAP revision `$41` has this payload:

| Offset | Field | Type | Meaning |
| ---: | --- | --- | --- |
| 0 | map revision | u8 | `$41` |
| 1 | flags | u8 | 0 |
| 2 | entry bank | u8 | 0 |
| 3 | entry address | u16 | selected entry |
| 5 | used length | u16 | high-water mark minus image base |
| 7 | final cursor | u16 | cursor after the last statement |
| 9 | part count | u8 | number of source parts |
| 10 | part banks | u8[] | one zero for each part |

This map records placement and source-part order without inventing runtime
storage semantics. A future shared Debug80 object package can support the
Nucleus and Atom map profiles behind one framing and CRC implementation.

## COMMIT

The seven-byte payload contains total record count `u16`, entry bank `u8`,
entry address `u16`, and CRC `u16`. CRC-16/CCITT-FALSE uses polynomial `$1021`,
initial value `$FFFF`, no reflection, and no final XOR. It covers every byte
through the high byte of the COMMIT entry address and excludes the stored CRC.

`parseAtomNobj` validates framing, profile version, record order, record count,
map revision, and CRC before returning metadata.
