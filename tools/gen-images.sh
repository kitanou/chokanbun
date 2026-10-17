#!/bin/sh
# 漢像 (.zo) をカーネルイメージへ埋め込むアセンブリを生成する。
# 使い方: tools/gen-images.sh <出力.S> 名前=漢像ファイル [名前=漢像ファイル ...]
#   生成物は .rodata.images (EL0 から読める 0x40000000 ブロック内) に像表と各漢像を置く。
#   像表の 1 項 (32 B): +0 名前のアドレス, +8 名前の長さ, +16 漢像のアドレス, +24 漢像の長さ
set -eu
out="$1"; shift
n=$#
{
    echo '// tools/gen-images.sh が生成。編集しない。'
    echo '    .section .rodata.images, "a"'
    echo '    .balign 8'
    echo 'image_table:'
    i=0
    for kv in "$@"; do
        name="${kv%%=*}"; file="${kv#*=}"
        len="$(wc -c <"$file" | tr -d ' ')"
        nlen="$(printf '%s' "$name" | wc -c | tr -d ' ')"
        echo "    .quad image_name_$i, $nlen, image_data_$i, $len"
        i=$((i + 1))
    done
    i=0
    for kv in "$@"; do
        name="${kv%%=*}"; file="${kv#*=}"
        abs="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
        echo "image_name_$i:"
        echo "    .ascii \"$name\""
        echo '    .balign 8'
        echo "image_data_$i:"
        echo "    .incbin \"$abs\""
        echo '    .balign 8'
        i=$((i + 1))
    done
    echo '    .text'
    echo '    .globl image_table_addr'
    echo 'image_table_addr:'
    echo '    adrp x0, image_table'
    echo '    add x0, x0, :lo12:image_table'
    echo '    ret'
    echo '    .globl image_count_fn'
    echo 'image_count_fn:'
    echo "    mov x0, #$n"
    echo '    ret'
} >"$out"
