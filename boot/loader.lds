/* 独立ブートローダーのリンカスクリプト (QEMU virt / AArch64)。
 * 核 (0x40000000〜) と DTB (物理 0 番地) を壊さない RAM の高位 (0x46000000) に置く。
 * 128 MiB の RAM (〜0x48000000) の内側。docs/boot-spec.md §7。 */
ENTRY(_start)

SECTIONS
{
    . = 0x46000000;

    .text : {
        *(.text.boot)
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

    /* 核棧 (導の棧): 0x46180000 を頂点にして下へ伸びる */
    _stack_top = 0x46180000;

    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.bss)
        *(.bss.*)
    }
}
