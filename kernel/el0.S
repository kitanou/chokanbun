// EL0 / 漢令 (syscall) boundary for the Chokanbun kernel.
//
// This is the only place the kernel crosses the EL1/EL0 boundary.  As with the
// other entry points it is provisional assembly (language spec §7); the 漢令
// dispatch and the user task itself are machine-kanbun (kernel/kernel.txt).
//
//   * user_entry_addr()  – address of the machine-kanbun EL0 task entry,
//   * enter_el0()        – eret to EL0 at an address with a given stack,
//   * lower_sync_handler – Lower-EL synchronous vector (SVC from EL0).
//
// 漢令ABI v0.1 (docs/abi-aarch64.md): x8 = 番号, x0..x5 = 引数, x0 = 戻り値,
// `svc #0`.

    .text

// svc_call(nr, a0..a5): issue the 漢令ABI v0.1 `svc #0`.
//   in:  x0 = 番号, x1..x6 = 引数 (AAPCS64)
//   ->   x8 = 番号, x0..x5 = 引数, `svc #0`, x0 = 戻り値.
    .globl svc_call
svc_call:
    mov x8, x0
    mov x0, x1
    mov x1, x2
    mov x2, x3
    mov x3, x4
    mov x4, x5
    mov x5, x6
    svc #0
    ret

// user_entry_addr(): return the address of the EL0 task entry (view: user_main).
    .globl user_entry_addr
user_entry_addr:
    adrp x0, user_main
    add  x0, x0, :lo12:user_main
    ret

// enter_el0(entry, sp, arg): eret to EL0 at `entry` with SP_EL0 = sp and the
// first argument in x0.  SPSR_EL1 = EL0t with DAIF masked: the task runs
// without preemption until a scheduler exists (M3).
    .globl enter_el0
enter_el0:
    msr elr_el1, x0
    msr sp_el0, x1
    mov x3, #0x3C0
    msr spsr_el1, x3
    mov x0, x2
    eret

// Lower-EL synchronous entry (vector offset 0x400).
//
// The exception is taken to EL1 with SP_EL1 (EL1h).  Save the EL0 registers and
// NZCV, hand ESR_EL1 and a pointer to the saved frame to 漢令處理
// (svc_dispatch), then either restore and eret back to EL0 or, when the handler
// returns 1 (行程終了), park the CPU at EL1.
//
// Frame layout (256 bytes) matches the other handlers: x0..x29 at 0..232,
// x30 at 240, NZCV at 248.
    .globl lower_sync_handler
lower_sync_handler:
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

    mrs x0, esr_el1
    mov x1, sp
    bl svc_dispatch
    cmp x0, #1
    b.eq el0_park

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

// 行程終了: the user task is done; stay at EL1 and idle.
el0_park:
1:  wfi
    b 1b
