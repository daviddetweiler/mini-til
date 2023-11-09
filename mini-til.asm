default rel
bits 64

global boot

extern ExitProcess
extern GetStdHandle
extern WriteFile
extern ReadFile
extern GetLastError

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

%macro code_field 2
    [section .rdata]
        align 8
        %1:
            dq %2

    __?SECT?__
%endmacro

%macro primitive 1
    ; x86 prefers 16-byte aligned jump targets
    align 16
    code_field %1, %%code
        %%code:
%endmacro

%macro procedure 1
    align 8
    code_field %1, impl_procedure
%endmacro

%macro string 2
    %assign length %strlen(%2)
    %if length > 255
        %error "string too long"
    %endif

    code_field %1, impl_string
        db length, %2, 0
%endmacro

%macro constant 2
    align 8
    code_field %1, impl_constant
        dq %2
%endmacro

%macro variable 2
    constant %1, %%storage
    [section .bss]
        align 8
        %%storage:
            resq %2

    __?SECT?__
%endmacro

%macro maybe 1
    dq maybe_execute
    dq %1
%endmacro

%macro jump_to 1
    dq jump
    dq %1 - %%following
    %%following:
%endmacro

%macro branch_to 1
    dq branch
    dq %1 - %%following
    %%following:
%endmacro

%define config_input_buffer_size 4096

section .text
    boot:
        sub rsp, 8 + 8 * 16
        lea tp, program
        next

    ; --
    primitive set_rstack
        mov rp, stack_base(rstack)
        next

    ; --
    impl_procedure:
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
        mov dp, stack_base(dstack)
        next

    ; -- value
    primitive literal
        mov rax, [tp]
        add tp, 8
        sub dp, 8
        mov [dp], rax
        next

    ; code --
    primitive exit_process
        mov rcx, [dp]
        call ExitProcess

    ; -- constant
    impl_constant:
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
        call GetStdHandle
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
        call WriteFile
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
    impl_string:
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
        call ReadFile
        add dp, 8
        mov [dp], rax
        mov rax, [rsp + 8 * 5]
        mov [dp + 8], rax
        next

    ; value -- value=0?
    primitive eq_zero
        mov rax, [dp]
        test rax, rax
        setz al
        movzx rax, al
        mov [dp], rax
        next

    ; value --
    primitive maybe_execute
        mov rax, [dp]
        add dp, 8
        test rax, rax
        jnz .nzero
        add tp, 8

        .nzero:
        next

    ; value --
    primitive branch
        mov rax, [dp]
        add dp, 8
        mov rbx, [tp]
        add tp, 8
        test rax, rax
        jnz .nzero
        add tp, rbx

        .nzero:
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
        cmp rax, rbx
        sete al
        movzx rax, al
        mov [dp], rax
        next

    ; -- last-error
    primitive get_last_error
        call GetLastError
        sub dp, 8
        mov [dp], rax
        next

section .rdata
    align 8
    program:
        dq set_rstack
        dq initialize

        .next_input:
        dq refill_input
        dq input_valid_bytes
        dq load
        dq eq_zero
        maybe exit
        dq input_buffer
        dq input_valid_bytes
        dq load
        dq print
        jump_to .next_input

    ; --
    procedure initialize
        dq set_dstack
        dq init_io
        dq banner
        dq print
        dq return

    ; --
    procedure exit
        dq literal
        dq 0
        dq exit_process

    variable stdin_handle, 1
    variable stdout_handle, 1

    ; --
    procedure init_io
        dq literal
        dq -10
        dq get_std_handle
        dq assert
        dq stdin_handle
        dq store

        dq literal
        dq -11
        dq get_std_handle
        dq assert
        dq stdout_handle
        dq store

        dq return

    string banner, `Mini-TIL (c) 2023 David Detweiler\n\n`

    ; ptr size --
    procedure print
        dq stdout_handle
        dq load
        dq write_file
        dq assert
        dq drop
        dq return

    variable input_buffer, (config_input_buffer_size / 8) + 1
    variable input_valid_bytes, 1
    constant input_buffer_size, config_input_buffer_size

    ; --
    ;
    ; Signals EOF by setting input_valid_bytes to 0
    procedure refill_input
        dq input_buffer
        dq input_buffer_size
        dq stdin_handle
        dq load
        dq read_file
        branch_to .success
        dq get_last_error
        dq literal
        dq 0x6d
        dq eq
        branch_to .success
        dq crash

        .success:
        dq input_valid_bytes
        dq store
        dq return

    ; value -- value
    procedure assert
        dq copy
        dq eq_zero
        maybe crash
        dq return

section .bss
    rstack:
        resq stack_depth

    dstack:
        resq stack_depth
