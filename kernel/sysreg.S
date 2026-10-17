// System-register helpers for the Chokanbun kernel (provisional, spec §7).
//
// The machine-kanbun page-table builder (kernel/kernel.txt, 設頁表) writes the
// translation tables into memory; these thin helpers program the system
// registers that turn translation on.
//
// enable_mmu(x0 = level-1 table base, physical, 4 KiB aligned):
//   Identity map produced by the builder:
//     index 0: 0x00000000-0x3FFFFFFF  Device-nGnRnE  (PL011 UART, GIC)
//     index 1: 0x40000000-0x7FFFFFFF  Normal, WB     (RAM, kernel, stack)
//   T0SZ = 33 selects a 2 GiB region starting at level 1 (1 GiB blocks).

    .section .text.sysreg, "ax"

    .globl enable_mmu
enable_mmu:
    ldr x1, =0x00FF            // MAIR_EL1: Attr0 = Normal WB, Attr1 = Device
    msr mair_el1, x1

    msr ttbr0_el1, x0          // translation table base (ASID 0)

    ldr x1, =0x200903521       // TCR_EL1: T0SZ=33, TG0=4K, WB, inner-shareable
    msr tcr_el1, x1

    dsb sy
    isb

    mrs x1, sctlr_el1
    bic x1, x1, #0x400000      // SCTLR_EL1.PAN : allow EL1 data access to
                               //   memory that is also writable at EL0
                               //   (the user stack block, AP=0b01)
    orr x1, x1, #1             // SCTLR.M : enable MMU
    orr x1, x1, #4             // SCTLR.C : enable data cache
    orr x1, x1, #4096          // SCTLR.I : enable instruction cache
    msr sctlr_el1, x1
    isb
    ret

// read_sctlr(): return SCTLR_EL1 so the kernel can confirm translation is on.
    .globl read_sctlr
read_sctlr:
    mrs x0, sctlr_el1
    ret

// ---- ARM generic timer (EL1 physical timer, CNTP) -----------------------
// timer_start(x0 = ticks): arm CNTP_TVAL_EL0 and enable the timer interrupt.
    .globl timer_start
timer_start:
    msr cntp_tval_el0, x0
    mov x1, #1
    msr cntp_ctl_el0, x1       // ENABLE=1, IMASK=0
    ret

// timer_rearm(x0 = ticks): reload the down-counter (interrupt stays enabled).
    .globl timer_rearm
timer_rearm:
    msr cntp_tval_el0, x0
    ret

// timer_stop(): disable the timer interrupt.
    .globl timer_stop
timer_stop:
    msr cntp_ctl_el0, xzr
    ret

// read_cntfrq(): CNTFRQ_EL0, the system counter frequency in Hz.
    .globl read_cntfrq
read_cntfrq:
    mrs x0, cntfrq_el0
    ret

// ---- CPU interrupt control ---------------------------------------------
// local_irq_enable(): clear PSTATE.I so IRQs are delivered.
    .globl local_irq_enable
local_irq_enable:
    msr daifclr, #2
    ret

// wait_irq(): idle until an IRQ (or other wake event) arrives.
    .globl wait_irq
wait_irq:
    wfi
    ret
