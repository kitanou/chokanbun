// EL0 / 漢令 (syscall) boundary for the Chokanbun kernel.
//
// This is the only place the kernel crosses the EL1/EL0 boundary.  As with the
// other entry points it is provisional assembly (language spec §7); the 漢令
// dispatch and the user task itself are machine-kanbun (kernel/kernel.mkn).
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

// Exception-handler return trampoline.  例外飛 sets a handler's x30 to this
// address; a handler that returns without calling ret_exc is treated as
// ret_exc(0) and resumes the interrupted instruction.  The first SVC should
// never return for ret=0, so the loop is only a guard.
    .globl exc_return_stub
exc_return_stub:
    mov x0, #0
    mov x8, #182
    svc #0
1:  b 1b

// Message-handler return trampoline.  メッセージ配送 sets a handler's x30 to
// this address; a handler that returns without calling ret_msg is treated as
// ret_msg(0) and resumes the interrupted position.
    .globl msg_return_stub
msg_return_stub:
    mov x0, #0
    mov x8, #184
    svc #0
1:  b 1b

// exc_return_stub_addr(): EL0 address of exc_return_stub (kernel code is mapped
// EL0 RO+X, so the trampoline is executable from the user handler).
    .globl exc_return_stub_addr
exc_return_stub_addr:
    adrp x0, exc_return_stub
    add  x0, x0, :lo12:exc_return_stub
    ret

// msg_return_stub_addr(): EL0 address of msg_return_stub.
    .globl msg_return_stub_addr
msg_return_stub_addr:
    adrp x0, msg_return_stub
    add  x0, x0, :lo12:msg_return_stub
    ret

// user_entry_addr(): return the address of the EL0 task entry (view: user_main).
    .globl user_entry_addr
user_entry_addr:
    adrp x0, user_main
    add  x0, x0, :lo12:user_main
    ret

// enter_el0(entry, sp, arg, kernel_sp): eret to EL0 at `entry` with SP_EL0 = sp,
// the first argument in x0, and SP_EL1 set to the 行程's own kernel stack top.
// The kernel runs at EL1h, so the current `sp` *is* SP_EL1.
// SPSR_EL1 = EL0t with DAIF masked: the task runs without preemption until it
// asks for it (開先取 / 番7).
    .globl enter_el0
enter_el0:
    mov sp, x3
    msr elr_el1, x0
    msr sp_el0, x1
    mov x4, #0x3C0
    msr spsr_el1, x4
    mov x0, x2
    eret

// Lower-EL synchronous entry (vector offset 0x400).
//
// The exception is taken to EL1 with SP_EL1 (EL1h).  Save the EL0 registers,
// NZCV, ELR_EL1, SPSR_EL1 and SP_EL0 to a 288-byte frame on the kernel stack,
// hand ESR_EL1 and the frame pointer to 漢令處理 (svc_dispatch), then resume from
// the frame the handler points at (allowing a context switch) and eret.
//
// svc_dispatch returns a frame pointer to resume from, or 0 when no 行程 is
// runnable (park at EL1).
//
// Frame layout (288 bytes):
//   x0..x29  at   0..232   (30 registers)
//   x30      at 240
//   NZCV     at 248
//   ELR_EL1  at 256
//   SPSR_EL1 at 264
//   SP_EL0   at 272
    .globl lower_sync_handler
lower_sync_handler:
    sub sp, sp, #288
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
    mrs x2, elr_el1
    str x2, [sp, #256]
    mrs x2, spsr_el1
    str x2, [sp, #264]
    mrs x2, sp_el0
    str x2, [sp, #272]

    mrs x0, esr_el1
    mov x1, sp
    bl svc_dispatch
    cbz x0, el0_park
    mov sp, x0                 // resume from the frame the handler selected
    b el0_resume

// Lower-EL IRQ entry (vector offset 0x480): the timer interrupt taken while an
// EL0 行程 runs.  It saves the same 288-byte frame as the SVC path and hands the
// frame pointer to 割込切替 (irq_switch), which acknowledges the GIC, advances
// the tick counter, rearms the timer and asks 排程 to pick the next 行程.  The
// machine-kanbun handler returns a frame pointer to resume from (possibly a
// different 行程), or 0 when no 行程 is runnable.
    .globl lower_irq_handler
lower_irq_handler:
    sub sp, sp, #288
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
    mrs x2, elr_el1
    str x2, [sp, #256]
    mrs x2, spsr_el1
    str x2, [sp, #264]
    mrs x2, sp_el0
    str x2, [sp, #272]

    mov x0, sp
    bl irq_switch
    cbz x0, el0_park
    mov sp, x0                 // resume from the frame the handler selected
    // fall through to the shared EL0 resume path

// Resume an EL0 行程 from the 288-byte frame at SP.  SP has already been set to
// the frame the machine-kanbun handler selected (its own kernel stack).
el0_resume:
    // The frame now holds the state of the 行程 to resume (possibly a different
    // one than entered this handler).
    ldr x2, [sp, #248]
    msr nzcv, x2
    ldr x2, [sp, #256]
    msr elr_el1, x2
    ldr x2, [sp, #264]
    msr spsr_el1, x2
    ldr x2, [sp, #272]
    msr sp_el0, x2

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
    add sp, sp, #288

    eret

// No runnable 行程 is left: idle at EL1.  idle_poll (閑巡, kernel/proc/sync.mkn) polls
// the GIC (IRQs stay masked; WFI still wakes on a pending timer interrupt), runs the
// timeout wake-ups and returns a frame to resume when a 行程 became runnable, else 0.
el0_park:
    bl idle_poll
    cbz x0, 2f
    mov sp, x0
    b el0_resume
2:  wfi
    b el0_park
