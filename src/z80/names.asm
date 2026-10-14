;=============================================================================
;  Names: RADIX-40 packing and mnemonic recognition
;=============================================================================
;
;  Atom stores every name in six bytes: three 16-bit words of RADIX-40
;  characters, without case. Symbols, directives and mnemonics are all
;  compared in this packed form. Row n of the mnemonic table holds three
;  bytes of mnemonic n's packed name, so recognising a mnemonic returns its
;  number, which the parser and encoder use from then on.
;
;  enTemp is six bytes because the packer needs three words. The encoder
;  reuses its first four bytes to stage an instruction before commit.

    %INCLUDE "radix40.asm"              ; Pack names into three RADIX-40 words.
    %INCLUDE "mnemonic.asm"             ; Number and recognise Z80 mnemonics.
