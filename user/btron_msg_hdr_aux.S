// Auxiliary assembly for the 信手試 image (user/btron_msg_hdr.mkn).
//
// 機械漢文には関数のアドレスを取る式が無いので、メッセージハンドラのアドレスは
// このファイルから ELF 記號で取り出す。mkimage.sh は user/<name>_aux.S が
// あれば自動でリンクする。

    .text

.macro MSG_ADDR name, target
    .globl \name
\name:
    adrp x0, \target
    add  x0, x0, :lo12:\target
    ret
.endm

    MSG_ADDR msg_handler_a_addr, msg_handler_a
    MSG_ADDR msg_handler_b_addr, msg_handler_b
    MSG_ADDR msg_handler_c_addr, msg_handler_c
    MSG_ADDR msg_handler_d_addr, msg_handler_d
    MSG_ADDR msg_handler_e_addr, msg_handler_e
    MSG_ADDR msg_handler_f_addr, msg_handler_f
