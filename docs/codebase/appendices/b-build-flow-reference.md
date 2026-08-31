# Appendix B — Build-flow reference

[← Directory and file reference](a-directory-and-file-reference.md) | [Public surface and ABI reference →](c-public-surface-and-abi-reference.md)

This appendix condenses the complete source-to-artifact path and its principal
data handoffs.

## Filesystem project build

```text
ASSEMBLEATOMPROJECT(OPTIONS)
  RESOLVEATOMPROJECT()
    SNAPSHOT DEFINITIONS, PLACEMENT, AND LIMITS
    CREATENODESOURCEREADER(ROOT)
      REALPATH AND OPEN PROJECT ROOT
      CONFINE AND SNAPSHOT SOURCE READS
      PRODUCE PHYSICAL, DEPENDENCY, AND LOGICAL IDENTITIES
    RESOLVESOURCEPROJECT()
      INSPECT ENTRY THROUGH ATOM SOURCE PROFILE
        PARSE ENTRY %DEFINE VALUES
        EVALUATE %IF / %ELSE / %ENDIF
        COLLECT ACTIVE %INCLUDE REFERENCES
        MASK DIRECTIVES AND INACTIVE LINES TO EQUAL LENGTH
      VISIT DEPENDENCIES IN DETERMINISTIC POSTORDER
        INSPECT EACH DEPENDENCY WITH FROZEN DEFINITIONS
        DEDUPLICATE DIAMONDS
        DEDUPLICATE REPEATS AND DIAMONDS
        REJECT CYCLES AND CAPACITY FAILURES
      JOINSOURCEPLACEMENT()
        ASSIGN BANKS BY LOGICAL PATH
        BUILD PROVENANCE
    LOWERATOMBINARYINCLUDES()
      RESOLVE AND SNAPSHOT ACTIVE INCBIN FILES
      REPLACE EACH LINE WITH EQUAL-LENGTH DS COUNT,0
      RETAIN BINARY BY SOURCE PART AND LINE
  ASSEMBLERESOLVEDATOMPROJECT()
    VALIDATE AND SNAPSHOT PARTS, TARGET, BUDGETS, AND NATIVE CORE
    CREATE DEBUG80 RUNTIME AND FIXED MEMORY MAP
    WRITE BUILD DESCRIPTOR AND PART DESCRIPTORS
    SERVE IMMUTABLE COMPILER BYTES THROUGH THE SOURCE CALLBACK
    ENTER ATOMASSEMBLE
      VALIDATE DESCRIPTOR
      RESET SYMBOL, PENDING, AND OUTPUT STATE
      SINK BEGIN
      FOR EACH PART
        TOKENIZER RESET
        ASSEMBLE PART
      FINAL UNDEFINED AND PRIVATE-SCOPE CHECKS
      SINK COMMIT OR ABORT
    INTERCEPT SINK SERVICES
      SUBSTITUTE INCBIN IMAGE BYTES
      RETAIN IMAGE, PATCH, LAYOUT, AND SYMBOL EVENTS
    CHECK PC, SP, CANARIES, SOURCE, DESCRIPTORS, AND IMMUTABLE CODE
    RETURN PROJECT, GENERATION, EXECUTION, NATIVE STATUS, AND CORE ACCOUNT
```

## Native part flow

```text
ATOMASSEMBLEPART
  ATOMTOKENIZERNEXT
    NAME / NUMBER / STRING / PUNCTUATION / EOL / EOF
  RECOGNIZE MNEMONIC OR DIRECTIVE
  LABEL OR EQUATE
    PACK EXACT RADIX-40 NAME
    VALIDATE SCOPE AND CAPACITY
    DECLARE SYMBOL
    RESOLVE PENDING PATCHES FOR THAT SYMBOL
  INSTRUCTION
    ATOMPARSERPARSE
      RECOGNIZE MNEMONIC
      CLASSIFY UP TO THREE OPERANDS
      EVALUATE CONCRETE OR DEFERRED EXPRESSIONS
      LOCATE PATCHABLE FIELDS
      VALIDATE COMPLETE FORM
      PREFLIGHT SYMBOLS AND REFERENCES
      COMMIT PARSED RECORD AND REFERENCE DESCRIPTIONS
    ATOMOUTPUTEMITINSTRUCTION
      ENCODE TO FOUR-BYTE SCRATCH
      PREFLIGHT TARGET AND PENDING CAPACITY
      SUBMIT IMAGE BYTES
      QUEUE PENDING REFERENCES
  DIRECTIVE
    EQU       DECLARE RESOLVED CONSTANT
    ORG       SET LOGICAL CURSOR
    DB / DW   EMIT CONCRETE OR PLACEHOLDER DATA
    DS        RESERVE OR EMIT FILL BYTES
    ALIGN     EMIT ZERO FILL TO BOUNDARY
    CSTR      EMIT STRING AND ZERO
    PSTR      EMIT LENGTH AND STRING
    ISTR      EMIT STRING WITH FINAL HIGH BIT
```

## Forward-reference flow

```text
PARSE FORWARD FIELD
  EXPRESSION RETURNS SYMBOL + SIGNED-BYTE ADDEND
  PARSER DETERMINES PATCH KIND AND FIELD OFFSET
  PARSER VALIDATES FORM AND PREFLIGHTS RECORDS
  OUTPUT EMITS PLACEHOLDER IMAGE BYTE(S)
  PARSER APPENDS SIX-BYTE PENDING RECORD

DEFINE SYMBOL
  SYMBOL RECORD BECOMES DEFINED
  OUTPUT PEEKS ONE PENDING RECORD
  CALCULATE AND RANGE-CHECK FINAL VALUE
  SINK APPENDS FINAL PATCH BYTE(S)
  REMOVE PENDING RECORD
  REPEAT UNTIL NONE REMAIN
```

## Artifact flow

```text
RENDERATOMARTIFACTS(ASSEMBLED)
  MATERIALIZEATOMGENERATION()
    FILL LOGICAL RANGE
    APPLY IMAGE OPERATIONS
    APPLY PATCH OPERATIONS
  WRITEATOMNOBJ()
    BEGIN
    COALESCED IMAGE RECORDS
    COALESCED PATCH RECORDS
    FLAT MAP
    COMMIT WITH CRC
  WRITEINTELHEX()
  WRITEATOMLISTING()
    ORIGINAL SOURCE + FINAL BYTES + LAYOUT + SYMBOLS
  WRITEATOMD8()
    FILES + SOURCE SEGMENTS + SYMBOLS + ENTRY

OPTIONAL PUBLISHATOMARTIFACTS()
  HASH ORDERED ARTIFACT SET
  WRITE AND SYNC TEMPORARY GENERATION
  WRITE MANIFEST WITH BYTE COUNTS AND SHA-256
  RENAME TO CONTENT DIGEST OR VERIFY EXISTING DIGEST
  CREATE TEMPORARY CURRENT SYMLINK
  RENAME SYMLINK OVER CURRENT
```

## Self-host flow

```text
NATIVE/ATOM.ASM AND FIVE INCLUDED PARTS
  |
  +-- RESOLVE AND MASK THROUGH NORMAL PREPARATION
        |
        +-- PINNED CORE ASSEMBLES SOURCE -------> FIRST ATOM CORE
        |                                           |
        |                                           +-- COMPARE WITH PINNED CORE
        |
        +-- RECOVER SYMBOL MAP AND RUN FIRST CORE
        |                                           |
        |                                           +-- SECOND ATOM CORE
        |                                               COMPARE WITH FIRST
        |
        +-- TRANSLATE THE SAME PREPARED PARTS TO AZM
                                                    |
                                                    +-- STRICT-CONTRACT BUILD
                                                        COMPARE INITIALIZED
                                                        ADDRESSES AND BYTES
```

## Data handoffs

| Stage | Input | Output |
| --- | --- | --- |
| Node source reader | Project root and path specifier | Snapshotted source with three identities |
| Atom source profile | Original source bytes and definition state | Equal-length compiler bytes, dependency references, masked ranges |
| Neutral resolver | Reader, profile, limits, placement | Ordered placed parts, provenance, retained definition state |
| `INCBIN` lowering | Resolved project and reader | Transformed compiler bytes plus binary snapshots |
| Native runner | Prepared project, target, core, budgets, sink | Committed logical generation and execution evidence |
| Native tokenizer | One part interval | Nine-byte token records |
| Native expression parser | Token stream and symbol arena | Concrete 24-bit value or deferred symbol/addend/transform |
| Native instruction parser | Mnemonic and operands | Ten-byte instruction plus zero to two reference descriptions |
| Native output | Parsed instruction or directive data | IMAGE, PATCH, cursor, capacity, and pending state |
| Memory sink | Native sink calls | Frozen committed generation |
| Artifact renderer | Project and generation | NOBJ, BIN, HEX, listing, D8 |
| Publisher | Artifact set | Immutable digest generation and atomic `current` selection |
