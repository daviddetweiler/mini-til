# `mini-til`

The aim of this project is to produce a "minimalist" threaded interpretive language for Windows. A TIL must have at
least:
- A textual interpreter with an assembly mode
- `dictionary`, `entry_data`, `entry_immediate`, `entry_name` (dictionary manipulation)
- An assortment of stack primitives (`+`, `-`, `-#`, `&`, `|`, `~`, etc.)
- `]`, `[` `assembly_ptr`, `assembly_base`, `assembly_cap`, `assemble`, `assemble_string` (thread assembler)
- `print`, `print_line`, `new_line` (text output, though optional)
- FFI: `GetProcAddress` / `GetModuleHandle`

Essentially, to provide the minimal necessary environment to bootstrap to a much nicer interpreter written in the TIL
itself (one more akin to [Silicon](https://github.com/daviddetweiler/silicon)).
