default rel
bits 64

global boot

%define base_address 0x2000000000

%macro call_import 1
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
    %if %$length > 7
        %error "name too long"
    %endif

    %assign %$this_entry top_entry + 1

    [section .rdata]
        align 8
        entry(%$this_entry):
            da entry(top_entry)
            db %$length | this_entry_flag
            db %$name

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
        constant %1, address(ptr_ %+ %1)

    section .text
        align 16
        ptr_ %+ %1:
%endmacro

%macro primitive 1
    ; x86 prefers 16-byte aligned jump targets
    align 16
    code_field %1, %%code
        %%code:
%endmacro

%macro procedure 1
    align 8
    code_field %1, ptr_proc
%endmacro

%macro string 2
    %push

    %assign %$length %strlen(%2)
    %if %$length > 255
        %error "string too long"
    %endif

    code_field %1, ptr_str
        db %$length, %2, 0

    %pop
%endmacro

%macro constant 2
    align 8
    code_field %1, ptr_const
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
    da lit
    dq %1
%endmacro

%macro jump_to 1
    da jump
    dq %1 - %%following
    %%following:
%endmacro

%macro branch_to 1
    da branch
    dq %1 - %%following
    %%following:
%endmacro

%define config_in_buf_size 4096
%define config_prs_buffer_size 128
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
        import CreateFileA

        lea tp, program
        next

    ; --
    primitive clrs
        lea rp, stack_base(rstack)
        next

    ; --
    impl proc
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
    primitive clds
        lea dp, stack_base(dstack)
        next

    ; -- value
    primitive lit
        mov rax, [tp]
        add tp, 8
        sub dp, 8
        mov [dp], rax
        next

    ; code --
    primitive exit
        mov rcx, [dp]
        call_import ExitProcess

    ; -- constant
    impl const
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
    primitive handle
        mov rcx, [dp]
        call_import GetStdHandle
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
    primitive wfile
        mov rcx, [dp]
        mov rdx, [dp + 16]
        mov r8, [dp + 8]
        lea r9, [rsp + 8 * 5]
        xor rax, rax
        mov [rsp + 8 * 4], rax
        call_import WriteFile
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
        xor rcx, rcx
        int 0x29 ; fast_fail_fatal_app_exit

    ; -- ptr size
    impl str
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
    primitive rfile
        mov rcx, [dp]
        mov rdx, [dp + 16]
        mov r8, [dp + 8]
        lea r9, [rsp + 8 * 5]
        xor rax, rax
        mov [rsp + 8 * 4], rax
        call_import ReadFile
        add dp, 8
        mov [dp], rax
        mov rax, [rsp + 8 * 5]
        mov [dp + 8], rax
        next

    ; value --
    primitive branch
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
    primitive jump
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
    primitive error
        call_import GetLastError
        sub dp, 8
        mov [dp], rax
        next

    ; entry-ptr -- entry-name length
    primitive de_name
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
    primitive de_imm
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
    primitive prs_ws
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
    primitive prs_nws
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
    primitive bstore
        mov rax, [dp]
        mov rbx, [dp + 8]
        add dp, 8 * 2
        mov [rax], bl
        next

    ; ptr -- byte
    primitive bload
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
    primitive scopy
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
    primitive seq
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
    primitive calign
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
        xor r10, r10
        cmp rcx, `-`
        jne .not_negative
        not r10
        add rax, 1
        sub rbx, 1
        jz .not_number
        movzx rcx, byte [rax]

        .not_negative:
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

        test r10, r10
        jz .no_negate
        neg rcx

        .no_negate:
        mov [dp + 8], rcx
        mov qword [dp], -1
        next

        .not_number:
        mov qword [dp], 0
        next

    ; ptr code -- new-ptr
    primitive prs_ch
        mov rax, [dp + 8]
        mov rcx, [dp]
        add dp, 8

        .next_char:
        movzx rbx, byte [rax]
        cmp rbx, rcx
        je .exit
        test rbx, rbx
        jz .exit
        add rax, 1
        jmp .next_char

        .exit:
        mov [dp], rax
        next

    ; name -- handle-or-invalid
    primitive open
        mov rcx, [dp]
		mov rdx, 0x80000000 ; GENERIC_READ
		mov r8, 1 ; FILE_SHARE_READ
		xor r9, r9
		mov qword [rsp + 8 * 4], 3 ; OPEN_EXISTING
		mov qword [rsp + 8 * 5], 0x80 ; FILE_ATTRIBUTE_NORMAL
		mov qword [rsp + 8 * 6], r9
		call_import CreateFileA
		cmp rax, -1
		jne .success
		mov rax, 0

		.success:
		mov [dp], rax
		next

section .rdata
    align 8
    program:
        da clrs
        da clds
        da init
        da in_fill
        branch_to .exit

        .next_input:
        da prs_nxt
        branch_to .exit
        da prs_wrd
        da copy
        da ones
        da eq
        da not
        branch_to .good
        da drop
        da drop
        da etok
        da print
        da abort

        .good:
        da number
        branch_to .number
        da drop
        da prs_wrd
        da find
        da copy
        branch_to .found
        da drop
        da prs_wrd
        da print
        da efind
        da print
        da abort

        .found:
        da copy
        da de_imm
        da swap
        da de_name
        da add
        da calign
        da swap
        da mode
        da load
        da not
        da or
        branch_to .invoke
        da asm
        jump_to .next_input

        .number:
        da mode
        da load
        da not
        branch_to .next_input
        literal address(lit)
        da asm
        da asm
        jump_to .next_input

        .invoke:
        da invoke
        jump_to .next_input

        .exit:
        da zeroes
        da exit

    procedure abort
        da ones
        da exit

    immediate
    procedure flush
        .again:
        da in_ptr
        da load
        literal `\n`
        da prs_ch
        da in_adv
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
        da return

    variable dict, 1

    variable stdin, 1
    variable stdout, 1

    string libname, `init.mini`

    ; --
    procedure init_io
        literal -10
        da handle
        da assert
        da stdin
        da store

        literal -11
        da handle
        da assert
        da stdout
        da store

        da libname
        da drop
        da open
        da copy
        da zeroes
        da eq
        da not
        branch_to .good
        da einit
        da print
        da abort

        .good:
        da in
        da store

        da return

    string einit, `init.mini not found\n`

    ; ptr size --
    procedure print
        da stdout
        da load
        da wfile
        da assert
        da drop
        da return

    variable in_buf, (config_in_buf_size / 8) + 1
    variable in_end, 1
    constant in_lim, config_in_buf_size
    variable in, 1

    ; -- eof?
    procedure in_fill
        da in_buf
        da copy
        da in_ptr
        da store
        da in_lim
        da in
        da load
        da rfile
        branch_to .success
        da error
        literal 0x6d
        da eq
        branch_to .success
        da crash

        .success:
        da copy
        da in_buf
        da add
        da zeroes
        da over
        da bstore
        da in_end
        da store
        da zeroes
        da eq
        da return

    ; value -- value
    procedure assert
        da copy
        da zeroes
        da eq
        da not
        branch_to .ok
        da crash

        .ok:
        da return

    constant zeroes, 0
    variable in_ptr, 1

    ; -- eof?
    procedure prs_nxt
        da prs_buf
        da prs_ptr
        da store

        da prs_rms
        branch_to .eof

        da prs_rd
        branch_to .eof

        da zeroes
        da return

        .eof:
        da ones
        da return

    ; string length --
    procedure prs_mov
        da prs_ptr
        da load
        da over
        da over
        da add
        da prs_ptr
        da store

        da scopy
        da return

    ; -- eof?
    procedure prs_rd
        .again:
        da in_ptr
        da load
        da copy
        da prs_nws
        da over
        da over
        da over
        da sub
        da copy
        da prs_res
        branch_to .too_long
        da prs_mov
        da swap
        da drop
        da in_adv
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
        da prs_buf
        literal 1
        da sub
        da prs_ptr
        da store
        da zeroes
        da return

    ; length -- too-long?
    procedure prs_res
        da prs_sz
        da add
        da prs_lim
        da gt
        da return

    ; -- string length
    procedure prs_wrd
        da prs_buf
        da prs_ptr
        da load
        da over
        da sub
        da return

    ; -- occupied-bytes
    procedure prs_sz
        da prs_ptr
        da load
        da prs_buf
        da sub
        da return

    ; -- eof?
    procedure prs_rms
        .again:
        da in_ptr
        da load
        da prs_ws
        da in_adv
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
    procedure in_adv
        da copy
        da in_ptr
        da store
        da in_end
        da load
        da eq
        da copy
        branch_to .refill
        da zeroes
        da return

        .refill:
        da in_fill
        da return

    variable prs_buf, config_prs_buffer_size / 8
    constant prs_lim, config_prs_buffer_size
    variable prs_ptr, 1

    name kernel32, "kernel32.dll"
    name ExitProcess, "ExitProcess"
    name GetStdHandle, "GetStdHandle"
    name WriteFile, "WriteFile"
    name ReadFile, "ReadFile"
    name GetLastError, "GetLastError"
    name CreateFileA, "CreateFileA"

    string etok, `Token too long\n`
    string efind, ` not found\n`

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
        da de_name
        da seq
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
    procedure asm
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
    procedure basm
        da here
        da load
        da bstore
        da here
        da copy
        da load
        literal 1
        da add
        da swap
        da store
        da return

    constant ffi, address(imports)

    ; --
    procedure newhdr
        da here
        da load
        da dict
        da load
        da asm
        da dict
        da store
        da prs_nxt
        da drop
        da prs_wrd
        da copy
        da basm
        da copy
        da push
        da here
        da load
        da scopy
        da pop
        da here
        da load
        da add
        da here
        da store
        da here
        da load
        da calign
        da here
        da store
        da return

section .bss
    rstack:
        resq stack_depth

    dstack:
        resq stack_depth

    imports:
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

    CreateFileA:
        resq 1

section .rdata
    finalize_dictionary kernel

section .bss
    bss_end:

section .rdata
    align 8
    dq bss_end - bss_start
