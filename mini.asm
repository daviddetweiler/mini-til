DEFAULT REL
BITS 64

GLOBAL BOOT

%DEFINE BASE_ADDRESS 0X2000000000

%MACRO CALL_IMPORT 1
    CALL [%1]
%ENDMACRO

%MACRO NAME 2
    NAME_ %+ %1:
        DB %2, 0
%ENDMACRO

%MACRO IMPORT 1
    MOV RCX, RSI
    LEA RDX, NAME_ %+ %1
    CALL RDI
    MOV [%1], RAX
%ENDMACRO

%DEFINE ADDRESS(LABEL) (LABEL) + BASE_ADDRESS

%MACRO DA 1
    DQ ADDRESS(%1)
%ENDMACRO

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

%ASSIGN TOP_ENTRY 0
%DEFINE ENTRY(ID) HEADER_ %+ ID
%DEFINE HEADER_0 0 - BASE_ADDRESS
%ASSIGN THIS_ENTRY_FLAG 0
%ASSIGN DICT_FINALIZED 0

%MACRO IMMEDIATE 0
    %ASSIGN THIS_ENTRY_FLAG 0X80
%ENDMACRO

%MACRO HEADER 1
    %PUSH

    %IF DICT_FINALIZED
        %ERROR "DICT ALREADY FINALIZED"
    %ENDIF

    %DEFSTR %$NAME %1
    %ASSIGN %$LENGTH %STRLEN(%$NAME)
    %IF %$LENGTH > 7
        %ERROR "NAME TOO LONG"
    %ENDIF

    %ASSIGN %$THIS_ENTRY TOP_ENTRY + 1

    [SECTION .rdata]
        ALIGN 8
        ENTRY(%$THIS_ENTRY):
            DA ENTRY(TOP_ENTRY)
            DB %$LENGTH | THIS_ENTRY_FLAG
            DB %$NAME

    __?SECT?__

    %ASSIGN THIS_ENTRY_FLAG 0
    %ASSIGN TOP_ENTRY %$THIS_ENTRY

    %POP
%ENDMACRO

%MACRO FINALIZE_DICTIONARY 1
    %PUSH
    %ASSIGN %$FINAL_ID TOP_ENTRY + 1
    CONSTANT %1, ADDRESS(ENTRY(%$FINAL_ID))
    %ASSIGN DICT_FINALIZED 1
    %POP
%ENDMACRO

%MACRO CODE_FIELD 2
    HEADER %1
    [SECTION .rdata]
        ALIGN 8
        %1:
            DA %2

    __?SECT?__
%ENDMACRO

%MACRO IMPL 1
    SECTION .rdata
        CONSTANT %1, ADDRESS(PTR_ %+ %1)

    SECTION .text
        ALIGN 16
        PTR_ %+ %1:
%ENDMACRO

%MACRO PRIMITIVE 1
    ; X86 PREFERS 16-BYTE ALIGNED JUMP TARGETS
    ALIGN 16
    CODE_FIELD %1, %%CODE
        %%CODE:
%ENDMACRO

%MACRO PROCEDURE 1
    ALIGN 8
    CODE_FIELD %1, PTR_PROC
%ENDMACRO

%MACRO STRING 2
    %PUSH

    %ASSIGN %$LENGTH %STRLEN(%2)
    %IF %$LENGTH > 255
        %ERROR "STRING TOO LONG"
    %ENDIF

    CODE_FIELD %1, PTR_STR
        DB %$LENGTH, %2, 0

    %POP
%ENDMACRO

%MACRO CONSTANT 2
    ALIGN 8
    CODE_FIELD %1, PTR_CONST
        DQ %2
%ENDMACRO

%MACRO VARIABLE 2
    %IF %2 < 1
        %ERROR "VARIABLE SIZE MUST BE AT LEAST 1"
    %ENDIF

    CONSTANT %1, ADDRESS(%%STORAGE)
    [SECTION .bss]
        ALIGN 8
        %%STORAGE:
            RESQ %2

    __?SECT?__
%ENDMACRO

%MACRO LITERAL 1
    DA LIT
    DQ %1
%ENDMACRO

%MACRO JUMP_TO 1
    DA JUMP
    DQ %1 - %%FOLLOWING
    %%FOLLOWING:
%ENDMACRO

%MACRO BRANCH_TO 1
    DA BRANCH
    DQ %1 - %%FOLLOWING
    %%FOLLOWING:
%ENDMACRO

%DEFINE CONFIG_IN_BUF_SIZE 4096
%DEFINE CONFIG_PRS_BUFFER_SIZE 128
%DEFINE CONFIG_ARENA_SIZE (1 << 16) - 1

SECTION .bss
    BSS_START:

SECTION .text
    BOOT:
        MOV RSI, RCX
        MOV RDI, RDX
        MOV [GetModuleHandleA], RSI
        MOV [GetProcAddress], RDI

        LEA RCX, NAME_KERNEL32
        CALL RSI

        MOV RSI, RAX
        IMPORT ExitProcess
        IMPORT GetStdHandle
        IMPORT WriteFile
        IMPORT ReadFile
        IMPORT GetLastError
        IMPORT CreateFileA

        LEA TP, PROGRAM
        NEXT

    ; --
    PRIMITIVE CLRS
        LEA RP, STACK_BASE(RSTACK)
        NEXT

    ; --
    IMPL PROC
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
    PRIMITIVE CLDS
        LEA DP, STACK_BASE(DSTACK)
        NEXT

    ; -- VALUE
    PRIMITIVE LIT
        MOV RAX, [TP]
        ADD TP, 8
        SUB DP, 8
        MOV [DP], RAX
        NEXT

    ; CODE --
    PRIMITIVE EXIT
        MOV RCX, [DP]
        CALL_IMPORT ExitProcess

    ; -- CONSTANT
    IMPL CONST
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

    ; ID -- HANDLE?
    PRIMITIVE HANDLE
        MOV RCX, [DP]
        CALL_IMPORT GetStdHandle
        CMP RAX, -1
        JE .INVALID
        TEST RAX, RAX
        JZ .INVALID
        MOV [DP], RAX
        NEXT

        .INVALID:
        XOR RAX, RAX
        MOV [DP], RAX
        NEXT

    ; PTR SIZE HANDLE -- SUCCESS?
    PRIMITIVE WFILE
        MOV RCX, [DP]
        MOV RDX, [DP + 16]
        MOV R8, [DP + 8]
        LEA R9, [RSP + 8 * 5]
        XOR RAX, RAX
        MOV [RSP + 8 * 4], RAX
        CALL_IMPORT WriteFile
        ADD DP, 8 * 2
        MOV [DP], RAX
        NEXT

    ; A -- A A
    PRIMITIVE COPY
        MOV RAX, [DP]
        SUB DP, 8
        MOV [DP], RAX
        NEXT

    ; --
    PRIMITIVE CRASH
        XOR RCX, RCX
        INT 0X29 ; FAST_FAIL_FATAL_APP_EXIT

    ; -- PTR SIZE
    IMPL STR
        MOVZX RAX, BYTE [WP + 8]
        LEA RBX, [WP + 9]
        SUB DP, 8 * 2
        MOV [DP], RAX
        MOV [DP + 8], RBX
        NEXT

    ; VALUE --
    PRIMITIVE DROP
        ADD DP, 8
        NEXT

    ; BUFFER SIZE HANDLE -- BYTES-READ SUCCESS?
    PRIMITIVE RFILE
        MOV RCX, [DP]
        MOV RDX, [DP + 16]
        MOV R8, [DP + 8]
        LEA R9, [RSP + 8 * 5]
        XOR RAX, RAX
        MOV [RSP + 8 * 4], RAX
        CALL_IMPORT ReadFile
        ADD DP, 8
        MOV [DP], RAX
        MOV RAX, [RSP + 8 * 5]
        MOV [DP + 8], RAX
        NEXT

    ; VALUE --
    PRIMITIVE BRANCH
        MOV RAX, [DP]
        ADD DP, 8
        MOV RBX, [TP]
        ADD TP, 8
        TEST RAX, RAX
        JZ .ZEROES
        ADD TP, RBX

        .ZEROES:
        NEXT

    ; --
    PRIMITIVE JUMP
        MOV RAX, [TP]
        LEA TP, [TP + RAX + 8]
        NEXT

    ; A B -- A=B?
    PRIMITIVE EQ
        MOV RAX, [DP]
        MOV RBX, [DP + 8]
        ADD DP, 8
        XOR RCX, RCX
        CMP RAX, RBX
        JNE .NEQ
        NOT RCX

        .NEQ:
        MOV [DP], RCX
        NEXT

    ; -- LAST-ERROR
    PRIMITIVE ERROR
        CALL_IMPORT GetLastError
        SUB DP, 8
        MOV [DP], RAX
        NEXT

    ; ENTRY-PTR -- ENTRY-NAME LENGTH
    PRIMITIVE DE_NAME
        MOV RAX, [DP]
        ADD RAX, 8
        MOVZX RBX, BYTE [RAX]
        AND RBX, 0X7F
        LEA RAX, [RAX + 1]
        MOV [DP], RAX
        SUB DP, 8
        MOV [DP], RBX
        NEXT

    ; ENTRY-PTR -- ENTRY-IS-IMMEDIATE?
    PRIMITIVE DE_IMM
        MOV RAX, [DP]
        ADD RAX, 8
        MOVZX RBX, BYTE [RAX]
        XOR RAX, RAX
        TEST RBX, 0X80
        JZ .ZEROES
        NOT RAX

        .ZEROES:
        MOV [DP], RAX
        NEXT

    ; A B -- A B A
    PRIMITIVE OVER
        MOV RAX, [DP + 8]
        SUB DP, 8
        MOV [DP], RAX
        NEXT

    ; A B -- A+B
    PRIMITIVE ADD
        MOV RAX, [DP]
        ADD DP, 8
        ADD [DP], RAX
        NEXT

    ; A B -- A-B
    PRIMITIVE SUB
        MOV RAX, [DP]
        ADD DP, 8
        SUB [DP], RAX
        NEXT

    ; PTR -- NEW-PTR
    PRIMITIVE PRS_WS
        MOV RAX, [DP]
        JMP .NEXT_CHAR

        .CONSUME:
        ADD RAX, 1

        .NEXT_CHAR:
        MOVZX RBX, BYTE [RAX]
        CMP RBX, ` `
        JE .CONSUME
        CMP RBX, `\t`
        JE .CONSUME
        CMP RBX, `\n`
        JE .CONSUME
        CMP RBX, `\r`
        JE .CONSUME

        MOV [DP], RAX
        NEXT

    ; PTR -- NEW-PTR
    PRIMITIVE PRS_NWS
        MOV RAX, [DP]

        .NEXT_CHAR:
        MOVZX RBX, BYTE [RAX]
        CMP RBX, ` `
        JE .EXIT
        CMP RBX, `\t`
        JE .EXIT
        CMP RBX, `\n`
        JE .EXIT
        CMP RBX, `\r`
        JE .EXIT
        CMP RBX, 0
        JE .EXIT
        ADD RAX, 1
        JMP .NEXT_CHAR

        .EXIT:
        MOV [DP], RAX
        NEXT

    ; BYTE PTR --
    PRIMITIVE BSTORE
        MOV RAX, [DP]
        MOV RBX, [DP + 8]
        ADD DP, 8 * 2
        MOV [RAX], BL
        NEXT

    ; PTR -- BYTE
    PRIMITIVE BLOAD
        MOV RAX, [DP]
        MOVZX RAX, BYTE [RAX]
        MOV [DP], RAX
        NEXT

    ; A B -- A>B
    PRIMITIVE GT
        MOV RAX, [DP + 8]
        MOV RBX, [DP]
        ADD DP, 8
        XOR RCX, RCX
        CMP RAX, RBX
        JLE .LE
        NOT RCX

        .LE:
        MOV [DP], RCX
        NEXT

    ; STRING LENGTH DESTINATION --
    PRIMITIVE SCOPY
        MOV RDI, [DP]
        MOV RCX, [DP + 8]
        MOV RSI, [DP + 8 * 2]
        ADD DP, 8 * 3
        REP MOVSB
        NEXT

    ; A B -- B A
    PRIMITIVE SWAP
        MOV RAX, [DP]
        MOV RBX, [DP + 8]
        MOV [DP], RBX
        MOV [DP + 8], RAX
        NEXT

    ; VALUE --
    PRIMITIVE PUSH
        MOV RAX, [DP]
        ADD DP, 8
        SUB RP, 8
        MOV [RP], RAX
        NEXT

    ; -- TOP
    PRIMITIVE POP
        MOV RAX, [RP]
        ADD RP, 8
        SUB DP, 8
        MOV [DP], RAX
        NEXT

    ; A A-LENGTH B B-LENGTH -- EQUAL?
    PRIMITIVE SEQ
        MOV RCX, [DP]
        MOV RDX, [DP + 8 * 2]
        MOV RSI, [DP + 8]
        MOV RDI, [DP + 8 * 3]
        ADD DP, 8 * 3
        CMP RCX, RDX
        JNE .NEQ

        REPE CMPSB
        TEST RCX, RCX
        JNZ .NEQ

        MOVZX RAX, BYTE [RSI - 1]
        MOVZX RBX, BYTE [RDI - 1]
        CMP RAX, RBX
        JNE .NEQ

        XOR RAX, RAX
        NOT RAX
        MOV [DP], RAX
        NEXT

        .NEQ:
        XOR RAX, RAX
        MOV [DP], RAX
        NEXT

    ; PTR -- ALIGNED-PTR
    PRIMITIVE CALIGN
        MOV RAX, [DP]
        AND RAX, 7
        SUB RAX, 8
        NEG RAX
        AND RAX, 7
        ADD [DP], RAX
        NEXT

    ; CALLABLE --
    PRIMITIVE INVOKE
        MOV RAX, [DP]
        ADD DP, 8
        MOV WP, RAX
        RUN

    ; A -- ~A
    PRIMITIVE NOT
        NOT QWORD [DP]
        NEXT

    ; A B -- A|B
    PRIMITIVE OR
        MOV RAX, [DP]
        ADD DP, 8
        OR [DP], RAX
        NEXT

    ; STRING LENGTH -- N NUMBER?
    PRIMITIVE NUMBER
        MOV RAX, [DP + 8]
        MOV RBX, [DP]

        MOVZX RCX, BYTE [RAX]
        XOR R10, R10
        CMP RCX, `-`
        JNE .NOT_NEGATIVE
        NOT R10
        ADD RAX, 1
        SUB RBX, 1
        JZ .NOT_NUMBER
        MOVZX RCX, BYTE [RAX]

        .NOT_NEGATIVE:
        CMP RCX, `0`
        JL .NOT_NUMBER
        CMP RCX, `9`
        JG .NOT_NUMBER

        XOR RCX, RCX

        .NEXT:
        MOVZX RDX, BYTE [RAX]
        SUB RDX, `0`
        IMUL RCX, 10
        ADD RCX, RDX
        ADD RAX, 1
        SUB RBX, 1
        JNZ .NEXT

        TEST R10, R10
        JZ .NO_NEGATE
        NEG RCX

        .NO_NEGATE:
        MOV [DP + 8], RCX
        MOV QWORD [DP], -1
        NEXT

        .NOT_NUMBER:
        MOV QWORD [DP], 0
        NEXT

    ; PTR -- NEW-PTR
    PRIMITIVE PRS_NL
        MOV RAX, [DP]

        .NEXT_CHAR:
        MOVZX RBX, BYTE [RAX]
        CMP RBX, `\n`
        JE .EXIT
        ADD RAX, 1
        JMP .NEXT_CHAR

        .EXIT:
        MOV [DP], RAX
        NEXT

    ; NAME -- HANDLE-OR-INVALID
    PRIMITIVE OPEN
        MOV RCX, [DP]
		MOV RDX, 0X80000000 ; GENERIC_READ
		XOR R8, R8
		XOR R9, R9
		MOV QWORD [RSP + 8 * 4], 3 ; OPEN_EXISTING
		MOV QWORD [RSP + 8 * 5], 0X80 ; FILE_ATTRIBUTE_NORMAL
		MOV QWORD [RSP + 8 * 6], R9
		CALL_IMPORT CreateFileA
		CMP RAX, -1
		JNE .SUCCESS
		MOV RAX, 0

		.SUCCESS:
		MOV [DP], RAX
		NEXT

SECTION .rdata
    ALIGN 8
    PROGRAM:
        DA CLRS
        DA CLDS
        DA INIT
        DA IN_FILL
        BRANCH_TO .EXIT

        .NEXT_INPUT:
        DA PRS_NXT
        BRANCH_TO .EXIT
        DA PRS_WRD
        DA COPY
        DA ONES
        DA EQ
        DA NOT
        BRANCH_TO .GOOD
        DA DROP
        DA DROP
        DA ETOK
        DA PRINT
        DA ABORT

        .GOOD:
        DA NUMBER
        BRANCH_TO .NUMBER
        DA DROP
        DA PRS_WRD
        DA FIND
        DA COPY
        BRANCH_TO .FOUND
        DA DROP
        DA PRS_WRD
        DA PRINT
        DA EFIND
        DA PRINT
        DA ABORT

        .FOUND:
        DA COPY
        DA DE_IMM
        DA SWAP
        DA DE_NAME
        DA ADD
        DA CALIGN
        DA SWAP
        DA MODE
        DA LOAD
        DA NOT
        DA OR
        BRANCH_TO .INVOKE
        DA ASM
        JUMP_TO .NEXT_INPUT

        .NUMBER:
        DA MODE
        DA LOAD
        DA NOT
        BRANCH_TO .NEXT_INPUT
        LITERAL ADDRESS(LIT)
        DA ASM
        DA ASM
        JUMP_TO .NEXT_INPUT

        .INVOKE:
        DA INVOKE
        JUMP_TO .NEXT_INPUT

        .EXIT:
        DA ZEROES
        DA EXIT

    PROCEDURE ABORT
        DA ONES
        DA EXIT

    IMMEDIATE
    PROCEDURE FLUSH
        .AGAIN:
        DA IN_PTR
        DA LOAD
        DA PRS_NL
        DA IN_ADV
        BRANCH_TO .EOF
        BRANCH_TO .AGAIN
        DA RETURN

        .EOF:
        DA DROP
        DA RETURN

    ; --
    PROCEDURE INIT
        DA INIT_IO
        DA KERNEL
        DA DICT
        DA STORE
        DA ARENA
        DA ZEROES
        DA MODE
        DA STORE
        DA HERE
        DA STORE
        DA RETURN

    VARIABLE DICT, 1

    VARIABLE STDIN, 1
    VARIABLE STDOUT, 1

    STRING LIBNAME, `init.mini`

    ; --
    PROCEDURE INIT_IO
        LITERAL -10
        DA HANDLE
        DA ASSERT
        DA STDIN
        DA STORE

        LITERAL -11
        DA HANDLE
        DA ASSERT
        DA STDOUT
        DA STORE

        DA LIBNAME
        DA DROP
        DA OPEN
        DA COPY
        DA ZEROES
        DA EQ
        DA NOT
        BRANCH_TO .GOOD
        DA EINIT
        DA PRINT
        DA ABORT

        .GOOD:
        DA IN
        DA STORE

        DA RETURN

    STRING EINIT, `INIT.MINI NOT FOUND\n`

    ; PTR SIZE --
    PROCEDURE PRINT
        DA STDOUT
        DA LOAD
        DA WFILE
        DA ASSERT
        DA DROP
        DA RETURN

    VARIABLE IN_BUF, (CONFIG_IN_BUF_SIZE / 8) + 1
    VARIABLE IN_END, 1
    CONSTANT IN_LIM, CONFIG_IN_BUF_SIZE
    VARIABLE IN, 1

    ; -- EOF?
    PROCEDURE IN_FILL
        DA IN_BUF
        DA COPY
        DA IN_PTR
        DA STORE
        DA IN_LIM
        DA IN
        DA LOAD
        DA RFILE
        BRANCH_TO .SUCCESS
        DA ERROR
        LITERAL 0X6D
        DA EQ
        BRANCH_TO .SUCCESS
        DA CRASH

        .SUCCESS:
        DA COPY
        DA IN_BUF
        DA ADD
        DA ZEROES
        DA OVER
        DA BSTORE
        DA IN_END
        DA STORE
        DA ZEROES
        DA EQ
        DA RETURN

    ; VALUE -- VALUE
    PROCEDURE ASSERT
        DA COPY
        DA ZEROES
        DA EQ
        DA NOT
        BRANCH_TO .OK
        DA CRASH

        .OK:
        DA RETURN

    CONSTANT ZEROES, 0
    VARIABLE IN_PTR, 1

    ; -- EOF?
    PROCEDURE PRS_NXT
        DA PRS_BUF
        DA PRS_PTR
        DA STORE

        DA PRS_RMS
        BRANCH_TO .EOF

        DA PRS_RD
        BRANCH_TO .EOF

        DA ZEROES
        DA RETURN

        .EOF:
        DA ONES
        DA RETURN

    ; STRING LENGTH --
    PROCEDURE PRS_MOV
        DA PRS_PTR
        DA LOAD
        DA OVER
        DA OVER
        DA ADD
        DA PRS_PTR
        DA STORE

        DA SCOPY
        DA RETURN

    ; -- EOF?
    PROCEDURE PRS_RD
        .AGAIN:
        DA IN_PTR
        DA LOAD
        DA COPY
        DA PRS_NWS
        DA OVER
        DA OVER
        DA OVER
        DA SUB
        DA COPY
        DA PRS_RES
        BRANCH_TO .TOO_LONG
        DA PRS_MOV
        DA SWAP
        DA DROP
        DA IN_ADV
        BRANCH_TO .EOF
        BRANCH_TO .AGAIN

        DA ZEROES
        DA RETURN

        .EOF:
        DA DROP
        DA ONES
        DA RETURN

        .TOO_LONG:
        DA DROP
        DA DROP
        DA DROP
        DA DROP
        DA PRS_BUF
        LITERAL 1
        DA SUB
        DA PRS_PTR
        DA STORE
        DA ZEROES
        DA RETURN

    ; LENGTH -- TOO-LONG?
    PROCEDURE PRS_RES
        DA PRS_SZ
        DA ADD
        DA PRS_LIM
        DA GT
        DA RETURN

    ; -- STRING LENGTH
    PROCEDURE PRS_WRD
        DA PRS_BUF
        DA PRS_PTR
        DA LOAD
        DA OVER
        DA SUB
        DA RETURN

    ; -- OCCUPIED-BYTES
    PROCEDURE PRS_SZ
        DA PRS_PTR
        DA LOAD
        DA PRS_BUF
        DA SUB
        DA RETURN

    ; -- EOF?
    PROCEDURE PRS_RMS
        .AGAIN:
        DA IN_PTR
        DA LOAD
        DA PRS_WS
        DA IN_ADV
        BRANCH_TO .EOF
        BRANCH_TO .AGAIN
        DA ZEROES
        DA RETURN

        .EOF:
        DA DROP
        DA ONES
        DA RETURN

    CONSTANT ONES, ~0

    ; READ-PTR -- FRESH-INPUT? EOF?
    PROCEDURE IN_ADV
        DA COPY
        DA IN_PTR
        DA STORE
        DA IN_END
        DA LOAD
        DA EQ
        DA COPY
        BRANCH_TO .REFILL
        DA ZEROES
        DA RETURN

        .REFILL:
        DA IN_FILL
        DA RETURN

    VARIABLE PRS_BUF, CONFIG_PRS_BUFFER_SIZE / 8
    CONSTANT PRS_LIM, CONFIG_PRS_BUFFER_SIZE
    VARIABLE PRS_PTR, 1

    NAME KERNEL32, "kernel32.dll"
    NAME ExitProcess, "ExitProcess"
    NAME GetStdHandle, "GetStdHandle"
    NAME WriteFile, "WriteFile"
    NAME ReadFile, "ReadFile"
    NAME GetLastError, "GetLastError"
    NAME CreateFileA, "CreateFileA"

    STRING ETOK, `TOKEN TOO LONG\n`
    STRING EFIND, ` ?\n`

    ; NAME LENGTH -- ENTRY?
    PROCEDURE FIND
        DA DICT
        DA LOAD
        DA PUSH

        .NEXT:
        DA OVER
        DA OVER
        DA POP
        DA COPY
        DA PUSH
        DA DE_NAME
        DA SEQ
        BRANCH_TO .FOUND
        DA POP
        DA LOAD
        DA COPY
        DA PUSH
        BRANCH_TO .NEXT

        .FOUND:
        DA DROP
        DA DROP
        DA POP
        DA RETURN

    VARIABLE MODE, 1
    VARIABLE ARENA, CONFIG_ARENA_SIZE / 8
    VARIABLE HERE, 1
    CONSTANT LIMIT, CONFIG_ARENA_SIZE

    ; --
    PROCEDURE BEGIN
        DA ONES
        DA MODE
        DA STORE
        DA RETURN

    ; --
    IMMEDIATE
    PROCEDURE END
        DA ZEROES
        DA MODE
        DA STORE
        DA RETURN

    ; VALUE --
    PROCEDURE ASM
        DA HERE
        DA LOAD
        DA STORE
        DA HERE
        DA COPY
        DA LOAD
        LITERAL 8
        DA ADD
        DA SWAP
        DA STORE
        DA RETURN

    ; VALUE --
    PROCEDURE BASM
        DA HERE
        DA LOAD
        DA BSTORE
        DA HERE
        DA COPY
        DA LOAD
        LITERAL 1
        DA ADD
        DA SWAP
        DA STORE
        DA RETURN

    CONSTANT FFI, ADDRESS(IMPORTS)

    ; --
    PROCEDURE NEWHDR
        DA HERE
        DA LOAD
        DA DICT
        DA LOAD
        DA ASM
        DA DICT
        DA STORE
        DA PRS_NXT
        DA DROP
        DA PRS_WRD
        DA COPY
        DA BASM
        DA COPY
        DA PUSH
        DA HERE
        DA LOAD
        DA SCOPY
        DA POP
        DA HERE
        DA LOAD
        DA ADD
        DA HERE
        DA STORE
        DA HERE
        DA LOAD
        DA CALIGN
        DA HERE
        DA STORE
        DA RETURN

SECTION .bss
    RSTACK:
        RESQ STACK_DEPTH

    DSTACK:
        RESQ STACK_DEPTH

    IMPORTS:
    GetProcAddress:
        RESQ 1

    GetModuleHandleA:
        RESQ 1

    ExitProcess:
        RESQ 1

    GetStdHandle:
        RESQ 1

    WriteFile:
        RESQ 1

    ReadFile:
        RESQ 1

    GetLastError:
        RESQ 1

    CreateFileA:
        RESQ 1

SECTION .rdata
    FINALIZE_DICTIONARY KERNEL

SECTION .bss
    BSS_END:

SECTION .rdata
    ALIGN 8
    DQ BSS_END - BSS_START
