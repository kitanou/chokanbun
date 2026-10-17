/* 漢像のリンカスクリプト。仮想アドレス 0x40610000 に置く (民の窓のコード領域)。 */
ENTRY(_start)

SECTIONS
{
    . = 0x40610000;
    __image_base = .;

    .header : { KEEP(*(.header)) }

    .text : {
        *(.text.start)
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
    . = ALIGN(8);
    __image_end = .;

    .bss (NOLOAD) : ALIGN(16) {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        __bss_end = .;
    }

    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.eh_frame)
    }
}
