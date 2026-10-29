#!/bin/sh
# 漢像の目録を作る (kld の最後の引数)。使い方: tools/kimages.sh 出力.txt 名前=漢像ファイル ...
# 1 行 1 像: 名前<TAB>-<TAB>ファイル。TC[20] (BTRON3 のファイル名) は機械漢文のリンカ (selfhost/linker.mkn) が名前から作る。
set -eu
out="$1"; shift
: >"$out"
for kv in "$@"; do
    name="${kv%%=*}"; file="${kv#*=}"
    printf '%s\t-\t%s\n' "$name" "$file" >>"$out"
done
