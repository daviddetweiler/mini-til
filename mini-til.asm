DEFAULT REL
BITS 64

GLOBAL BOOT

EXTERN ExitProcess

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

SECTION .bss
    RSTACK:
        RESQ STACK_DEPTH

    DSTACK:
        RESQ STACK_DEPTH
