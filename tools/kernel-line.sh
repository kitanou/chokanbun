#!/bin/sh
# 展開後のソースの行番号を、元のファイル:行に戻す。
# 使い方: tools/kernel-line.sh <展開後ソース>.map <行番号>
set -eu
awk -v n="$2" '$1 <= n && n <= $2 { printf "%s:%d\n", $3, $4 + (n - $1); found = 1; exit } END { exit found ? 0 : 1 }' "$1"
