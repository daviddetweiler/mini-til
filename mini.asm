default rel
bits 64

global boot

%define base_address 0x2000000000

%macro cimport 1
    call [%1]
%endmacro

%macro name 2
    name_ %+ %1:
        db %2, 0
%endmacro

%macro import 1
    mov rcx, rsi
    lea rdx, name_ %+ %1
    call rdi
    mov [%1], rax
%endmacro

%define address(label) (label) + base_address

%macro da 1
    dq address(%1)
%endmacro

%define tp r15
%define wp r14
%define rp r13
%define dp r12

%macro run 0
    jmp [wp]
%endmacro

%macro next 0
    mov wp, [tp]
    add tp, 8
    run
%endmacro

%define stack_depth 1024
%define stack_base(label) label + stack_depth * 8

%assign top_entry 0
%define entry(id) header_ %+ id
%define header_0 0 - base_address
%assign this_entry_flag 0
%assign dict_finalized 0

%macro immediate 0
    %assign this_entry_flag 0x80
%endmacro

%macro header 1
    %push

    %if dict_finalized
        %error "dict already finalized"
    %endif

    %defstr %$name %1
    %assign %$length %strlen(%$name)
    %if %$length > 127
        %error "name too long"
    %endif

    %assign %$this_entry top_entry + 1

    [section .rdata]
        align 8
        entry(%$this_entry):
            da entry(top_entry)
            db %$length | this_entry_flag
            db %$name, 0

    __?SECT?__

    %assign this_entry_flag 0
    %assign top_entry %$this_entry

    %pop
%endmacro

%macro finalize_dictionary 1
    %push
    %assign %$final_id top_entry + 1
    constant %1, address(entry(%$final_id))
    %assign dict_finalized 1
    %pop
%endmacro

%macro code_field 2
    header %1
    [section .rdata]
        align 8
        %1:
            da %2

    __?SECT?__
%endmacro

%macro impl 1
    section .rdata
        constant impl_ %+ %1, address(ptr_ %+ %1)

    section .text
        align 16
        ptr_ %+ %1:
%endmacro

%macro primitive 1
    ; x86 prefers 16-byte aligned jump_impl targets
    align 16
    code_field %1, %%code
        %%code:
%endmacro

%macro procedure 1
    align 8
    code_field %1, ptr_procedure
%endmacro

%macro string 2
    %push

    %assign %$length %strlen(%2)
    %if %$length > 255
        %error "string too long"
    %endif

    code_field %1, ptr_string
        db %$length, %2, 0

    %pop
%endmacro

%macro constant 2
    align 8
    code_field %1, ptr_constant
        dq %2
%endmacro

%macro variable 2
    %if %2 < 1
        %error "variable size must be at least 1"
    %endif

    constant %1, address(%%storage)
    [section .bss]
        align 8
        %%storage:
            resq %2

    __?SECT?__
%endmacro

%macro literal 1
    da literal_impl
    dq %1
%endmacro

%macro jump_to 1
    da jump_impl
    dq %1 - %%following
    %%following:
%endmacro

%macro branch_to 1
    da branch_impl
    dq %1 - %%following
    %%following:
%endmacro

%define config_input_buf_size 4096
%define config_parser_buffer_size 128
%define config_arena_size (1 << 16) - 1

section .bss
    bss_start:

section .text
    boot:
        mov rsi, rcx
        mov rdi, rdx
        mov [GetModuleHandleA], rsi
        mov [GetProcAddress], rdi

        lea rcx, name_kernel32
        call rsi

        mov rsi, rax
        import ExitProcess
        import GetStdHandle
        import WriteFile
        import ReadFile
        import GetLastError

        lea tp, program
        next

    ; --
    primitive set_rstack
        lea rp, stack_base(rstack)
        next

    ; --
    impl procedure
        sub rp, 8
        mov [rp], tp
        lea tp, [wp + 8]
        next

    ; --
    primitive return
        mov tp, [rp]
        add rp, 8
        next

    ; --
    primitive set_dstack
        lea dp, stack_base(dstack)
        next

    ; -- value
    primitive literal_impl
        mov rax, [tp]
        add tp, 8
        sub dp, 8
        mov [dp], rax
        next

    ; code --
    primitive exit_process
        mov rcx, [dp]
        cimport ExitProcess

    ; -- constant
    impl constant
        mov rax, [wp + 8]
        sub dp, 8
        mov [dp], rax
        next

    ; value ptr --
    primitive store
        mov rax, [dp]
        mov rbx, [dp + 8]
        add dp, 8 * 2
        mov [rax], rbx
        next

    ; ptr -- value
    primitive load
        mov rax, [dp]
        mov rax, [rax]
        mov [dp], rax
        next

    ; id -- handle?
    primitive get_std_handle
        mov rcx, [dp]
        cimport GetStdHandle
        cmp rax, -1
        je .invalid
        test rax, rax
        jz .invalid
        mov [dp], rax
        next

        .invalid:
        xor rax, rax
        mov [dp], rax
        next

    ; ptr size handle -- success?
    primitive write_file
        mov rcx, [dp]
        mov rdx, [dp + 16]
        mov r8, [dp + 8]
        lea r9, [rsp + 8 * 5]
        xor rax, rax
        mov [rsp + 8 * 4], rax
        cimport WriteFile
        add dp, 8 * 2
        mov [dp], rax
        next

    ; a -- a a
    primitive copy
        mov rax, [dp]
        sub dp, 8
        mov [dp], rax
        next

    ; --
    primitive crash
        int 0x29 ; fast_fail_fatal_app_exit

    ; -- ptr size
    impl string
        movzx rax, byte [wp + 8]
        lea rbx, [wp + 9]
        sub dp, 8 * 2
        mov [dp], rax
        mov [dp + 8], rbx
        next

    ; value --
    primitive drop
        add dp, 8
        next

    ; buffer size handle -- bytes-read success?
    primitive read_file
        mov rcx, [dp]
        mov rdx, [dp + 16]
        mov r8, [dp + 8]
        lea r9, [rsp + 8 * 5]
        xor rax, rax
        mov [rsp + 8 * 4], rax
        cimport ReadFile
        add dp, 8
        mov [dp], rax
        mov rax, [rsp + 8 * 5]
        mov [dp + 8], rax
        next

    ; value -- value=0?
    primitive eq_zero
        mov rax, [dp]
        xor rbx, rbx
        test rax, rax
        jnz .nzero
        not rbx

        .nzero:
        mov [dp], rbx
        next

    ; value --
    primitive branch_impl
        mov rax, [dp]
        add dp, 8
        mov rbx, [tp]
        add tp, 8
        test rax, rax
        jz .zeroes
        add tp, rbx

        .zeroes:
        next

    ; --
    primitive jump_impl
        mov rax, [tp]
        lea tp, [tp + rax + 8]
        next

    ; a b -- a=b?
    primitive eq
        mov rax, [dp]
        mov rbx, [dp + 8]
        add dp, 8
        xor rcx, rcx
        cmp rax, rbx
        jne .neq
        not rcx

        .neq:
        mov [dp], rcx
        next

    ; -- last-error
    primitive get_last_error
        cimport GetLastError
        sub dp, 8
        mov [dp], rax
        next

    ; entry-ptr -- entry-name length
    primitive entry_name
        mov rax, [dp]
        add rax, 8
        movzx rbx, byte [rax]
        and rbx, 0x7f
        lea rax, [rax + 1]
        mov [dp], rax
        sub dp, 8
        mov [dp], rbx
        next

    ; entry-ptr -- entry-is-immediate?
    primitive entry_imm
        mov rax, [dp]
        add rax, 8
        movzx rbx, byte [rax]
        xor rax, rax
        test rbx, 0x80
        jz .zeroes
        not rax

        .zeroes:
        mov [dp], rax
        next

    ; a b -- a b a
    primitive over
        mov rax, [dp + 8]
        sub dp, 8
        mov [dp], rax
        next

    ; a b -- a+b
    primitive add
        mov rax, [dp]
        add dp, 8
        add [dp], rax
        next

    ; a b -- a-b
    primitive sub
        mov rax, [dp]
        add dp, 8
        sub [dp], rax
        next

    ; ptr -- new-ptr
    primitive parser_spaces
        mov rax, [dp]
        jmp .next_char

        .consume:
        add rax, 1

        .next_char:
        movzx rbx, byte [rax]
        cmp rbx, ` `
        je .consume
        cmp rbx, `\t`
        je .consume
        cmp rbx, `\n`
        je .consume
        cmp rbx, `\r`
        je .consume

        mov [dp], rax
        next

    ; ptr -- new-ptr
    primitive parser_nonspaces
        mov rax, [dp]

        .next_char:
        movzx rbx, byte [rax]
        cmp rbx, ` `
        je .exit
        cmp rbx, `\t`
        je .exit
        cmp rbx, `\n`
        je .exit
        cmp rbx, `\r`
        je .exit
        cmp rbx, 0
        je .exit
        add rax, 1
        jmp .next_char

        .exit:
        mov [dp], rax
        next

    ; byte ptr --
    primitive store_byte
        mov rax, [dp]
        mov rbx, [dp + 8]
        add dp, 8 * 2
        mov [rax], bl
        next

    ; ptr -- byte
    primitive load_byte
        mov rax, [dp]
        movzx rax, byte [rax]
        mov [dp], rax
        next

    ; a b -- a>b
    primitive gt
        mov rax, [dp + 8]
        mov rbx, [dp]
        add dp, 8
        xor rcx, rcx
        cmp rax, rbx
        jle .le
        not rcx

        .le:
        mov [dp], rcx
        next

    ; string length destination --
    primitive string_copy
        mov rdi, [dp]
        mov rcx, [dp + 8]
        mov rsi, [dp + 8 * 2]
        add dp, 8 * 3
        rep movsb
        next

    ; a b -- b a
    primitive swap
        mov rax, [dp]
        mov rbx, [dp + 8]
        mov [dp], rbx
        mov [dp + 8], rax
        next

    ; value --
    primitive push
        mov rax, [dp]
        add dp, 8
        sub rp, 8
        mov [rp], rax
        next

    ; -- top
    primitive pop
        mov rax, [rp]
        add rp, 8
        sub dp, 8
        mov [dp], rax
        next

    ; a a-length b b-length -- equal?
    primitive string_eq
        mov rcx, [dp]
        mov rdx, [dp + 8 * 2]
        mov rsi, [dp + 8]
        mov rdi, [dp + 8 * 3]
        add dp, 8 * 3
        cmp rcx, rdx
        jne .neq

        repe cmpsb
        test rcx, rcx
        jnz .neq

        movzx rax, byte [rsi - 1]
        movzx rbx, byte [rdi - 1]
        cmp rax, rbx
        jne .neq

        xor rax, rax
        not rax
        mov [dp], rax
        next

        .neq:
        xor rax, rax
        mov [dp], rax
        next

    ; ptr -- aligned-ptr
    primitive cell_align
        mov rax, [dp]
        and rax, 7
        sub rax, 8
        neg rax
        and rax, 7
        add [dp], rax
        next

    ; callable --
    primitive invoke
        mov rax, [dp]
        add dp, 8
        mov wp, rax
        run

    ; a -- ~a
    primitive not
        not qword [dp]
        next

    ; a b -- a|b
    primitive or
        mov rax, [dp]
        add dp, 8
        or [dp], rax
        next

    ; string length -- n number?
    primitive number
        mov rax, [dp + 8]
        mov rbx, [dp]

        movzx rcx, byte [rax]
        cmp rcx, `0`
        jl .not_number
        cmp rcx, `9`
        jg .not_number

        xor rcx, rcx

        .next:
        movzx rdx, byte [rax]
        sub rdx, `0`
        imul rcx, 10
        add rcx, rdx
        add rax, 1
        sub rbx, 1
        jnz .next
        mov [dp + 8], rcx
        mov qword [dp], -1
        next

        .not_number:
        mov qword [dp], 0
        next

    ; ptr -- new-ptr
    primitive parser_line
        mov rax, [dp]

        .next_char:
        movzx rbx, byte [rax]
        cmp rbx, `\n`
        je .exit
        add rax, 1
        jmp .next_char

        .exit:
        mov [dp], rax
        next

section .rdata
    align 8
    program:
        da set_rstack
        da set_dstack
        da init
        da input_refill
        branch_to .exit

        .next_input:
        da parser_next
        branch_to .exit
        da parser_word
        da copy
        da ones
        da eq
        da not
        branch_to .good
        da drop
        da drop
        da msg_tok
        da print
        jump_to program

        .good:
        da number
        branch_to .number
        da drop
        da parser_word
        da find
        da copy
        branch_to .found
        da drop
        da parser_word
        da print
        da msg_find
        da print
        jump_to program

        .found:
        da copy
        da entry_imm
        da swap
        da entry_name
        da add
        da cell_align
        da swap
        da mode
        da load
        da not
        da or
        branch_to .invoke
        da assemble
        jump_to .next_input

        .number:
        da mode
        da load
        da not
        branch_to .next_input
        literal address(literal_impl)
        da assemble
        da assemble
        jump_to .next_input

        .invoke:
        da invoke
        jump_to .next_input

        .exit:
        da zeroes
        da exit_process

    immediate
    procedure flush
        .again:
        da input_read_ptr
        da load
        da parser_line
        da input_update
        branch_to .eof
        branch_to .again
        da return

        .eof:
        da drop
        da return

    ; --
    procedure init
        da init_io
        da kernel
        da dict
        da store
        da arena
        da zeroes
        da mode
        da store
        da here
        da store
        da banner
        da print
        da return

    variable dict, 1

    variable stdin, 1
    variable stdout, 1

    ; --
    procedure init_io
        literal -10
        da get_std_handle
        da assert
        da stdin
        da store

        literal -11
        da get_std_handle
        da assert
        da stdout
        da store

        da return

    string banner, `Mini (c) 2023 David Detweiler\n\n`

    ; ptr size --
    procedure print
        da stdout
        da load
        da write_file
        da assert
        da drop
        da return

    variable input_buf, (config_input_buf_size / 8) + 1
    variable input_end, 1
    constant input_lim, config_input_buf_size

    ; -- eof?
    procedure input_refill
        da input_buf
        da copy
        da input_read_ptr
        da store
        da input_lim
        da stdin
        da load
        da read_file
        branch_to .success
        da get_last_error
        literal 0x6d
        da eq
        branch_to .success
        da crash

        .success:
        da copy
        da input_buf
        da add
        da zeroes
        da over
        da store_byte
        da input_end
        da store
        da eq_zero
        da return

    ; value -- value
    procedure assert
        da copy
        da eq_zero
        da not
        branch_to .ok
        da crash

        .ok:
        da return

    constant zeroes, 0
    variable input_read_ptr, 1

    ; -- eof?
    procedure parser_next
        da parser_buf
        da parser_ptr
        da store

        da parser_strip
        branch_to .eof

        da parser_ingest_word
        branch_to .eof

        da zeroes
        da return

        .eof:
        da ones
        da return

    ; string length --
    procedure parser_move_string
        da parser_ptr
        da load
        da over
        da over
        da add
        da parser_ptr
        da store

        da string_copy
        da return

    ; -- eof?
    procedure parser_ingest_word
        .again:
        da input_read_ptr
        da load
        da copy
        da parser_nonspaces
        da over
        da over
        da over
        da sub
        da copy
        da parser_allocate
        branch_to .too_long
        da parser_move_string
        da swap
        da drop
        da input_update
        branch_to .eof
        branch_to .again

        da zeroes
        da return

        .eof:
        da drop
        da ones
        da return

        .too_long:
        da drop
        da drop
        da drop
        da drop
        da parser_buf
        literal 1
        da sub
        da parser_ptr
        da store
        da zeroes
        da return

    ; length -- too-long?
    procedure parser_allocate
        da parser_usage
        da add
        da parser_lim
        da gt
        da return

    ; -- string length
    procedure parser_word
        da parser_buf
        da parser_ptr
        da load
        da over
        da sub
        da return

    ; -- occupied-bytes
    procedure parser_usage
        da parser_ptr
        da load
        da parser_buf
        da sub
        da return

    ; -- eof?
    procedure parser_strip
        .again:
        da input_read_ptr
        da load
        da parser_spaces
        da input_update
        branch_to .eof
        branch_to .again
        da zeroes
        da return

        .eof:
        da drop
        da ones
        da return

    constant ones, ~0

    ; read-ptr -- fresh-input? eof?
    procedure input_update
        da copy
        da input_read_ptr
        da store
        da input_end
        da load
        da eq
        da copy
        branch_to .refill
        da zeroes
        da return

        .refill:
        da input_refill
        da return

    variable parser_buf, config_parser_buffer_size / 8
    constant parser_lim, config_parser_buffer_size
    variable parser_ptr, 1

    name kernel32, "kernel32.dll"
    name ExitProcess, "ExitProcess"
    name GetStdHandle, "GetStdHandle"
    name WriteFile, "WriteFile"
    name ReadFile, "ReadFile"
    name GetLastError, "GetLastError"

    string msg_tok, `Token too long\n`
    string msg_find, ` not found\n`

    ; name length -- entry?
    procedure find
        da dict
        da load
        da push

        .next:
        da over
        da over
        da pop
        da copy
        da push
        da entry_name
        da string_eq
        branch_to .found
        da pop
        da load
        da copy
        da push
        branch_to .next

        .found:
        da drop
        da drop
        da pop
        da return

    variable mode, 1
    variable arena, config_arena_size / 8
    variable here, 1
    constant limit, config_arena_size

    ; --
    procedure begin
        da ones
        da mode
        da store
        da return

    ; --
    immediate
    procedure end
        da zeroes
        da mode
        da store
        da return

    ; value --
    procedure assemble
        da here
        da load
        da store
        da here
        da copy
        da load
        literal 8
        da add
        da swap
        da store
        da return

    ; value --
    procedure assemble_byte
        da here
        da load
        da store_byte
        da here
        da copy
        da load
        literal 1
        da add
        da swap
        da store
        da return

    constant ffi_gpa, address(GetProcAddress)
    constant ffi_gmh, address(GetModuleHandleA)

section .bss
    rstack:
        resq stack_depth

    dstack:
        resq stack_depth

    GetProcAddress:
        resq 1

    GetModuleHandleA:
        resq 1

    ExitProcess:
        resq 1

    GetStdHandle:
        resq 1

    WriteFile:
        resq 1

    ReadFile:
        resq 1

    GetLastError:
        resq 1

section .rdata
    finalize_dictionary kernel

section .bss
    bss_end:

section .rdata
    align 8
    dq bss_end - bss_start
