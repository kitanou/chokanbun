/* Linker script for the Chokanbun kernel (QEMU virt / AArch64, EL1).
 *
 * RAM starts at 0x40000000 on QEMU virt.  The exception vector table must be
 * 2 KiB aligned, so it is placed on its own alignment boundary right after the
 * boot stub.
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
