// Chokanbun kernel boot stub for QEMU virt / AArch64.
//
// QEMU's -kernel entry starts the image at EL1 with a single CPU, so this stub
// only has to establish the machine state the machine-kanbun kernel expects:
//
//   1. point SP at the reserved kernel stack,
//   2. zero the .bss section,
//   3. install the exception vector table in VBAR_EL1,
//   4. transfer control to 核主 (ELF symbol `main`).
//
// Hand-written assembly here is provisional and confined to the boot entry
// (language spec §7); the kernel proper lives in kernel/kernel.mkn.

    .section .text.boot, "ax"
    .globl _start

_start:
    // 1. Kernel stack (top symbol provided by kernel.lds).
    ldr x0, =_stack_top
    mov sp, x0

    // 2. Zero .bss.
    ldr x0, =__bss_start
    ldr x1, =__bss_end
zero_bss:
    cmp x0, x1
    b.hs zero_bss_done
    str xzr, [x0], #8
    b zero_bss
zero_bss_done:

    // 3. Install the exception vector table.
    ldr x0, =_vectors
    msr vbar_el1, x0
    isb

    // 4. Enter the machine-kanbun kernel.
    bl main

halt:
    wfi
    b halt
