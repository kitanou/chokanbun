#!/bin/sh
# 機械漢文の命令 (user/*.mkn) を漢像 (KBN1、仮想 0x40610000 基底の平坦バイナリ) にする。
# 使い方: tools/mkimage.sh <ソース.mkn> <出力.zo> [中間ファイルの置き場]
#   必要: chokanbun (BIN)、LLVM の llc / clang / llvm-objcopy、lld の ld.lld
set -eu
src="$1"
out="$2"
work="${3:-$(dirname "$out")}"
name="$(basename "$src" .mkn)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${BIN:-$ROOT/chokanbun}"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
LLD_BIN="${LLD_BIN:-/opt/homebrew/opt/lld/bin}"

mkdir -p "$work"
sh "$ROOT/tools/kernel-expand.sh" "$src" "$work/user_$name.all.mkn"
"$BIN" "$work/user_$name.all.mkn" -ir -o "$work/user_$name.ll" 2>"$work/user_$name.gen.log"
"$LLVM_BIN/llc" -march=aarch64 -filetype=obj "$work/user_$name.ll" -o "$work/user_$name.o"
"$LLD_BIN/ld.lld" -T "$ROOT/user/user.lds" "$work/user_$name.o" -o "$work/user_$name.elf"
"$LLVM_BIN/llvm-objcopy" -O binary "$work/user_$name.elf" "$out"
