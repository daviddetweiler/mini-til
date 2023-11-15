# `mini`

`mini` is a "complete" Forth-like language / command interpreter hosted by a single 4096-byte Windows executable. New
primitive words can be defined circuitously through `assemble_byte` and `ffi` (the internal import table, which also
contains `GetModuleHandleA` and `GetProcAddress`), and everything else is achievable through its minimalist memory
management and assembly mode. See _Thinking Forth_ or _Threaded Interpretive Languages_ for context. `init.mini` is run
on startup and can be used to define your own programs.

## Build Instructions

You will need `NASM` 2.16.01 and `NMAKE` and `LINK` as provided with Visual Studio. Run `nmake` to build `mini.exe` and
`nmake report` to generate a digest of all defined functions ("instructions") in `mini.asm`, which is written to
`report.md`.

## Meta-compilation

I have a plan:
- `mini.exe` will be the exceedingly tiny kernel used for bootstrapping by a full, self-hosted Forth/TIL meta-compiler.
    - But let's keep compression around purely for the satisfaction and the reference implementation.
- This meta-compiler will be retargeted for UEFI to make a classic block-based multitasking, persistent environment, on
  which much further work can be done.
- LISP and Smalltalk implementations will follow, hopefully self-hosting and image-based.
