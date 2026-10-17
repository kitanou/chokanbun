// 漢像 (KBN1) の先頭ヘッダと実行開始ルーチン。
//
// 漢像 = 32 バイトのヘッダ + コード + rodata + data。仮想アドレス 0x40610000 から配置される。
// ヘッダはアセンブラが記号どうしの差を計算できないため、リンカが決める**絶対アドレス**を持つ。
// 長さはローダー (kernel の 像検査) が引き算で求める。
//   +0  魔: ASCII "KBN1"
//   +4  入口の仮想アドレス (u32。_start)
//   +8  漢像の終端の仮想アドレス (u64。__image_end。長さ = これ - 0x40610000)
//   +16 bss の開始の仮想アドレス (u64。__bss_start)
//   +24 bss の終端の仮想アドレス (u64。__bss_end)
// 詳細は docs/design-process-exec.md §5.1。

    .section .header, "a"
    .globl __image_header
__image_header:
    .ascii "KBN1"
    .word  _start
    .quad  __image_end
    .quad  __bss_start
    .quad  __bss_end

    .section .text.start, "ax"
    .globl _start
// 入口。x0 = 引数文字列のアドレス, x1 = その長さ (漢令 生行程 が与える)。
// 民務 (user_main) の戻り値 x0 を終了コードに 終行程 (番2) を発行する。
_start:
    bl user_main
    mov x8, #2
    svc #0
1:  b 1b

// svc_call(nr, a0..a5): 漢令 ABI v0.1 の `svc #0` (kernel/el0.S と同じ)。
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
