default rel
bits 64

global boot

extern ExitProcess
extern GetStdHandle
extern WriteFile

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

%macro variable 2
    align 8
    code_field %1, impl_constant
        dq %%storage

    [section .bss]
        align 8
        %%storage:
            resq %2

    __?SECT?__
%endmacro

%macro string 2
    %assign length %strlen(%2)
    %if length > 255
        %error "string too long"
    %endif

    align 8
    code_field %1, impl_string
        db length, %2, 0
%endmacro

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

    ; value -- value
    primitive assert
        mov rax, [dp]
        test rax, rax
        jnz .ok
        int 0x29 ; fast_fail_fatal_app_exit

        .ok:
        next

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

section .rdata
    align 8
    program:
        dq set_rstack
        dq initialize
        dq exit

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

section .bss
    rstack:
        resq stack_depth

    dstack:
        resq stack_depth
