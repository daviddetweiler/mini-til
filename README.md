# `mini`

`mini` is a "complete" Forth-like language in a single 4096-byte Windows executable. See `example.txt` for a quick
example. In many ways it resembles a kind of macro assembler, a step just below a fully-featured Forth (_c.f._
[Silicon](https://github.com/daviddetweiler/silicon)), including requiring that all numerical constants be built up from
the built-in `zeroes` and `ones`. New primitive words can be defined circuitously through `arena_top`, `store_byte`,
and `ptr_get_proc_address`/`ptr_get_module_handle`, and everything else is achievable through its minimalist memory
management and assembly mode. See _Thinking Forth_ or _Threaded Interpretive Languages_ for context.

## Build Instructions

You will need `NASM` 2.16.01 and `NMAKE` and `LINK` as provided with Visual Studio. Run `nmake` to build `mini.exe` and
`nmake report` to generate a digest of all defined functions ("instructions") in `mini.asm`, which is written to
`report.md`.
