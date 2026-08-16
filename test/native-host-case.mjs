export const NATIVE_HOST_FILES = Object.freeze({
  "lib.asm": "%if FEATURE\nLibValue EQU 3\n%endif\n",
  "main.asm": [
    "%define FEATURE %1",
    "%include \"lib.asm\"",
    "ORG 4000H",
    "Start:",
    "    ld a,LibValue",
    "    jr .later",
    "    db \"A\",%1",
    ".later:",
    "    dw Start",
    "    ds 2,0ffH",
    "",
  ].join("\n"),
});
