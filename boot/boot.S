// Minimal boot code for QEMU virt / AArch64
// Sets up a stack and transfers control to 核主 (emitted as the `main` symbol).
//
// QEMU virt: RAM at 0x40000000, UART (PL011) at 0x09000000.
// The PL011 is enabled at reset, so no explicit UART init is required here.

    .section .text.boot
    .globl _start

_start:
    // Stack top: 2 MiB above the RAM base, safely inside QEMU's default RAM.
    ldr x0, =0x40200000
    mov sp, x0

    // Call 核主 (main produced from machine-kanbun)
    bl main

    // If main returns, halt.
halt:
    wfi
    b halt
