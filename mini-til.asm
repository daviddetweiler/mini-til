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

%assign top_entry 0
%define entry(id) header_ %+ id
%define header_0 0
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
            dq entry(top_entry)
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

    constant %1, %%storage
    [section .bss]
        align 8
        %%storage:
            resq %2

    __?SECT?__
%endmacro

%macro maybe 1
    dq maybe_impl
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

%macro either_or 2
    dq either_or_impl
    dq %1
    dq %2
%endmacro

%define config_input_buffer_size 4096
%define config_parse_buffer_size 32

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
    primitive branch
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
        call GetLastError
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
        dq set_rstack
        dq initialize

        .next_input:
        dq parse
        dq copy
        dq eq_zero
        maybe exit
        dq print
        jump_to .next_input

    ; --
    procedure initialize
        dq set_dstack
        dq init_io
        dq kernel
        dq dictionary
        dq store
        dq banner
        dq print
        dq return

    variable dictionary, 1

    ; --
    procedure exit
        dq zero
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

        dq input_buffer
        dq copy
        dq input_end_ptr
        dq store
        dq input_read_ptr
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
    variable input_end_ptr, 1
    constant input_buffer_size, config_input_buffer_size

    ; -- eof?
    procedure input_refill
        dq input_buffer
        dq copy
        dq input_read_ptr
        dq store
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
        dq copy
        dq input_buffer
        dq add
        dq zero
        dq over
        dq store_byte
        dq input_end_ptr
        dq store
        dq eq_zero
        dq return

    ; value -- value
    procedure assert
        dq copy
        dq eq_zero
        maybe crash
        dq return

    constant zero, 0
    variable input_read_ptr, 1

    ; -- string length?
    ;
    ; Signals EOF by returning length 0
    procedure parse
        dq input_refill
        branch_to .eof

        dq parse_buffer
        dq parse_write_ptr
        dq store
        
        dq parse_strip_spaces
        dq copy
        dq eq_zero
        branch_to .eof

        dq input_end_ptr
        dq load
        dq over
        dq sub
        dq return

        .eof:
        dq zero
        dq copy
        dq return

    ; -- after-spaces-ptr?
    ;
    ; Signals EOF by returning null
    procedure parse_strip_spaces
        .again:
        dq input_read_ptr
        dq load
        dq parse_consume_spaces
        dq input_end_ptr
        dq load
        dq over
        dq neq
        branch_to .no_refill
        dq drop
        dq input_refill
        branch_to .eof
        jump_to .again

        .no_refill:
        dq copy
        dq input_read_ptr
        dq store
        dq return

        .eof:
        dq zero
        dq return

    ; read-ptr -- fresh-input? eof?
    procedure input_update
        dq input_end_ptr
        dq load
        dq over
        dq neq
        dq copy
        either_or zero, input_refill
        dq return

    variable parse_buffer, config_parse_buffer_size / 8
    variable parse_word_length, 1
    variable parse_write_ptr, 1

section .bss
    rstack:
        resq stack_depth

    dstack:
        resq stack_depth

section .rdata
    finalize_dictionary kernel
