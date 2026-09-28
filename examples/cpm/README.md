# CP/M hello

`HELLO.ASM` is a standalone CP/M transient command. It prints a short message
with BDOS function 9 and returns to CP/M.

On a desktop, build it from this directory with:

```sh
atom hello.asm hello.com
```

On CP/M, run Atom with the source name; it writes `HELLO.COM` beside the
source:

```text
A>ATOM HELLO.ASM
```
