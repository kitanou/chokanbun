@ Minimal boot code for QEMU virt / AArch64
@ Sets up stack, UART, and calls main (核主)
@
@ QEMU virt: RAM at 0x40000000, UART (PL011) at 0x09000000

    .section .text.boot
    .globl _start

    @ QEMU virt RAM starts at 0x40000000
    set x19, #0x40000000   @ RAM base

_start:
    @ Set up stack at end of first 1MB
    ldr x0, =0x40100000    @ stack top
    mov sp, x0

    @ Initialize UART (PL011)
    ldr x0, =0x09000000    @ UART base
    mov x1, #0             @ disable
    str x1, [x0, #0x000]  @ UARTCR = 0
    mov x1, #0x300         @ 38400 baud (115200 would be 0x600)
    str x1, [x0, #0x0C0]  @ UBAUD
    mov x1, #0x08          @ 8n1
    str x1, [x0, #0x004]  @ LCR
    mov x1, #0x0300        @ enable TX and RX
    str x1, [x0, #0x000]  @ UARTCR

    @ Call main (核主)
    bl main

    @ If main returns, halt
halt:
    wfi
    b halt

    .section .data
    .align 3
    .quad 0x40100000
