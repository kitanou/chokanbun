// AArch64 exception vector table and common entry for the Chokanbun kernel.
//
// The table holds 16 entries spaced 0x80 bytes apart (0x800 total) and must be
// 2 KiB aligned.  Entries 5-8 (offset 0x200+) handle exceptions taken at the
// current EL with SP_ELx ("EL1h"), which is where the kernel runs; entry 5
// (offset 0x200) is the synchronous case we exercise with `brk #0`.
//
// The register save/restore and system-register access below is provisional
// assembly (language spec §7).  The diagnostic logic itself is the
// machine-kanbun function 異常處理, visible to the linker as
// `exception_dispatch`.

    .section .vectors, "ax"
    .p2align 11
    .globl _vectors

_vectors:
    // ---- Current EL with SP0 (not used: kernel runs on SP_EL1) ----
    .p2align 7; b exception_handler       // Synchronous
    .p2align 7; b exception_handler       // IRQ
    .p2align 7; b exception_handler       // FIQ
    .p2align 7; b exception_handler       // SError

    // ---- Current EL with SPx (EL1h) ----
    .p2align 7; b exception_handler       // Synchronous
    .p2align 7; b irq_handler             // IRQ
    .p2align 7; b exception_handler       // FIQ
    .p2align 7; b exception_handler       // SError

    // ---- Lower EL using AArch64 (EL0) ----
    .p2align 7; b lower_sync_handler      // Synchronous (SVC)
    .p2align 7; b lower_irq_handler       // IRQ (timer preemption of EL0 行程)
    .p2align 7; b exception_handler       // FIQ
    .p2align 7; b exception_handler       // SError

    // ---- Lower EL using AArch32 ----
    .p2align 7; b exception_handler
    .p2align 7; b exception_handler
    .p2align 7; b exception_handler
    .p2align 7; b exception_handler

// Common exception entry.
//   * save the general-purpose registers,
//   * hand ESR_EL1 and ELR_EL1 to 異常處理 (exception_dispatch),
//   * resume at the address it returns.
exception_handler:
    sub sp, sp, #256
    stp x0,  x1,  [sp, #0]
    stp x2,  x3,  [sp, #16]
    stp x4,  x5,  [sp, #32]
    stp x6,  x7,  [sp, #48]
    stp x8,  x9,  [sp, #64]
    stp x10, x11, [sp, #80]
    stp x12, x13, [sp, #96]
    stp x14, x15, [sp, #112]
    stp x16, x17, [sp, #128]
    stp x18, x19, [sp, #144]
    stp x20, x21, [sp, #160]
    stp x22, x23, [sp, #176]
    stp x24, x25, [sp, #192]
    stp x26, x27, [sp, #208]
    stp x28, x29, [sp, #224]
    str x30, [sp, #240]

    mrs x0, esr_el1
    mrs x1, elr_el1
    bl exception_dispatch
    msr elr_el1, x0

    ldr x30, [sp, #240]
    ldp x28, x29, [sp, #224]
    ldp x26, x27, [sp, #208]
    ldp x24, x25, [sp, #192]
    ldp x22, x23, [sp, #176]
    ldp x20, x21, [sp, #160]
    ldp x18, x19, [sp, #144]
    ldp x16, x17, [sp, #128]
    ldp x14, x15, [sp, #112]
    ldp x12, x13, [sp, #96]
    ldp x10, x11, [sp, #80]
    ldp x8,  x9,  [sp, #64]
    ldp x6,  x7,  [sp, #48]
    ldp x4,  x5,  [sp, #32]
    ldp x2,  x3,  [sp, #16]
    ldp x0,  x1,  [sp, #0]
    add sp, sp, #256

    eret

// Common IRQ entry for exceptions taken at EL1h (kernel).  Like the
// synchronous entry, but asynchronous: it also preserves NZCV because the
// interrupted computation may depend on the flags.  The acknowledge/
// end-of-interrupt and timer logic live in machine-kanbun
// (kernel/kernel.mkn, 割込處理).  Timer interrupts taken while an EL0 行程 runs
// use the Lower-EL IRQ vector instead (kernel/el0.S, lower_irq_handler).
irq_handler:
    sub sp, sp, #256
    stp x0,  x1,  [sp, #0]
    stp x2,  x3,  [sp, #16]
    stp x4,  x5,  [sp, #32]
    stp x6,  x7,  [sp, #48]
    stp x8,  x9,  [sp, #64]
    stp x10, x11, [sp, #80]
    stp x12, x13, [sp, #96]
    stp x14, x15, [sp, #112]
    stp x16, x17, [sp, #128]
    stp x18, x19, [sp, #144]
    stp x20, x21, [sp, #160]
    stp x22, x23, [sp, #176]
    stp x24, x25, [sp, #192]
    stp x26, x27, [sp, #208]
    stp x28, x29, [sp, #224]
    str x30, [sp, #240]
    mrs x2, nzcv
    str x2, [sp, #248]

    bl irq_dispatch

    ldr x2, [sp, #248]
    msr nzcv, x2
    ldr x30, [sp, #240]
    ldp x28, x29, [sp, #224]
    ldp x26, x27, [sp, #208]
    ldp x24, x25, [sp, #192]
    ldp x22, x23, [sp, #176]
    ldp x20, x21, [sp, #160]
    ldp x18, x19, [sp, #144]
    ldp x16, x17, [sp, #128]
    ldp x14, x15, [sp, #112]
    ldp x12, x13, [sp, #96]
    ldp x10, x11, [sp, #80]
    ldp x8,  x9,  [sp, #64]
    ldp x6,  x7,  [sp, #48]
    ldp x4,  x5,  [sp, #32]
    ldp x2,  x3,  [sp, #16]
    ldp x0,  x1,  [sp, #0]
    add sp, sp, #256

    eret
