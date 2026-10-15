/* Linker script for QEMU virt / AArch64 */
/* RAM starts at 0x40000000 */

ENTRY(_start)

SECTIONS
{
    . = 0x40000000;

    .text : {
        *(.text.boot)
        *(.text)
    }

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    }

    .data : {
        *(.data)
        *(.data.*)
    }

    .bss (NOLOAD) : {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    }

    /DISCARD/ : {
        *(.comment)
        *(.note.*)
    }
}
