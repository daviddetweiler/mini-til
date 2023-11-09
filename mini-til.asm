DEFAULT REL
BITS 64

GLOBAL BOOT

EXTERN ExitProcess
EXTERN GetStdHandle

%DEFINE TP R15
%DEFINE WP R14
%DEFINE RP R13
%DEFINE DP R12

%MACRO RUN 0
    JMP [WP]
%ENDMACRO

%MACRO NEXT 0
    MOV WP, [TP]
    ADD TP, 8
    RUN
%ENDMACRO

%DEFINE STACK_DEPTH 1024
%DEFINE STACK_BASE(LABEL) LABEL + STACK_DEPTH * 8

%MACRO CODE_FIELD 2
    [SECTION .rdata]
        ALIGN 8
        %1:
            DQ %2

    __?SECT?__
%ENDMACRO

%MACRO PRIMITIVE 1
    ; X86 PREFERS 16-BYTE ALIGNED JUMP TARGETS
    ALIGN 16
    CODE_FIELD %1, %%CODE
        %%CODE:
%ENDMACRO

%MACRO PROCEDURE 1
    ALIGN 8
    CODE_FIELD %1, IMPL_PROCEDURE
%ENDMACRO

%MACRO VARIABLE 2
    ALIGN 8
    CODE_FIELD %1, IMPL_CONSTANT
        DQ %%STORAGE

    [SECTION .bss]
        ALIGN 8
        %%STORAGE:
            RESQ %2

    __?SECT?__
%ENDMACRO

SECTION .text
    BOOT:
        SUB RSP, 8 + 8 * 16
        LEA TP, PROGRAM
        NEXT

    ; --
    PRIMITIVE SET_RSTACK
        MOV RP, STACK_BASE(RSTACK)
        NEXT

    ; --
    IMPL_PROCEDURE:
        SUB RP, 8
        MOV [RP], TP
        LEA TP, [WP + 8]
        NEXT

    ; --
    PRIMITIVE RETURN
        MOV TP, [RP]
        ADD RP, 8
        NEXT

    ; --
    PRIMITIVE SET_DSTACK
        MOV DP, STACK_BASE(DSTACK)
        NEXT

    ; -- VALUE
    PRIMITIVE LITERAL
        MOV RAX, [TP]
        ADD TP, 8
        SUB DP, 8
        MOV [DP], RAX
        NEXT

    ; CODE --
    PRIMITIVE EXIT_PROCESS
        MOV RCX, [DP]
        CALL ExitProcess

    ; -- CONSTANT
    IMPL_CONSTANT:
        MOV RAX, [WP + 8]
        SUB DP, 8
        MOV [DP], RAX
        NEXT

    ; VALUE PTR --
    PRIMITIVE STORE
        MOV RAX, [DP]
        MOV RBX, [DP + 8]
        ADD DP, 8 * 2
        MOV [RAX], RBX
        NEXT

    ; PTR -- VALUE
    PRIMITIVE LOAD
        MOV RAX, [DP]
        MOV RAX, [RAX]
        MOV [DP], RAX
        NEXT

    ; ID -- HANDLE
    PRIMITIVE GET_STD_HANDLE
        MOV RCX, [DP]
        CALL GetStdHandle
        MOV [DP], RAX
        CMP RAX, -1
        JE .INVALID
        TEST RAX, RAX
        JZ .INVALID
        NEXT

        .INVALID:
        INT 0X29 ; FAST_FAIL_FATAL_APP_EXIT

SECTION .rdata
    ALIGN 8
    PROGRAM:
        DQ SET_RSTACK
        DQ INITIALIZE
        DQ EXIT

    ; --
    PROCEDURE INITIALIZE
        DQ SET_DSTACK
        DQ RETURN

    ; --
    PROCEDURE EXIT
        DQ LITERAL
        DQ 0
        DQ EXIT_PROCESS

    VARIABLE STDIN_HANDLE, 1
    VARIABLE STDOUT_HANDLE, 1

    ; --
    PROCEDURE INIT_IO
        DQ LITERAL
        DQ -10
        DQ GET_STD_HANDLE
        DQ STDIN_HANDLE
        DQ STORE

        DQ LITERAL
        DQ -11
        DQ GET_STD_HANDLE
        DQ STDOUT_HANDLE
        DQ STORE

        DQ RETURN

SECTION .bss
    RSTACK:
        RESQ STACK_DEPTH

    DSTACK:
        RESQ STACK_DEPTH
