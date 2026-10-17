#!/bin/sh
# kernel/kernel.mkn の「註 @取込 相対パス」行を、そのファイルの内容で置き換えて 1 つの
# ソースに展開する（コンパイラは取込を知らない。言語は変えない）。
#
# 使い方: tools/kernel-expand.sh <入力> <出力>
#   出力 に展開後のソース、出力 + ".map" に行の対応表を書く。
#   対応表の各行: <展開後の開始行> <展開後の終了行> <元ファイル> <元の開始行>
# 展開後の行番号で出た診断は tools/kernel-line.sh で元のファイル:行に戻せる。
set -eu
in="$1"
out="$2"
dir="$(dirname "$in")"
: >"$out.map"
awk -v dir="$dir" -v mapf="$out.map" -v root="$in" '
function seg_end() {
    if (cf != "") printf "%d %d %s %d\n", gs, gline, cf, ss >> mapf
}
function put(text, f, ln) {
    if (f != cf || ln != cl + 1) { seg_end(); cf = f; gs = gline + 1; ss = ln }
    gline++; cl = ln
    print text
}
function include(path, label,    ln, line, sub_path) {
    ln = 0
    while ((getline line < path) > 0) {
        ln++
        if (line ~ /^註 @取込 /) {
            sub_path = line
            sub(/^註 @取込 /, "", sub_path)
            include(dir "/" sub_path, dir "/" sub_path)
        } else {
            put(line, label, ln)
        }
    }
    close(path)
}
BEGIN { gline = 0; cf = ""; cl = 0; gs = 0; ss = 0; include(root, root); seg_end() }
' >"$out"
