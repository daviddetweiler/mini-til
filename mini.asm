default rel
bits 64

global start

extern VirtualAlloc
extern GetModuleHandleA
extern GetProcAddress

%define image_base 0x2000000000

%define upper8 (((1 << 8) - 1) << (64 - 8))
%define flag_extra_byte 0x80

%define node_size (2 * 8 + 2 * 8 + 8) ; Children, counts, total_count
%define total_nodes (1023) ; Magic number, but known from the python implementation

section .text
    start:
        sub rsp, 8 + 8 * 16

    init_models:
        ; r15 will be the node arena pointer
        xor rcx, rcx
        mov rdx, (total_nodes * node_size)
        call allocate
        mov r15, rax

        mov r14, r15 ; root node
        call make_node

        mov r13, r15 ; dummy node
        mov [r13 + 8], r13
        mov [r13], r13
        call make_node

        mov rsi, r14
        call make_15bit_model ; length model in rsi
        call make_15bit_model ; offset model in rsi
        mov rdi, rsi ; dict entry model in rdi

        mov rcx, r14
        mov dl, 8
        call make_bitstring ; rsi now points to the literal model
        mov rsi, rax

        mov [r14], rsi
        mov [r14 + 8], rdi
        mov r15, r14 ; r15 now points to the packet model
        mov r14, r13 ; r14 now points to the dummy model

    prepare_decoder:
        xor r13, r13 ; r13 = arithmetic decoder lower bound
        xor r12, r12 ; r12 = arithmetic decoder upper bound
        xor r11, r11 ; r11 = arithmetic decoder 64-bit window
        xor r10, r10 ; r10 = bitstream unconsumed byte index

        not r12 ; set all ones

        .next_init:
        shl r11, 8
        lea rax, bitstream
        mov r11b, [rax + r10]
        inc r10
        test r10, 7
        jnz .next_init

    prepare_decompression:
        xchg r15, r14
        call decode_literal_dword

        push r11
        push r10

        mov rcx, image_base
        mov edx, eax
        call allocate
        mov rdi, rax ; rdi = decompression buffer address

        pop r10
        pop r11

        call decode_literal_dword
        xchg r15, r14
        mov r14d, eax ; r14 = expected bytes to unpack

    lzss_unpack:
        .next_command:
        mov r8b, 1
        call decode

        test al, 0x1
        jz .literal

        .copy_command:
        call decode_byte
        xor rsi, rsi
        mov sil, al

        test sil, flag_extra_byte
        jz .get_length

        xor sil, flag_extra_byte ; clear the flag
        shl rsi, 8

        call decode_byte
        mov sil, al

        .get_length:
        call decode_byte

        shl rsi, 32
        mov sil, al

        test sil, flag_extra_byte
        jz .copy_loop

        xor sil, flag_extra_byte ; clear the flag
        shl si, 8

        call decode_byte
        mov sil, al

        .copy_loop: ; By now the upper 32 bits of rsi are the offset, and the lower 32 bits are the length
        mov rbx, rsi
        shr rbx, 32
        neg rbx
        mov esi, esi
        sub r14, rsi

        .next_byte:
        mov al, [rdi + rbx]
        stosb
        dec rsi
        jnz .next_byte

        jmp .advance

        .literal:
        call decode_byte
        dec r14
        stosb

        .advance:
        test r14, r14
        jnz .next_command

    load:
        mov rax, image_base + 8
        lea rcx, GetModuleHandleA
        lea rdx, GetProcAddress
        jmp rax

    allocate:
        sub rsp, 8 + 8 * 4

        mov r8, 0x1000 | 0x2000 ; MEM_COMMIT | MEM_RESERVE
        mov r9, 0x40 ; PAGE_EXECUTE_READWRITE
        call VirtualAlloc

        add rsp, 8 + 8 * 4
        ret

    make_node:
        xor rax, rax
        inc rax
        mov [r15 + 8 * 3], rax
        mov [r15 + 8 * 4], rax
        inc rax
        mov [r15 + 8 * 2], rax
        add r15, node_size
        ret

    ; rcx = root, rdx = bits
    make_bitstring:
        mov rax, rcx
        test dl, dl
        jz .finished
        dec dl
        call make_bitstring
        push rax
        call make_bitstring
        inc dl
        mov [r15], rax
        pop qword [r15 + 8]
        call make_node
        lea rax, [r15 - node_size]
        .finished:
        ret

    make_15bit_model:
        mov rcx, rsi
        mov dl, 7
        call make_bitstring ; rsi now points to the short_length model
        mov rsi, rax

        mov rcx, rsi
        mov dl, 8
        call make_bitstring ; rdi now points to the ext_length model
        mov rdi, rax

        mov [r15], rsi
        mov rsi, r15 ; rsi now points to the length model
        mov [r15 + 8], rdi
        call make_node

        ret

    ; This will perform the arithmetic decode and return the symbols in rax.
    ; WARNING the unwritten bits of rax are undefined, so mask them off before using.
    ; WARNING the symbols are written in reverse order, so you must reverse them before using.
    ; r8 = number of symbols to decode
    ; High register pressure here, r15-r10 in use, as is rdi, rcx, r8, rdx
    decode:
        push rsp

        .next_symbol:
        lea rcx, [r15 + 8 * 3] ; rcx = model data, ptr is between total and counts
        mov rbx, r12
        sub rbx, r13 ; rbx = interval width

        xor r9, r9 ; r9 = trial symbol

        .next_subinterval:
        mov rdx, [rcx + r9 * 8] ; rdx = symbol frequency
        xor rax, rax
        div qword [rcx - 8] ; rax = symbol probability
        xor rdx, rdx
        mul rbx ; rdx = subinterval width

        add rdx, r13 ; rdx = subinterval lower bound
        cmp rdx, r11 ; range check
        jb .advance_subinterval
        mov r12, rdx ; update upper bound
        shl qword [rsp], 1
        or [rsp], r9b ; store symbol
        inc qword [rcx + r9 * 8] ; update model
        inc qword [rcx - 8] ; update model
        mov r15, [r15 + r9 * 8] ; r15 = next model
        jmp .renormalize

        .advance_subinterval:
        mov r13, rdx ; update lower bound
        inc r9
        jmp .next_subinterval

        .renormalize:
        mov rbx, r12
        xor rbx, r13 ; any clear bits are the "frozen" bits
        mov al, 0xff
        shl rax, 64 - 8
        test rbx, rax ; check if we have 8 frozen bits at the top
        jnz .adjust_convergence
        shl r12, 8 ; renormalize
        not r12b ; set all ones in the lower 8 bits
        shl r13, 8
        shl r11, 8
        lea rax, bitstream
        mov r11b, [rax + r10]
        inc r10
        jmp .renormalize

        .adjust_convergence:
        mov rax, r13
        mov rbx, r12
        shr rax, 64 - 8
        shr rbx, 64 - 8 
        sub rbx, rax
        cmp rbx, 1
        jne .adjusted

        .next_adjustment:
        mov rax, r13
        mov rbx, r12
        shr rax, 64 - 16
        shr rbx, 64 - 16
        cmp al, 0xff
        jne .adjusted
        test bl, bl
        jne .adjusted

        mov r9, r13
        call strange_shift
        mov r13, r9

        mov r9, r12
        call strange_shift
        mov r12, r9
        not r12b

        mov r9, r11
        call strange_shift
        mov r11, r9

        lea rax, bitstream
        mov r11b, [rax + r10]
        inc r10
        jmp .next_adjustment

        .adjusted:
        dec r8b
        jnz .next_symbol

        pop rax ; rax = decoded symbols
        ret

    decode_byte:
        mov r8b, 8
        call decode
        ret

    decode_literal_dword:
        mov r8b, 32
        call decode
        ret

    strange_shift:
        mov rbx, r9
        mov al, 0xff
        shl rax, 64 - 8
        and rbx, rax
        shl r9, 8
        andn r9, rax, r9
        or r9, rbx
        ret

    bitstream:
        %include "bitstream.inc"

    db `\0\0\0\0\0\0\0\0` ; You do not want garbage data entering the bitstream near the end
