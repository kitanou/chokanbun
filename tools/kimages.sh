#!/bin/sh
# 漢像の目録を作る (kld の最後の引数)。使い方: tools/kimages.sh 出力.txt 名前=漢像ファイル ...
# 1 行 1 像: 名前<TAB>TC[20] の 80 桁 16 進<TAB>ファイル。TC は tools/gen-images.sh と同じ
# (日本語は JIS X 0208 の 2 バイト符号 = EUC-JP から 0x80 を引いたもの、ASCII は上位バイト 0 の 2 バイト)。
set -eu
out="$1"; shift
: >"$out"
for kv in "$@"; do
    name="${kv%%=*}"; file="${kv#*=}"
    tc="$(python3 -I -c '
import sys
cs = []
for ch in sys.argv[1][:20]:
    if ord(ch) < 0x80:
        cs.append(ord(ch))
    else:
        b = ch.encode("euc_jp")
        cs.append(((b[0] - 0x80) << 8) | (b[1] - 0x80))
cs += [0] * (20 - len(cs))
sys.stdout.write("".join("%02x%02x" % (c & 255, c >> 8) for c in cs))
' "$name")"
    printf '%s\t%s\t%s\n' "$name" "$tc" "$file" >>"$out"
done
