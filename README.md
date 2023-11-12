# `mini`

`mini` is a "complete" Forth-like language / command interpreter in a single 4096-byte Windows executable. See
`example.mini` for scripting usage. New primitive words can be defined circuitously through `assemble_byte` and
`ffi_gpa`/`ffi_gmh` (`GetProcAddress`/`GetModuleHandle`), and everything else is achievable through its minimalist
memory management and assembly mode. See _Thinking Forth_ or _Threaded Interpretive Languages_ for context.

## Build Instructions

You will need `NASM` 2.16.01 and `NMAKE` and `LINK` as provided with Visual Studio. Run `nmake` to build `mini.exe` and
`nmake report` to generate a digest of all defined functions ("instructions") in `mini.asm`, which is written to
`report.md`.
