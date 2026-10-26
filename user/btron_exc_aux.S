// Auxiliary assembly for the 例試 image (user/btron_exc.mkn).
//
// 機械漢文には関数のアドレスを取る式が無いので、例外ハンドラのアドレスは
// このファイルから ELF 記號で取り出す。mkimage.sh は user/<name>_aux.S が
// あれば自動でリンクする (この像だけの補助)。

    .text

// void exc_brk(void): raise a BRK from EL0 (lower-EL synchronous exception).
    .globl exc_brk
exc_brk:
    brk #0
    ret

.macro EXC_ADDR name, target
    .globl \name
\name:
    adrp x0, \target
    add  x0, x0, :lo12:\target
    ret
.endm

    EXC_ADDR exc_handler_a_addr, exc_handler_a
    EXC_ADDR exc_handler_b_addr, exc_handler_b
    EXC_ADDR exc_handler_c_addr, exc_handler_c
    EXC_ADDR exc_handler_d_addr, exc_handler_d
    EXC_ADDR exc_handler_e_addr, exc_handler_e
    EXC_ADDR exc_handler_f_addr, exc_handler_f
