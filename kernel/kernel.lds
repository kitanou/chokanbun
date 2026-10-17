/* Linker script for the Chokanbun kernel (QEMU virt / AArch64, EL1).
 *
 * RAM starts at 0x40000000 on QEMU virt.  The kernel is laid out across the
 * 2 MiB translation blocks described in kernel/kernel.mkn (設頁表):
 *
 *   0x40000000  .text/.vectors/.rodata  EL1 RO+exec, EL0 RO+exec (user code)
 *   0x40200000  .data/.bss/kernel stack EL1 RW, EL0 no access
 *
 * The executable image and the kernel stack must live in *different* 2 MiB
 * blocks because, for the AArch64 EL1&0 regime, a block that is writable at
 * EL0 is never executable at EL1 (ARM stage-1 rule) -- and the user task needs
 * an EL0-writable stack somewhere.
 *
 * The exception vector table must be 2 KiB aligned, so it is placed on its own
 * alignment boundary right after the boot stub.
 */

ENTRY(_start)

SECTIONS
{
    . = 0x40000000;

    .text : {
        *(.text.boot)
    }

    /* AArch64 exception vector table: 16 entries of 0x80 bytes, 2 KiB aligned. */
    . = ALIGN(0x800);
    .vectors : {
        KEEP(*(.vectors))
    }

    .text.rest : {
        *(.text)
        *(.text.*)
    }

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    }

    /* Writable image: a separate 2 MiB block (see 設頁表). */
    . = 0x40200000;

    .data : {
        *(.data)
        *(.data.*)
    }

    .bss (NOLOAD) : ALIGN(16) {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        __bss_end = .;
    }

    /* Kernel stack: 16 KiB growing down from _stack_top. */
    . = ALIGN(16);
    . = . + 0x4000;
    _stack_top = .;

    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.eh_frame)
    }
}
