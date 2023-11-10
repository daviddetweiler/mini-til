default rel
bits 64

global boot

%ifndef compressed
    extern ExitProcess
    extern GetStdHandle
    extern WriteFile
    extern ReadFile
    extern GetLastError
    extern VirtualAlloc

    %define base_address 0

    %macro call_import 1
        call %1
    %endmacro

    %macro prologue 0
        sub rsp, 8 + 8 * 16
    %endmacro
%else
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

    %macro prologue 0
        mov rsi, rcx
        mov rdi, rdx

        lea rcx, name_kernel32
        call rsi

        mov rsi, rax
        import ExitProcess
        import GetStdHandle
        import WriteFile
        import ReadFile
        import GetLastError
        import VirtualAlloc
    %endmacro
%endif

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
        %error "dictionary already finalized"
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
    constant %1, entry(%$final_id)
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

%macro shared 1
    section .rdata
        constant shared_ %+ %1, address(%1)

    section .text
        align 16
        %1:
%endmacro

%macro primitive 1
    ; x86 prefers 16-byte aligned jump_impl targets
    align 16
    code_field %1, %%code
        %%code:
%endmacro

%macro procedure 1
    align 8
    code_field %1, impl_procedure
%endmacro

%macro string 2
    %push

    %assign %$length %strlen(%2)
    %if %$length > 255
        %error "string too long"
    %endif

    code_field %1, impl_string
        db %$length, %2, 0

    %pop
%endmacro

%macro constant 2
    align 8
    code_field %1, impl_constant
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

%macro maybe 1
    da maybe_impl
    da %1
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

%macro either_or 2
    da either_or_impl
    da %1
    da %2
%endmacro

%define config_input_buffer_size 4096
%define config_parse_buffer_size 32

section .bss
    bss_start:

section .text
    boot:
        prologue
        lea tp, program
        next

    ; --
    primitive set_rstack
        lea rp, stack_base(rstack)
        next

    ; --
    shared impl_procedure
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
        call_import ExitProcess

    ; -- constant
    shared impl_constant
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
    primitive write_file
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
        int 0x29 ; fast_fail_fatal_app_exit

    ; -- ptr size
    shared impl_string
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
        call_import ReadFile
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
    primitive maybe_impl
        mov rax, [dp]
        add dp, 8
        test rax, rax
        jnz .nzero
        add tp, 8

        .nzero:
        next

    ; value --
    primitive branch_impl
        mov rax, [dp]
        add dp, 8
        mov rbx, [tp]
        add tp, 8
        test rax, rax
        jz .zero
        add tp, rbx

        .zero:
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

     ; a b -- a~=b?
    primitive neq
        mov rax, [dp]
        mov rbx, [dp + 8]
        add dp, 8
        xor rcx, rcx
        cmp rax, rbx
        je .eq
        not rcx

        .eq:
        mov [dp], rcx
        next

    ; -- last-error
    primitive get_last_error
        call_import GetLastError
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
    primitive entry_is_immediate
        mov rax, [dp]
        add rax, 8
        movzx rbx, byte [rax]
        xor rax, rax
        test rbx, 0x80
        jz .zero
        not rax

        .zero:
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
    primitive parse_consume_spaces
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
    primitive parse_consume_nonspaces
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
        movzx rbx, byte [rax]
        mov [dp], rbx
        next

    ; a b -- a b a b
    primitive copy_pair
        mov rax, [dp + 8]
        mov rbx, [dp]
        sub dp, 8 * 2
        mov [dp + 8], rax
        mov [dp], rbx
        next

    ; condition --
    primitive either_or_impl
        mov rax, [dp]
        mov rbx, [tp]
        mov rcx, [tp + 8]
        add tp, 8 * 2
        test rax, rax
        cmovz rbx, rcx
        mov wp, rbx
        run

section .rdata
    align 8
    program:
        da set_rstack
        da initialize

        .next_input:
        da parse
        da copy
        da eq_zero
        maybe exit
        da print
        jump_to .next_input

    ; --
    procedure initialize
        da set_dstack
        da init_io
        da kernel
        da dictionary
        da store
        da banner
        da print
        da return

    variable dictionary, 1

    ; --
    procedure exit
        da zero
        da exit_process

    variable stdin_handle, 1
    variable stdout_handle, 1

    ; --
    procedure init_io
        literal -10
        da get_std_handle
        da assert
        da stdin_handle
        da store

        literal -11
        da get_std_handle
        da assert
        da stdout_handle
        da store

        da input_buffer
        da copy
        da input_end_ptr
        da store
        da input_read_ptr
        da store

        da return

    string banner, `Mini (c) 2023 David Detweiler\n\n`

    ; ptr size --
    procedure print
        da stdout_handle
        da load
        da write_file
        da assert
        da drop
        da return

    variable input_buffer, (config_input_buffer_size / 8) + 1
    variable input_end_ptr, 1
    constant input_buffer_size, config_input_buffer_size

    ; -- eof?
    procedure input_refill
        da input_buffer
        da copy
        da input_read_ptr
        da store
        da input_buffer_size
        da stdin_handle
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
        da input_buffer
        da add
        da zero
        da over
        da store_byte
        da input_end_ptr
        da store
        da eq_zero
        da return

    ; value -- value
    procedure assert
        da copy
        da eq_zero
        maybe crash
        da return

    constant zero, 0
    variable input_read_ptr, 1

    ; -- string length?
    ;
    ; Signals EOF by returning length 0
    procedure parse
        da input_refill
        branch_to .eof

        da parse_buffer
        da parse_write_ptr
        da store
        
        da parse_strip_spaces
        da copy
        da eq_zero
        branch_to .eof

        da input_end_ptr
        da load
        da over
        da sub
        da return

        .eof:
        da zero
        da copy
        da return

    ; -- after-spaces-ptr?
    ;
    ; Signals EOF by returning null
    procedure parse_strip_spaces
        .again:
        da input_read_ptr
        da load
        da parse_consume_spaces
        da input_update
        branch_to .eof
        branch_to .again
        da input_read_ptr
        da load
        da return

        .eof:
        da zero
        da return

    ; read-ptr -- fresh-input? eof?
    procedure input_update
        da copy
        da input_read_ptr
        da store
        da input_end_ptr
        da load
        da eq
        da copy
        either_or input_refill, zero
        da return

    variable parse_buffer, config_parse_buffer_size / 8
    variable parse_word_length, 1
    variable parse_write_ptr, 1

    %ifdef compressed
        name kernel32, "kernel32.dll"
        name ExitProcess, "ExitProcess"
        name GetStdHandle, "GetStdHandle"
        name WriteFile, "WriteFile"
        name ReadFile, "ReadFile"
        name GetLastError, "GetLastError"
        name VirtualAlloc, "VirtualAlloc"
    %endif

section .bss
    rstack:
        resq stack_depth

    dstack:
        resq stack_depth

    %ifdef compressed
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

        VirtualAlloc:
            resq 1
    %endif

section .rdata
    finalize_dictionary kernel

section .bss
    bss_end:

%ifdef compressed
    section .rdata
        align 8
        dq bss_end - bss_start
%endif
