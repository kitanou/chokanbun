/* 漢像のリンカスクリプト。仮想アドレス 0x40610000 に置く (民の窓のコード領域)。 */
ENTRY(_start)

SECTIONS
{
    . = 0x40610000;
    __image_base = .;

    /* 漢像ヘッダ (KBN1、40 バイト。docs/design-process-exec.md §5.1)。
     * +0 魔 "KBN1" / +4 入口 (u32) / +8 像の終端 / +16 bss 始 / +24 bss 終 / +32 副タスクの終了スタブ */
    .header : {
        BYTE(0x4B) BYTE(0x42) BYTE(0x4E) BYTE(0x31)
        LONG(_start)
        QUAD(__image_end)
        QUAD(__bss_start)
        QUAD(__bss_end)
        QUAD(__task_exit_stub)
    }

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
