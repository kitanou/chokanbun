#!/usr/bin/env bash
#
# ChoKanbun OS - reproducible test runner.
#
# Builds machine-kanbun sources, lowers them to AArch64 objects/ELF, and
# verifies the results.  Set LLVM_BIN / LLD_BIN / BIN to override tool paths.
#
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN="${BIN:-$ROOT/chokanbun}"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
LLD_BIN="${LLD_BIN:-/opt/homebrew/opt/lld/bin}"

LLC="$LLVM_BIN/llc"
CLANG="$LLVM_BIN/clang"
OBJDUMP="$LLVM_BIN/llvm-objdump"
READELF="$LLVM_BIN/llvm-readelf"
LD="$LLD_BIN/ld.lld"

OUT="$ROOT/tests/output"
mkdir -p "$OUT"

RC=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; RC=1; }

run() {
    # run <label> <command...>
    local label="$1"; shift
    if "$@" >"$OUT/${label}.log" 2>&1; then
        pass "$label"
    else
        fail "$label"
        echo "      see $OUT/${label}.log"
        sed 's/^/      /' "$OUT/${label}.log" | head -20
    fi
}

echo "=== ChoKanbun compiler tests ==="

# --- 機械漢文のツールチェーン (バックエンド selfhost/backend.mkn + リンカ selfhost/linker.mkn) ------------------------
#     IR → AArch64 → ELF/漢像。llc・ld.lld・llvm-objcopy に当たる。TOOLCHAIN=kanbun で、核・漢像・導の組み立てに LLVM を使わない。
#     kld 自身は C++ 版のコンパイラとホストの clang で作る (入出力だけの selfhost/host_ld.c を付ける)。
TOOLCHAIN="${TOOLCHAIN:-llvm}"
KLD="$OUT/kld"
export TOOLCHAIN KLD
if sh tools/kernel-expand.sh selfhost/toolchain.mkn "$OUT/toolchain_all.mkn" >/dev/null \
   && "$BIN" "$OUT/toolchain_all.mkn" -ir -o "$OUT/toolchain.ll" 2>"$OUT/toolchain.gen.log" \
   && "$CLANG" -Wno-override-module -x ir "$OUT/toolchain.ll" -x c selfhost/host_ld.c -o "$KLD" >"$OUT/toolchain.cc.log" 2>&1; then
    pass "toolchain: 機械漢文のバックエンドとリンカ (kld) をビルド (TOOLCHAIN=$TOOLCHAIN)"
else
    fail "toolchain: 機械漢文のバックエンドとリンカ (kld) をビルド"
    sed 's/^/      /' "$OUT/toolchain.gen.log" "$OUT/toolchain.cc.log" 2>/dev/null | head -10
fi

# --- hello: minimum function, IR -> AArch64 object ------------------------
"$BIN" tests/hello.mkn -ir -o "$OUT/hello.ll" 2>"$OUT/hello.gen.log" \
    && pass "hello: IR generation" || fail "hello: IR generation"
"$LLC" -march=aarch64 -filetype=obj "$OUT/hello.ll" -o "$OUT/hello.o" \
    >"$OUT/hello.llc.log" 2>&1 \
    && pass "hello: AArch64 object" || fail "hello: AArch64 object"
"$OBJDUMP" -d "$OUT/hello.o" >"$OUT/hello.dis" 2>&1 \
    && pass "hello: disassembly" || fail "hello: disassembly"

# --- uart: 核外輸出 call + 取址/長度 builtins -> ELF ----------------------
"$BIN" tests/uart.mkn -ir -o "$OUT/uart.ll" 2>"$OUT/uart.gen.log" \
    && pass "uart: IR generation" || fail "uart: IR generation"
"$LLC" -march=aarch64 -filetype=obj "$OUT/uart.ll" -o "$OUT/uart.o" \
    >"$OUT/uart.llc.log" 2>&1 \
    && pass "uart: AArch64 object" || fail "uart: AArch64 object"
"$CLANG" --target=aarch64-none-elf -ffreestanding -c boot/uart.c \
    -o "$OUT/uart_c.o" >"$OUT/uart_c.log" 2>&1 \
    && pass "uart: bootstrap UART object" || fail "uart: bootstrap UART object"
"$BIN" boot/boot.mkn -ir -o "$OUT/boot.ll" 2>"$OUT/boot.gen.log" \
    && "$LLC" -march=aarch64 -filetype=obj "$OUT/boot.ll" -o "$OUT/boot.o" \
        >"$OUT/boot.log" 2>&1 \
    && pass "uart: boot stub object" || fail "uart: boot stub object"

if [ -f "$OUT/uart.o" ] && [ -f "$OUT/uart_c.o" ] && [ -f "$OUT/boot.o" ]; then
    "$LD" -T boot/boot.lds "$OUT/boot.o" "$OUT/uart_c.o" "$OUT/uart.o" \
        -o "$OUT/uart.elf" >"$OUT/uart.link.log" 2>&1 \
        && pass "uart: ELF link" || fail "uart: ELF link"
    if [ -f "$OUT/uart.elf" ]; then
        "$READELF" -h "$OUT/uart.elf" >"$OUT/uart.readelf.log" 2>&1 \
            && pass "uart: ELF header" || fail "uart: ELF header"
        "$OBJDUMP" -d "$OUT/uart.elf" >"$OUT/uart.dis" 2>&1 \
            && pass "uart: disassembly" || fail "uart: disassembly"
    fi
fi

# --- uart_mmio: 機械漢文のみの PL011 ドライバ (volatile MMIO + 項) -> ELF ---
"$BIN" tests/uart_mmio.mkn -ir -o "$OUT/uart_mmio.ll" 2>"$OUT/uart_mmio.gen.log" \
    && pass "uart_mmio: IR generation" || fail "uart_mmio: IR generation"
"$LLC" -march=aarch64 -filetype=obj "$OUT/uart_mmio.ll" -o "$OUT/uart_mmio.o" \
    >"$OUT/uart_mmio.llc.log" 2>&1 \
    && pass "uart_mmio: AArch64 object" || fail "uart_mmio: AArch64 object"
if [ -f "$OUT/uart_mmio.o" ] && [ -f "$OUT/boot.o" ]; then
    "$LD" -T boot/boot.lds "$OUT/boot.o" "$OUT/uart_mmio.o" \
        -o "$OUT/uart_mmio.elf" >"$OUT/uart_mmio.link.log" 2>&1 \
        && pass "uart_mmio: ELF link" || fail "uart_mmio: ELF link"
    if [ -f "$OUT/uart_mmio.elf" ]; then
        "$OBJDUMP" -d "$OUT/uart_mmio.elf" >"$OUT/uart_mmio.dis" 2>&1 \
            && pass "uart_mmio: disassembly" || fail "uart_mmio: disassembly"
    fi
fi

# --- kernel: 漢極 (exception vectors + MMU + memory) -> ELF -> QEMU ---------
# kernel/kernel.mkn の「註 @取込」(kernel/vfs/*.mkn) を展開してからコンパイルする。
sh tools/kernel-expand.sh kernel/kernel.mkn "$OUT/kernel_all.mkn" \
    && pass "kernel: 取込の展開 (kernel/vfs/)" || fail "kernel: 取込の展開 (kernel/vfs/)"
# 展開後の行番号を元のファイル:行へ戻せること (診断の位置合わせ)
KLINE="$(grep -n '術曰「籍削」' "$OUT/kernel_all.mkn" | head -1 | cut -d: -f1)"
if [ -n "$KLINE" ] && [ "$(sh tools/kernel-line.sh "$OUT/kernel_all.mkn.map" "$KLINE")" = \
     "kernel/vfs/pian.mkn:$(grep -n '術曰「籍削」' kernel/vfs/pian.mkn | head -1 | cut -d: -f1)" ]; then
    pass "kernel: 展開後の行番号を元のファイル:行へ戻せる (籍削 → kernel/vfs/pian.mkn)"
else
    fail "kernel: 展開後の行番号を元のファイル:行へ戻せる"
fi
# 前回の成果物が残っていると、生成に失敗しても古い ELF で QEMU 試験が走ってしまう。
rm -f "$OUT/kernel.ll" "$OUT/kernel.o" "$OUT/kernel.elf"
"$BIN" "$OUT/kernel_all.mkn" -ir -o "$OUT/kernel.ll" 2>"$OUT/kernel.gen.log" \
    && pass "kernel: IR generation" || fail "kernel: IR generation"
if [ -s "$OUT/kernel.gen.log" ] && grep -q '錯' "$OUT/kernel.gen.log"; then
    echo "      (診断の行は展開後のもの。元の位置は: sh tools/kernel-line.sh $OUT/kernel_all.mkn.map <行>)"
    sed 's/^/      /' "$OUT/kernel.gen.log" | head -10
fi
# Regression: locals declared in loops must not alloca outside the entry block
# (otherwise a long-running loop exhausts the stack).
awk '/^define /{e=1} /^[A-Za-z0-9_.]+:$/{ if ($0!="entry:") e=0 } /alloca/{ if(!e) bad=1 } END{exit bad}' "$OUT/kernel.ll" \
    && pass "kernel: allocas hoisted to entry block" || fail "kernel: allocas hoisted to entry block"
if [ "$TOOLCHAIN" != kanbun ]; then
"$LLC" -march=aarch64 -filetype=obj "$OUT/kernel.ll" -o "$OUT/kernel.o" \
    >"$OUT/kernel.llc.log" 2>&1 \
    && pass "kernel: AArch64 object" || fail "kernel: AArch64 object"
fi

# 外部命令 (漢像 KBN1) をビルドし、カーネルイメージへ埋め込む (行程の設計 P1)。
export BIN LLVM_BIN LLD_BIN
sh tools/mkimage.sh user/hello.mkn "$OUT/hello.zo" "$OUT" 2>"$OUT/user_hello.build.log" \
    && pass "user: 外部命令 問安 を漢像にビルド" || {
        fail "user: 外部命令 問安 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_hello.build.log" | head -10
    }
sh tools/mkimage.sh user/fault.mkn "$OUT/fault.zo" "$OUT" 2>"$OUT/user_fault.build.log" \
    && pass "user: 異常試 (保護違反・BRK で異常終了する外部命令) を漢像にビルド" || {
        fail "user: 異常試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_fault.build.log" | head -10
    }
sh tools/mkimage.sh user/count.mkn "$OUT/count.zo" "$OUT" 2>"$OUT/user_count.build.log" \
    && pass "user: 外部命令 數 を漢像にビルド" || {
        fail "user: 外部命令 數 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_count.build.log" | head -10
    }
# 漢像のヘッダ: 魔 KBN1、入口が 0x40610000 台、終端が像の範囲
if [ -f "$OUT/hello.zo" ] && [ "$(head -c 4 "$OUT/hello.zo")" = "KBN1" ]; then
    pass "user: 漢像のヘッダ (魔 KBN1、$(wc -c <"$OUT/hello.zo" | tr -d ' ') バイト)"
else
    fail "user: 漢像のヘッダ"
fi
sh tools/mkimage.sh user/btron_gtid.mkn "$OUT/btron_gtid.zo" "$OUT" 2>"$OUT/user_btron_gtid.build.log" \
    && pass "user: BTRON3 互換層の試験 識試 (get_tid・ER_*) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 識試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_gtid.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_gname.mkn "$OUT/btron_gname.zo" "$OUT" 2>"$OUT/user_btron_gname.build.log" \
    && pass "user: BTRON3 互換層の試験 名試 (グローバル名) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 名試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_gname.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_clk.mkn "$OUT/btron_clk.zo" "$OUT" 2>"$OUT/user_btron_clk.build.log" \
    && pass "user: BTRON3 互換層の試験 時試 (get_tim・get_tod) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 時試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_clk.build.log" | head -10
    }
sh tools/mkimage.sh user/time_test.mkn "$OUT/time_test.zo" "$OUT" 2>"$OUT/user_time_test.build.log" \
    && pass "user: 黄帝紀元の変換・書式化・壁時計の試験 時元試 を漢像にビルド" || {
        fail "user: 黄帝紀元の変換・書式化・壁時計の試験 時元試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_time_test.build.log" | head -10
    }
sh tools/mkimage.sh user/time_cmd.mkn "$OUT/time_cmd.zo" "$OUT" 2>"$OUT/user_time_cmd.build.log" \
    && pass "user: 漢殻命令 時 (現在日時・篇時刻) を漢像にビルド" || {
        fail "user: 漢殻命令 時 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_time_cmd.build.log" | head -10
    }
sh tools/mkimage.sh user/tag_cmd.mkn "$OUT/tag_cmd.zo" "$OUT" 2>"$OUT/user_tag_cmd.build.log" \
    && pass "user: 漢殻命令 標・索 (篇の標と検索) を漢像にビルド" || {
        fail "user: 漢殻命令 標・索 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_tag_cmd.build.log" | head -10
    }
sh tools/mkimage.sh user/stress.mkn "$OUT/stress.zo" "$OUT" 2>"$OUT/user_stress.build.log" \
    && pass "user: 競合のストレス試験 競試 を漢像にビルド" || {
        fail "user: 競合のストレス試験 競試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_stress.build.log" "$OUT/user_stress.gen.log" 2>/dev/null | head -10
    }
sh tools/mkimage.sh user/lex_cmd.mkn "$OUT/lex_cmd.zo" "$OUT" 2>"$OUT/user_lex_cmd.build.log" \
    && pass "user: セルフホストの字句解析器の命令 字句 を漢像にビルド" || {
        fail "user: セルフホストの字句解析器の命令 字句 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_lex_cmd.build.log" "$OUT/user_lex_cmd.gen.log" 2>/dev/null | head -10
    }
sh tools/mkimage.sh user/ast_cmd.mkn "$OUT/ast_cmd.zo" "$OUT" 2>"$OUT/user_ast_cmd.build.log" \
    && pass "user: セルフホストの構文解析器の命令 構文 を漢像にビルド" || {
        fail "user: セルフホストの構文解析器の命令 構文 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_ast_cmd.build.log" "$OUT/user_ast_cmd.gen.log" 2>/dev/null | head -10
    }
sh tools/mkimage.sh user/tc_cmd.mkn "$OUT/tc_cmd.zo" "$OUT" 2>"$OUT/user_tc_cmd.build.log" \
    && pass "user: セルフホストの型検査器の命令 型検 を漢像にビルド" || {
        fail "user: セルフホストの型検査器の命令 型検 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_tc_cmd.build.log" "$OUT/user_tc_cmd.gen.log" 2>/dev/null | head -10
    }
sh tools/mkimage.sh user/cc_cmd.mkn "$OUT/cc_cmd.zo" "$OUT" 2>"$OUT/user_cc_cmd.build.log" \
    && pass "user: セルフホストのコンパイラの命令 機譯 を漢像にビルド" || {
        fail "user: セルフホストのコンパイラの命令 機譯 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_cc_cmd.build.log" "$OUT/user_cc_cmd.gen.log" 2>/dev/null | head -10
    }
sh tools/mkimage.sh user/src_gen.mkn "$OUT/src_gen.zo" "$OUT" 2>"$OUT/user_src_gen.build.log" \
    && pass "user: 大きなソースを篇に作る試験用の命令 源増 を漢像にビルド" || {
        fail "user: 源増 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_src_gen.build.log" "$OUT/user_src_gen.gen.log" 2>/dev/null | head -10
    }
sh tools/mkimage.sh user/src_in.mkn "$OUT/src_in.zo" "$OUT" 2>"$OUT/user_src_in.build.log" \
    && pass "user: コンソールから生のバイトを篇へ受ける試験用の命令 源受 を漢像にビルド" || {
        fail "user: 源受 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_src_in.build.log" "$OUT/user_src_in.gen.log" 2>/dev/null | head -10
    }
sh tools/mkimage.sh user/btron_msg.mkn "$OUT/btron_msg.zo" "$OUT" 2>"$OUT/user_btron_msg.build.log" \
    && pass "user: BTRON3 互換層の試験 信試 (メッセージ) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 信試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_msg.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_usr.mkn "$OUT/btron_usr.zo" "$OUT" 2>"$OUT/user_btron_usr.build.log" \
    && pass "user: BTRON3 互換層の試験 利試 (利用者情報・時刻の権限) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 利試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_usr.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_term.mkn "$OUT/btron_term.zo" "$OUT" 2>"$OUT/user_btron_term.build.log" \
    && pass "user: BTRON3 互換層の試験 強試 (ter_prc・prc_sts) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 強試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_term.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_sync.mkn "$OUT/btron_sync.zo" "$OUT" 2>"$OUT/user_btron_sync.build.log" \
    && pass "user: BTRON3 互換層の試験 同試 (セマフォ・イベントフラグ) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 同試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_sync.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_comm.mkn "$OUT/btron_comm.zo" "$OUT" 2>"$OUT/user_btron_comm.build.log" \
    && pass "user: BTRON3 互換層の試験 緩試 (メッセージバッファ・ランデブ) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 緩試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_comm.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_file.mkn "$OUT/btron_file.zo" "$OUT" 2>"$OUT/user_btron_file.build.log" \
    && pass "user: BTRON3 互換層の試験 録試 (ファイル管理 B1: 接続・パス解決) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 録試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_file.build.log" | head -10
    }
sh tools/mkimage.sh user/pian_test.mkn "$OUT/pian_test.zo" "$OUT" 2>"$OUT/user_pian_test.build.log" \
    && pass "user: 篇藏の試験 篇試 (F1〜F3) を漢像にビルド" || {
        fail "user: 篇藏の試験 篇試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_pian_test.build.log" | head -10
    }
sh tools/mkimage.sh user/pian_persist.mkn "$OUT/pian_persist.zo" "$OUT" 2>"$OUT/user_pian_persist.build.log" \
    && pass "user: 篇藏の永続化の試験 永試 を漢像にビルド" || {
        fail "user: 篇藏の永続化の試験 永試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_pian_persist.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_mem.mkn "$OUT/btron_mem.zo" "$OUT" 2>"$OUT/user_btron_mem.build.log" \
    && pass "user: BTRON3 互換層の試験 貯試 (1.5 メモリ管理 get_mbk/rel_mbk/mbk_sts) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 貯試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_mem.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_evt.mkn "$OUT/btron_evt.zo" "$OUT" 2>"$OUT/user_btron_evt.build.log" \
    && pass "user: BTRON3 互換層の試験 件試 (1.7 イベント管理) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 件試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_evt.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_dev.mkn "$OUT/btron_dev.zo" "$OUT" 2>"$OUT/user_btron_dev.build.log" \
    && pass "user: BTRON3 互換層の試験 設試 (1.8 デバイス管理) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 設試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_dev.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_omgr.mkn "$OUT/btron_omgr.zo" "$OUT" 2>"$OUT/user_btron_omgr.build.log" \
    && pass "user: BTRON3 互換層の試験 実試 (3.8 実身／仮身マネージャの登録簿・起動) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 実試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_omgr.build.log" | head -10
    }
sh tools/mkimage.sh user/obj_app.mkn "$OUT/obj_app.zo" "$OUT" 2>"$OUT/user_obj_app.build.log" \
    && pass "user: 起動プロトコルの試験用アプリ objapp を漢像にビルド" || {
        fail "user: 起動プロトコルの試験用アプリ objapp を漢像にビルド"
        sed 's/^/      /' "$OUT/user_obj_app.build.log" | head -10
    }
sh tools/mkimage.sh user/obj.mkn "$OUT/obj.zo" "$OUT" 2>"$OUT/user_obj.build.log" \
    && pass "user: 実身・仮身の漢殻の命令 (実作・仮置・実削・実目・実名) を漢像にビルド" || {
        fail "user: 実身・仮身の漢殻の命令を漢像にビルド"
        sed 's/^/      /' "$OUT/user_obj.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_sys.mkn "$OUT/btron_sys.zo" "$OUT" 2>"$OUT/user_btron_sys.build.log" \
    && pass "user: BTRON3 互換層の試験 系試 (1.10 システム管理) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 系試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_sys.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_exc.mkn "$OUT/btron_exc.zo" "$OUT" 2>"$OUT/user_btron_exc.build.log" \
    && pass "user: BTRON3 互換層の試験 例試 (1.10 def_exc・ret_exc) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 例試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_exc.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_msg_hdr.mkn "$OUT/btron_msg_hdr.zo" "$OUT" 2>"$OUT/user_btron_msg_hdr.build.log" \
    && pass "user: BTRON3 互換層の試験 信手試 (1.2 def_msg・ret_msg) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 信手試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_msg_hdr.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_task.mkn "$OUT/btron_task.zo" "$OUT" 2>"$OUT/user_btron_task.build.log" \
    && pass "user: BTRON3 互換層の試験 副試 (1.1 cre_tsk・ext_tsk・ter_tsk) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 副試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_task.build.log" | head -10
    }
KIMG_ARGS=(問安="$OUT/hello.zo" 數="$OUT/count.zo" 異常試="$OUT/fault.zo" 識試="$OUT/btron_gtid.zo" 名試="$OUT/btron_gname.zo" 時試="$OUT/btron_clk.zo" 時元試="$OUT/time_test.zo" 時="$OUT/time_cmd.zo" 信試="$OUT/btron_msg.zo" 利試="$OUT/btron_usr.zo" 強試="$OUT/btron_term.zo" 同試="$OUT/btron_sync.zo" 緩試="$OUT/btron_comm.zo" 録試="$OUT/btron_file.zo" 篇試="$OUT/pian_test.zo" 永試="$OUT/pian_persist.zo" 貯試="$OUT/btron_mem.zo" 件試="$OUT/btron_evt.zo" 設試="$OUT/btron_dev.zo" 系試="$OUT/btron_sys.zo" 例試="$OUT/btron_exc.zo" 信手試="$OUT/btron_msg_hdr.zo" 副試="$OUT/btron_task.zo" 実試="$OUT/btron_omgr.zo" 実作="$OUT/obj.zo" 仮置="$OUT/obj.zo" 実削="$OUT/obj.zo" 実目="$OUT/obj.zo" 実名="$OUT/obj.zo" objapp="$OUT/obj_app.zo" 標="$OUT/tag_cmd.zo" 索="$OUT/tag_cmd.zo" 競試="$OUT/stress.zo" 字句="$OUT/lex_cmd.zo" 構文="$OUT/ast_cmd.zo" 型検="$OUT/tc_cmd.zo" 機譯="$OUT/cc_cmd.zo" 源増="$OUT/src_gen.zo" 源受="$OUT/src_in.zo")
if [ "$TOOLCHAIN" = kanbun ]; then
    # 機械漢文のツールチェーン: 像表と漢像を核の rodata へ埋め込み、核の ELF を作る (gen-images.sh・clang・ld.lld の代わり)
    rm -f "$OUT/kernel.elf"
    sh tools/kimages.sh "$OUT/images.txt" "${KIMG_ARGS[@]}" \
        && pass "kernel: 漢像の目録 (像表)" || fail "kernel: 漢像の目録 (像表)"
    "$KLD" 1 40000000 "$OUT/kernel.ll" "$OUT/kernel.elf" "$OUT/images.txt" 2>"$OUT/kernel.link.log" \
        && pass "kernel: 機械漢文のバックエンドとリンカで核の ELF を作る (kld)" || {
            fail "kernel: 機械漢文のバックエンドとリンカで核の ELF を作る (kld)"
            sed 's/^/      /' "$OUT/kernel.link.log" | head -5
        }
    VADDR="$(awk '$2 == "_vectors" {print $1}' "$OUT/kernel.elf.map" 2>/dev/null)"
    if [ -n "$VADDR" ] && [ $(( 16#$VADDR % 2048 )) -eq 0 ]; then
        pass "kernel: vector table 2KiB aligned ($VADDR)"
    else
        fail "kernel: vector table 2KiB aligned (got '${VADDR:-none}')"
    fi
else
sh tools/gen-images.sh "$OUT/kernel_images.S" "${KIMG_ARGS[@]}" \
    && "$CLANG" --target=aarch64-none-elf -c "$OUT/kernel_images.S" -o "$OUT/kernel_images.o" \
        >"$OUT/kernel_images.log" 2>&1 \
    && pass "kernel: 漢像の埋め込み (像表)" || fail "kernel: 漢像の埋め込み (像表)"

if [ -f "$OUT/kernel.o" ] && \
   [ -f "$OUT/kernel_images.o" ]; then
    "$LD" -T kernel/kernel.lds \
        "$OUT/kernel_images.o" "$OUT/kernel.o" -o "$OUT/kernel.elf" \
        >"$OUT/kernel.link.log" 2>&1 \
        && pass "kernel: ELF link" || fail "kernel: ELF link"
    if [ -f "$OUT/kernel.elf" ]; then
        "$OBJDUMP" -d "$OUT/kernel.elf" >"$OUT/kernel.dis" 2>&1 \
            && pass "kernel: disassembly" || fail "kernel: disassembly"
        # _vectors must be 2 KiB aligned (AArch64 requirement).
        VADDR="$("$LLVM_BIN/llvm-nm" "$OUT/kernel.elf" 2>/dev/null | awk '/ _vectors$/{print $1}')"
        if [ -n "$VADDR" ] && [ $(( 16#$VADDR % 2048 )) -eq 0 ]; then
            pass "kernel: vector table 2KiB aligned ($VADDR)"
        else
            fail "kernel: vector table 2KiB aligned (got '${VADDR:-none}')"
        fi
    fi
fi
fi

# --- 独立ブートローダー「導」(boot/loader.mkn)。核のイメージ KBL1 を virtio-blk から読んで核へ移譲する -----------------
sh tools/kernel-expand.sh boot/loader.mkn "$OUT/loader_all.mkn" \
    && "$BIN" "$OUT/loader_all.mkn" -ir -o "$OUT/loader.ll" 2>"$OUT/loader.gen.log" \
    && if [ "$TOOLCHAIN" = kanbun ]; then "$KLD" 3 46000000 "$OUT/loader.ll" "$OUT/loader.elf" >"$OUT/loader.link.log" 2>&1; \
       else "$LLC" -march=aarch64 -filetype=obj "$OUT/loader.ll" -o "$OUT/loader.o" >"$OUT/loader.llc.log" 2>&1 \
         && "$LD" -T boot/loader.lds "$OUT/loader.o" -o "$OUT/loader.elf" >"$OUT/loader.link.log" 2>&1; fi \
    && pass "boot: 独立ブートローダー 導 をビルド (boot/loader.mkn → 0x46000000)" || {
        fail "boot: 独立ブートローダー 導 をビルド"
        sed 's/^/      /' "$OUT/loader.gen.log" | head -10
    }
if [ "$TOOLCHAIN" = kanbun ]; then
    # 機械漢文のリンカが KBL1 を直接作る (tools/mkkernelimg.py の代わり)
    "$KLD" 4 40000000 "$OUT/kernel.ll" "$OUT/kernel.img" "$OUT/images.txt" >"$OUT/kernel.img.log" 2>&1 \
        && [ -s "$OUT/kernel.img" ] && echo "KBL1: $(wc -c <"$OUT/kernel.img" | tr -d ' ') バイト" >"$OUT/kernel.img.log"
    KIMG_OK=$?
elif [ -f "$OUT/kernel.elf" ] && python3 tools/mkkernelimg.py "$OUT/kernel.elf" "$OUT/kernel.img" >"$OUT/kernel.img.log" 2>&1; then
    KIMG_OK=0
else
    KIMG_OK=1
fi
if [ "$KIMG_OK" = 0 ]; then
    pass "boot: 核のイメージ KBL1 を作る ($(cat "$OUT/kernel.img.log"))"
else
    fail "boot: 核のイメージ KBL1 を作る"
fi

# --- セルフホスト第 1 段: 機械漢文の字句解析器 (selfhost/lexer.mkn) が C++ 版 -tokens と同じ出力を出す --------------------
#     機械漢文のコンパイラで作った IR をホストの clang で実行ファイルにし (入出力だけの selfhost/host_main.c を付ける)、
#     リポジトリの全ての .mkn で比べる。字句の誤りは両方とも失敗すればよい。
if "$BIN" selfhost/lexer.mkn -ir -o "$OUT/selfhost_lexer.ll" 2>"$OUT/selfhost_lexer.gen.log" \
   && "$CLANG" -Wno-override-module -x ir "$OUT/selfhost_lexer.ll" -x c selfhost/host_main.c -o "$OUT/selfhost_lexer_host" \
        >"$OUT/selfhost_lexer.cc.log" 2>&1; then
    SH_OK=0; SH_BAD=0; SH_BADLIST=""
    for f in $(find tests boot kernel user selfhost -name '*.mkn' | sort); do
        "$BIN" "$f" -tokens >"$OUT/selfhost_ref.txt" 2>/dev/null; rc=$?
        "$OUT/selfhost_lexer_host" "$f" >"$OUT/selfhost_got.txt" 2>/dev/null; rc2=$?
        if [ $rc -eq 0 ] && [ $rc2 -eq 0 ] && cmp -s "$OUT/selfhost_ref.txt" "$OUT/selfhost_got.txt"; then SH_OK=$((SH_OK+1))
        elif [ $rc -ne 0 ] && [ $rc2 -ne 0 ]; then SH_OK=$((SH_OK+1))
        else SH_BAD=$((SH_BAD+1)); SH_BADLIST="$SH_BADLIST $f"; fi
    done
    if [ "$SH_BAD" -eq 0 ] && [ "$SH_OK" -ge 100 ]; then
        pass "selfhost: 機械漢文の字句解析器 (selfhost/lexer.mkn) が C++ 版と ${SH_OK} 個の .mkn で同じトークン列を出す"
    else
        fail "selfhost: 字句解析器の不一致 ${SH_BAD} 個 (${SH_OK} 個一致):$SH_BADLIST"
    fi
else
    fail "selfhost: 字句解析器をビルド"
    sed 's/^/      /' "$OUT/selfhost_lexer.gen.log" "$OUT/selfhost_lexer.cc.log" 2>/dev/null | head -10
fi

# --- セルフホスト第 2 段: 機械漢文の構文解析器 (selfhost/parser.mkn) が C++ 版 -ast と同じ出力を出す -----------------
#     リポジトリの全ての .mkn で比べる。字句・構文の誤りは両方とも失敗すればよい。
if sh tools/kernel-expand.sh selfhost/parser.mkn "$OUT/selfhost_parser_all.mkn" \
   && "$BIN" "$OUT/selfhost_parser_all.mkn" -ir -o "$OUT/selfhost_parser.ll" 2>"$OUT/selfhost_parser.gen.log" \
   && "$CLANG" -Wno-override-module -x ir "$OUT/selfhost_parser.ll" -x c selfhost/host_ast.c -o "$OUT/selfhost_parser_host" \
        >"$OUT/selfhost_parser.cc.log" 2>&1; then
    SP_OK=0; SP_BAD=0; SP_BADLIST=""
    for f in $(find tests boot kernel user selfhost -name '*.mkn' | sort); do
        "$BIN" "$f" -ast >"$OUT/selfhost_ref.txt" 2>/dev/null; rc=$?
        "$OUT/selfhost_parser_host" "$f" >"$OUT/selfhost_got.txt" 2>/dev/null; rc2=$?
        if [ $rc -eq 0 ] && [ $rc2 -eq 0 ] && cmp -s "$OUT/selfhost_ref.txt" "$OUT/selfhost_got.txt"; then SP_OK=$((SP_OK+1))
        elif [ $rc -ne 0 ] && [ $rc2 -ne 0 ]; then SP_OK=$((SP_OK+1))
        else SP_BAD=$((SP_BAD+1)); SP_BADLIST="$SP_BADLIST $f"; fi
    done
    if [ "$SP_BAD" -eq 0 ] && [ "$SP_OK" -ge 100 ]; then
        pass "selfhost: 機械漢文の構文解析器 (selfhost/parser.mkn) が C++ 版と ${SP_OK} 個の .mkn で同じ AST を出す (構文の誤りも両方で失敗)"
    else
        fail "selfhost: 構文解析器の不一致 ${SP_BAD} 個 (${SP_OK} 個一致):$SP_BADLIST"
    fi
else
    fail "selfhost: 構文解析器をビルド"
    sed 's/^/      /' "$OUT/selfhost_parser.gen.log" "$OUT/selfhost_parser.cc.log" 2>/dev/null | head -10
fi

# --- セルフホスト第 3 段: 機械漢文の型検査器 (selfhost/typecheck.mkn) が C++ 版 -check と同じ診断を出す --------------
#     リポジトリの全ての .mkn と、取込を展開した全てのプログラム (核・行程・ローダー・セルフホスト自身) で比べる。
#     診断の文字列・位置・順序が一致すること。字句・構文の誤りは両方とも失敗すればよい。
if sh tools/kernel-expand.sh selfhost/typecheck.mkn "$OUT/selfhost_tc_all.mkn" \
   && "$BIN" "$OUT/selfhost_tc_all.mkn" -ir -o "$OUT/selfhost_tc.ll" 2>"$OUT/selfhost_tc.gen.log" \
   && "$CLANG" -Wno-override-module -x ir "$OUT/selfhost_tc.ll" -x c selfhost/host_tc.c -o "$OUT/selfhost_tc_host" \
        >"$OUT/selfhost_tc.cc.log" 2>&1; then
    rm -rf "$OUT/selfhost_tc_exp"; mkdir -p "$OUT/selfhost_tc_exp"
    for f in $(grep -l '@取込' $(find tests boot kernel user selfhost -name '*.mkn' | sort)); do
        sh tools/kernel-expand.sh "$f" "$OUT/selfhost_tc_exp/$(echo "$f" | tr '/' '_')" >/dev/null 2>&1
    done
    ST_OK=0; ST_BAD=0; ST_DIAG=0; ST_BADLIST=""
    for f in $(find tests boot kernel user selfhost -name '*.mkn' | sort) "$OUT"/selfhost_tc_exp/*.mkn; do
        "$BIN" "$f" -ast >/dev/null 2>&1; prc=$?
        "$OUT/selfhost_tc_host" "$f" 2>"$OUT/selfhost_tc_got.txt"; rc2=$?
        if [ $prc -ne 0 ]; then
            if [ $rc2 -eq 2 ]; then ST_OK=$((ST_OK+1)); else ST_BAD=$((ST_BAD+1)); ST_BADLIST="$ST_BADLIST $f"; fi
            continue
        fi
        "$BIN" "$f" -check 2>"$OUT/selfhost_tc_ref.txt"; rc=$?
        if [ $rc -eq 1 ] && [ $rc2 -eq 1 ] && cmp -s "$OUT/selfhost_tc_ref.txt" "$OUT/selfhost_tc_got.txt"; then ST_OK=$((ST_OK+1)); ST_DIAG=$((ST_DIAG+1))
        elif [ $rc -eq 0 ] && [ $rc2 -eq 0 ]; then ST_OK=$((ST_OK+1))
        else ST_BAD=$((ST_BAD+1)); ST_BADLIST="$ST_BADLIST $f"; fi
    done
    if [ "$ST_BAD" -eq 0 ] && [ "$ST_DIAG" -ge 100 ]; then
        pass "selfhost: 機械漢文の型検査器 (selfhost/typecheck.mkn) が C++ 版と ${ST_OK} 個のプログラムで同じ診断を出す (うち診断あり ${ST_DIAG} 個。核を含む展開後の全プログラムは誤り無し)"
    else
        fail "selfhost: 型検査器の不一致 ${ST_BAD} 個 (${ST_OK} 個一致、診断あり ${ST_DIAG} 個):$ST_BADLIST"
    fi
else
    fail "selfhost: 型検査器をビルド"
    sed 's/^/      /' "$OUT/selfhost_tc.gen.log" "$OUT/selfhost_tc.cc.log" 2>/dev/null | head -10
fi

# --- セルフホスト第 4 段: 機械漢文の IR 生成器 (selfhost/irgen.mkn) が C++ 版 -ir と同じ IR を出す ------------------
#     型検査を通る全てのプログラム (核・行程・ローダー・セルフホスト自身を取込展開したもの) で、IR が 1 バイトも違わないこと。
#     型検査や IR 生成の診断で失敗するものは、診断の文字列が一致すること。字句・構文の誤りは両方とも失敗すればよい。
if sh tools/kernel-expand.sh selfhost/irgen.mkn "$OUT/selfhost_ir_all.mkn" \
   && "$BIN" "$OUT/selfhost_ir_all.mkn" -ir -o "$OUT/selfhost_ir.ll" 2>"$OUT/selfhost_ir.gen.log" \
   && "$CLANG" -Wno-override-module -x ir "$OUT/selfhost_ir.ll" -x c selfhost/host_ir.c -o "$OUT/selfhost_ir_host" \
        >"$OUT/selfhost_ir.cc.log" 2>&1; then
    SI_OK=0; SI_BAD=0; SI_IR=0; SI_BADLIST=""
    for f in $(find tests/lang tests/*.mkn boot kernel user selfhost -name '*.mkn' | sort) "$OUT"/selfhost_tc_exp/*.mkn "$OUT/selfhost_ir_all.mkn"; do
        "$BIN" "$f" -ast >/dev/null 2>&1; prc=$?
        "$OUT/selfhost_ir_host" "$f" >"$OUT/selfhost_ir_got.txt" 2>"$OUT/selfhost_ir_goterr.txt"; rc2=$?
        if [ $prc -ne 0 ]; then
            if [ $rc2 -eq 2 ]; then SI_OK=$((SI_OK+1)); else SI_BAD=$((SI_BAD+1)); SI_BADLIST="$SI_BADLIST $f"; fi
            continue
        fi
        "$BIN" "$f" -ir -o "$OUT/selfhost_ir_ref.ll" 2>"$OUT/selfhost_ir_referr.txt"; rc=$?
        if [ $rc -eq 0 ] && [ $rc2 -eq 0 ] && cmp -s "$OUT/selfhost_ir_ref.ll" "$OUT/selfhost_ir_got.txt"; then SI_OK=$((SI_OK+1)); SI_IR=$((SI_IR+1))
        elif [ $rc -ne 0 ] && [ $rc2 -eq 1 ] && cmp -s "$OUT/selfhost_ir_referr.txt" "$OUT/selfhost_ir_goterr.txt"; then SI_OK=$((SI_OK+1))
        else SI_BAD=$((SI_BAD+1)); SI_BADLIST="$SI_BADLIST $f"; fi
    done
    if [ "$SI_BAD" -eq 0 ] && [ "$SI_IR" -ge 50 ]; then
        pass "selfhost: 機械漢文の IR 生成器 (selfhost/irgen.mkn) が C++ 版と ${SI_IR} 個のプログラムで同じ IR を出す (核・IR 生成器自身を含む。診断で失敗するものも一致、計 ${SI_OK} 個)"
    else
        fail "selfhost: IR 生成器の不一致 ${SI_BAD} 個 (${SI_OK} 個一致、IR 一致 ${SI_IR} 個):$SI_BADLIST"
    fi
    # 自己再構築の予行: 機械漢文の IR 生成器 (ホストで動く) が自分自身のソースから作る IR が、C++ 版が作った IR と同じ
    "$OUT/selfhost_ir_host" "$OUT/selfhost_ir_all.mkn" >"$OUT/selfhost_ir_self.ll" 2>/dev/null
    if cmp -s "$OUT/selfhost_ir_self.ll" "$OUT/selfhost_ir.ll"; then
        pass "selfhost: 機械漢文の IR 生成器が自分自身のソースから作る IR が、C++ 版の作る IR と一致する ($(wc -l <"$OUT/selfhost_ir_self.ll" | tr -d ' ') 行)"
    else
        fail "selfhost: IR 生成器の自己再構築の IR が C++ 版と違う"
    fi
else
    fail "selfhost: IR 生成器をビルド"
    sed 's/^/      /' "$OUT/selfhost_ir.gen.log" "$OUT/selfhost_ir.cc.log" 2>/dev/null | head -10
fi

# --- セルフホスト第 5 段: 機械漢文のコンパイラ (selfhost/driver.mkn。取込の展開 + 型検査 + IR 生成) ----------------
#     根のソースを渡すだけで、tools/kernel-expand.sh + C++ 版 -ir と同じ IR を出す。さらに、機械漢文のコンパイラが
#     自分自身を 2 回再構築しても (C++ 版 → 第 2 世代 → 第 3 世代) IR が変わらない (不動点)。
if sh tools/kernel-expand.sh selfhost/cc_host.mkn "$OUT/selfhost_cc_all.mkn" \
   && "$BIN" "$OUT/selfhost_cc_all.mkn" -ir -o "$OUT/selfhost_cc.ll" 2>"$OUT/selfhost_cc.gen.log" \
   && "$CLANG" -Wno-override-module -x ir "$OUT/selfhost_cc.ll" -x c selfhost/host_cc.c -o "$OUT/selfhost_cc_host" \
        >"$OUT/selfhost_cc.cc.log" 2>&1; then
    SD_OK=0; SD_BAD=0; SD_BADLIST=""
    for f in kernel/kernel.mkn boot/loader.mkn boot/boot.mkn selfhost/lexer.mkn selfhost/parser.mkn selfhost/typecheck.mkn selfhost/irgen.mkn selfhost/cc_host.mkn $(grep -l '@取込' user/*.mkn); do
        sh tools/kernel-expand.sh "$f" "$OUT/selfhost_cc_exp.mkn" >/dev/null 2>&1
        "$BIN" "$OUT/selfhost_cc_exp.mkn" -ir -o "$OUT/selfhost_cc_ref.ll" 2>/dev/null; rc=$?
        "$OUT/selfhost_cc_host" "$f" >"$OUT/selfhost_cc_got.ll" 2>/dev/null; rc2=$?
        if [ $rc -eq 0 ] && [ $rc2 -eq 0 ] && cmp -s "$OUT/selfhost_cc_ref.ll" "$OUT/selfhost_cc_got.ll"; then SD_OK=$((SD_OK+1))
        else SD_BAD=$((SD_BAD+1)); SD_BADLIST="$SD_BADLIST $f"; fi
    done
    if [ "$SD_BAD" -eq 0 ] && [ "$SD_OK" -ge 10 ]; then
        pass "selfhost: 機械漢文のコンパイラ (selfhost/driver.mkn) が根のソースだけから取込を展開して、C++ 版と ${SD_OK} 個のプログラム (核・ローダー・行程・自分自身) で同じ IR を出す"
    else
        fail "selfhost: コンパイラの不一致 ${SD_BAD} 個 (${SD_OK} 個一致):$SD_BADLIST"
    fi
    "$OUT/selfhost_cc_host" selfhost/cc_host.mkn >"$OUT/selfhost_cc_gen2.ll" 2>/dev/null \
      && "$CLANG" -Wno-override-module -x ir "$OUT/selfhost_cc_gen2.ll" -x c selfhost/host_cc.c -o "$OUT/selfhost_cc_gen2_host" >/dev/null 2>&1 \
      && "$OUT/selfhost_cc_gen2_host" selfhost/cc_host.mkn >"$OUT/selfhost_cc_gen3.ll" 2>/dev/null
    if cmp -s "$OUT/selfhost_cc.ll" "$OUT/selfhost_cc_gen2.ll" && cmp -s "$OUT/selfhost_cc_gen2.ll" "$OUT/selfhost_cc_gen3.ll"; then
        pass "selfhost: 自己再構築の不動点 (C++ 版 → 第 2 世代 → 第 3 世代のコンパイラが作る自分自身の IR が全て同じ: $(wc -l <"$OUT/selfhost_cc_gen3.ll" | tr -d ' ') 行)"
    else
        fail "selfhost: 自己再構築の IR が世代で違う"
    fi
else
    fail "selfhost: コンパイラ (駆動部) をビルド"
    sed 's/^/      /' "$OUT/selfhost_cc.gen.log" "$OUT/selfhost_cc.cc.log" 2>/dev/null | head -10
fi

# --- type_error: 錯 E00xx must be reported --------------------------------
"$BIN" tests/type_error.mkn -ir -o /dev/null >"$OUT/type_error.log" 2>&1 \
    && fail "type_error: unexpected success" || pass "type_error: rejected"
if grep -q "E00" "$OUT/type_error.log"; then
    pass "type_error: diagnostic E00xx"
else
    fail "type_error: diagnostic E00xx"
fi

# --- QEMU: pure 機械漢文 driver prints 世界安寧 on the PL011 ---------------
if [ -f "$OUT/uart_mmio.elf" ]; then
    if command -v qemu-system-aarch64 >/dev/null 2>&1; then
        QLOG="$OUT/qemu.log"
        rm -f "$QLOG"
        qemu-system-aarch64 -M virt -cpu cortex-a57 -nographic \
            -serial "file:$QLOG" -kernel "$OUT/uart_mmio.elf" \
            >"$OUT/qemu.console.log" 2>&1 &
        QPID=$!
        # Wait up to ~10s for the expected output, then stop QEMU.
        for _ in $(seq 1 20); do
            grep -q "世界安寧" "$QLOG" 2>/dev/null && break
            sleep 0.5
        done
        kill "$QPID" 2>/dev/null
        wait "$QPID" 2>/dev/null
        if grep -q "世界安寧" "$QLOG" 2>/dev/null; then
            pass "qemu: 世界安寧 output (機械漢文 driver)"
        else
            fail "qemu: 世界安寧 output (機械漢文 driver)"
            sed 's/^/      /' "$QLOG" 2>/dev/null | head -20
        fi
    else
        echo "SKIP: qemu (qemu-system-aarch64 not found)"
    fi
else
    echo "SKIP: qemu (uart_mmio.elf not built)"
fi

# --- QEMU: 漢極 kernel — exception handler, MMU, memory ------------------
if [ -f "$OUT/kernel.elf" ]; then
    if command -v qemu-system-aarch64 >/dev/null 2>&1; then
        KLOG="$OUT/kernel_qemu.log"
        PIPE="$OUT/kernel_serial"
        rm -f "$KLOG" "$PIPE.in" "$PIPE.out"
        mkfifo "$PIPE.in" "$PIPE.out"
        # QEMU's pipe chardev: <path>.in is guest input, <path>.out is guest output.
        # The kernel's console is bidirectional, so 読込 (番10) can read this input.
        cat "$PIPE.out" > "$KLOG" &
        CATPID=$!
        # 設試 の vda (virtio-blk) 用の 32 KiB のディスクイメージ。QEMU の終了後に中身を調べる。
        dd if=/dev/zero of="$OUT/disk.img" bs=512 count=64 2>/dev/null
        qemu-system-aarch64 -M virt,gic-version=2 -cpu cortex-a57 -nographic \
            -global virtio-mmio.force-legacy=false \
            -drive file="$OUT/disk.img",if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 \
            -serial "pipe:$PIPE" -kernel "$OUT/kernel.elf" \
            >"$OUT/kernel_qemu.console.log" 2>&1 &
        QPID=$!
        # Feed one console line for the 読込 (番10) test.
        # Then feed 殻 (shell) commands once 甲 has read that line (M4).
        ( printf 'KANBUN\n' > "$PIPE.in"
          for _ in $(seq 1 60); do grep -q "甲得" "$KLOG" 2>/dev/null && break; sleep 0.25; done
          printf '響 天下太平\n讀 史記\n怪\n讀 無題\n目\n書 筆記 天地玄黄\n讀 筆記\n書 一二三四五六七八九十壱 x\n書 筆記\n目\n削 筆記\n讀 筆記\n目\n削 筆記\n書 新稿 草\n目\n問安 日月\n數 一 二 三\n識試\n名試\n時試\n時元試\n時\n時 史記\n信試\n信手試\n利試\n強試\n同試\n緩試\n録試\n篇試\n貯試\n件試\n設試\n系試\n例試\n副試\n実試\n章 天地/家/殻章\n移 天地/家/殻章\n在\n書 甲 一二\n改 甲 乙\n讀 乙\n改 甲\n移 ..\n在\n移 天地/典/史記\n移 天地/典\n在\n存在せず 子\nabcdefghijklmnopq\n\n終了\n   \n実作 oa\n実作 ob\n実作 abcdefghijklmnopqrst\n実作 abcdefghijklmnopqrstu\n実作 日本\n実作 a/b\n実目\n仮置 oa ob\n実目\n実削 oa\n実目\n実名 ob oc\n実目\n実削 oc\n実目\n助\n終\n響 再起\n終\n' > "$PIPE.in" ) &
        FEEDPID=$!
        # Wait up to ~40s for the final marker, then stop QEMU.  The generic
        # timer fires five times (5 × CNTFRQ/40 ≈ 125 ms); the long parts are the
        # BTRON3 file-management test (録試) and the memory test (貯試), which
        # grows with every stage (3 つの子を起動して回収する).
        # 終 は殻を終えるだけで殻行程 (乙、init 兼殻) は終了しないため、再起動後の
        # 殻起動・殻響 と 2 回目の 殻終 を最終マーカーにする。
        for _ in $(seq 1 80); do
            [ "$(grep -ac "殻終" "$KLOG" 2>/dev/null)" -ge 2 ] 2>/dev/null && \
                grep -q "殻響:再起" "$KLOG" 2>/dev/null && break
            sleep 0.5
        done
        kill "$QPID" 2>/dev/null
        wait "$QPID" 2>/dev/null
        wait "$CATPID" 2>/dev/null
        kill "$FEEDPID" 2>/dev/null
        wait "$FEEDPID" 2>/dev/null
        if grep -q "超漢文起動" "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 超漢文起動 output"
        else
            fail "kernel qemu: 超漢文起動 output"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        if grep -q "異常捕獲 ESR=0x00000000f2000000" "$KLOG" 2>/dev/null; then
            pass "kernel qemu: exception handler caught BRK (ESR decode)"
        else
            fail "kernel qemu: exception handler caught BRK (ESR decode)"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        if grep -q "異常後継続" "$KLOG" 2>/dev/null; then
            pass "kernel qemu: resumed after exception (eret)"
        else
            fail "kernel qemu: resumed after exception (eret)"
        fi
        if grep -q "記憶管理有効" "$KLOG" 2>/dev/null; then
            pass "kernel qemu: MMU enabled (identity map live)"
        else
            fail "kernel qemu: MMU enabled (identity map live)"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        if grep -q "0x0000000040400000" "$KLOG" 2>/dev/null; then
            pass "kernel qemu: physical page allocator"
        else
            fail "kernel qemu: physical page allocator"
        fi
        # --- M5/P0: 頁池 (ビットマップ) の割当・解放 ---------------------------
        pool_val() { grep -a "頁池 $1 " "$KLOG" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}'; }
        POOL_BAD=""
        for kv in 異頁=1 残減=1 解放=1 二重=0 範囲外=0 境界外=0 再利用=1 零埋=0 復元=1 枯渇数=1 枯渇零=1 枯渇復元=1; do
            k="${kv%%=*}"; want="$(printf '0x%016x' "${kv##*=}")"
            got="$(pool_val "$k")"
            [ "$got" = "$want" ] || POOL_BAD="$POOL_BAD $k(want=$want got=${got:-none})"
        done
        if [ -z "$POOL_BAD" ]; then
            pass "kernel qemu: 頁池 割当・解放・二重解放・範囲外・再利用・ゼロ埋め・空き数の復元・枯渇 (全頁を取り切って 0 が返り、全部放して復元)"
        else
            fail "kernel qemu: 頁池 (不一致:$POOL_BAD)"
            grep -a '頁池' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # --- M2 hardware: generic timer + GICv2 timer interrupt ---------------
        if grep -q "刻止" "$KLOG" 2>/dev/null; then
            pass "kernel qemu: GICv2 timer IRQ delivered (刻止)"
        else
            fail "kernel qemu: GICv2 timer IRQ delivered (刻止)"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        if grep -q "割込完了 周波数=0x" "$KLOG" 2>/dev/null; then
            pass "kernel qemu: IRQ handler returned via eret (割込完了)"
        else
            fail "kernel qemu: IRQ handler returned via eret (割込完了)"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        # --- M3 software: EL0 行程 + SVC + 漢令 ABI + スケジューラ + 空間分離 ----
        if grep -q "民籍投入" "$KLOG" 2>/dev/null; then
            pass "kernel qemu: EL0 行程を投入 (民籍投入)"
        else
            fail "kernel qemu: EL0 行程を投入 (民籍投入)"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        K_AK="$(grep -oE '甲棧 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_BK="$(grep -oE '乙棧 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        if [ -n "$K_AK" ] && [ -n "$K_BK" ] && [ "$K_AK" != "$K_BK" ] && \
           [ $((K_AK)) -ge $((0x40320000)) ] && [ $((K_AK)) -lt $((0x40340000)) ] && \
           [ $((K_BK)) -ge $((0x40320000)) ] && [ $((K_BK)) -lt $((0x40340000)) ]; then
            pass "kernel qemu: 行程ごとの核棧 (甲='${K_AK}' 乙='${K_BK}' が別アドレス)"
        else
            fail "kernel qemu: 行程ごとの核棧 (甲='${K_AK:-none}' 乙='${K_BK:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        K_AW="$(grep -oE '甲書 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_BW="$(grep -oE '乙書 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        if [ "$K_AW" = "0x000000000000000a" ] && [ "$K_BW" = "0x000000000000000b" ]; then
            pass "kernel qemu: 2 行程が EL0 で 書出/書数 を実行 (甲書=0xa 乙書=0xb)"
        else
            fail "kernel qemu: 2 行程が EL0 で 書出/書数 を実行 (A='${K_AW:-none}' B='${K_BW:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        K_AR="$(grep -oE '甲讀 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_BR="$(grep -oE '乙讀 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        if [ "$K_AR" = "$K_AW" ] && [ "$K_BR" = "$K_BW" ] && [ "$K_AR" != "$K_BR" ]; then
            pass "kernel qemu: 行程ごとのアドレス空間 (同一仮想アドレスで各自の値)"
        else
            fail "kernel qemu: 行程ごとのアドレス空間 (甲讀='${K_AR:-none}' 乙讀='${K_BR:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        # --- M3: デマンドページング (未写像の窓ページを触れると頁が与えられる) ---
        K_PG="$(grep -cE '頁供 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null)"
        if [ "${K_PG:-0}" -ge 4 ]; then
            pass "kernel qemu: デマンドページングで頁を供給 (頁供 x${K_PG})"
        else
            fail "kernel qemu: デマンドページングで頁を供給 (頁供 x${K_PG:-0})"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -30
        fi
        K_AP="$(grep -oE '甲頁 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_BP="$(grep -oE '乙頁 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        if [ "$K_AP" = "0x0000000000001000" ] && [ "$K_BP" = "0x0000000000001001" ]; then
            pass "kernel qemu: 未写像ページが触れた時に写像される (甲頁=0x1000 乙頁=0x1001)"
        else
            fail "kernel qemu: 未写像ページが触れた時に写像される (甲頁='${K_AP:-none}' 乙頁='${K_BP:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -30
        fi
        K_FA="$(grep -oE '頁供 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -c '0000000040701000')"
        if [ "${K_FA:-0}" -ge 2 ]; then
            pass "kernel qemu: 欠址が窓内の未写像頁 (0x40701000 を 2 回)"
        else
            fail "kernel qemu: 欠址が窓内の未写像頁 (0x40701000 x${K_FA:-0})"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -30
        fi
        K_PF="$(grep -oE '頁供 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -c '0000000040702000')"
        if [ "${K_PF:-0}" -ge 1 ]; then
            pass "kernel qemu: 読込 が書込先の頁を先に張る (0x40702000)"
        else
            fail "kernel qemu: 読込 が書込先の頁を先に張る (0x40702000 x${K_PF:-0})"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -30
        fi
        K_AE="$(grep -oE '甲禁 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_BE="$(grep -oE '乙禁 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        if [ "$K_AE" = "0xfffffffffffffff2" ] && [ "$K_BE" = "0xfffffffffffffff2" ]; then
            pass "kernel qemu: 核専用域への 書出 を -EFAULT で拒否"
        else
            fail "kernel qemu: 核専用域への 書出 を -EFAULT で拒否 (甲='${K_AE:-none}' 乙='${K_BE:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        K_ALE="$(grep -oE '甲令 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_BLE="$(grep -oE '乙令 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        if [ "$K_ALE" = "0xffffffffffffffda" ] && [ "$K_BLE" = "0xffffffffffffffda" ]; then
            pass "kernel qemu: 未知の漢令番号を -ENOSYS で拒否"
        else
            fail "kernel qemu: 未知の漢令番号を -ENOSYS で拒否 (甲='${K_ALE:-none}' 乙='${K_BLE:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        K_ALN="$(grep -oE '甲長 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_BLN="$(grep -oE '乙長 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        if [ "$K_ALN" = "0xfffffffffffffff2" ] && [ "$K_BLN" = "0xfffffffffffffff2" ]; then
            pass "kernel qemu: 長さの上限超過を -EFAULT で拒否"
        else
            fail "kernel qemu: 長さの上限超過を -EFAULT で拒否 (甲='${K_ALN:-none}' 乙='${K_BLN:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        K_ARD="$(grep -oE '甲読 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_BRD="$(grep -oE '乙読 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        if [ "$K_ARD" = "0xfffffffffffffff2" ] && [ "$K_BRD" = "0xfffffffffffffff2" ]; then
            pass "kernel qemu: 核専用域への 読込 を -EFAULT で拒否"
        else
            fail "kernel qemu: 核専用域への 読込 を -EFAULT で拒否 (甲='${K_ARD:-none}' 乙='${K_BRD:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        K_AG="$(grep -oE '甲得 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_RX="$(grep -oE 'KANBUN' "$KLOG" 2>/dev/null | head -1)"
        if [ "$K_AG" = "0x0000000000000007" ] && [ "$K_RX" = "KANBUN" ]; then
            pass "kernel qemu: UART 入力の 読込 (甲得=0x7, 入力 KANBUN を読み戻す)"
        else
            fail "kernel qemu: UART 入力の 読込 (甲得='${K_AG:-none}' 入力='${K_RX:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -30
        fi
        # --- M4: 典籍 (RAMFS/VFS) ---
        K_FO="$(grep -oE '籍開 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_FR="$(grep -oE '籍読 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_FC="$(grep -c '黄帝者、少典之子、姓公孫' "$KLOG" 2>/dev/null)"
        K_FW="$(grep -oE '籍書 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_FX="$(grep -oE '籍閉 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_FB="$(grep -oE '籍再 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_FN="$(grep -oE '籍無 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        if [ "$K_FO" = "0x0000000000000003" ] && [ "$K_FR" = "0x0000000000000024" ] && [ "${K_FC:-0}" -ge 1 ]; then
            pass "kernel qemu: 典籍 開→讀入 (史記 を 36 バイト読む)"
        else
            fail "kernel qemu: 典籍 開→讀入 (開='${K_FO:-none}' 読='${K_FR:-none}' 内容=${K_FC:-0})"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -30
        fi
        if [ "$K_FW" = "0x0000000000000006" ] && [ "$K_FX" = "0x0000000000000000" ]; then
            pass "kernel qemu: 典籍 柄書→閉"
        else
            fail "kernel qemu: 典籍 柄書→閉 (書='${K_FW:-none}' 閉='${K_FX:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -30
        fi
        if [ "$K_FB" = "0xfffffffffffffff7" ] && [ "$K_FN" = "0xfffffffffffffffe" ]; then
            pass "kernel qemu: 典籍の誤り経路 (閉後→-EBADF, 無い名前→-ENOENT)"
        else
            fail "kernel qemu: 典籍の誤り経路 (再='${K_FB:-none}' 無='${K_FN:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -30
        fi
        # --- M4: 漢文シェル (殻) ---
        if grep -q "殻起動" "$KLOG" 2>/dev/null && grep -q "殻響:天下太平" "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 殻 起動と 響 (UART 入力を解析して出力)"
        else
            fail "kernel qemu: 殻 起動と 響"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -40
        fi
        if grep -q "殻讀:黄帝者、少典之子、姓公孫" "$KLOG" 2>/dev/null && grep -q "殻無" "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 殻 讀 (典籍を開いて表示、無い名前は 殻無)"
        else
            fail "kernel qemu: 殻 讀"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -40
        fi
        # --- M4: 殻の命令拡充 (目 = 一覧、書 = 作成/書込) ---
        K_LS1="$(grep -c '殻目:史記' "$KLOG" 2>/dev/null)"
        K_LS2="$(grep -c '殻目:詩経' "$KLOG" 2>/dev/null)"
        K_LS3="$(grep -c '殻目:筆記' "$KLOG" 2>/dev/null)"
        if [ "${K_LS1:-0}" -ge 2 ] && [ "${K_LS2:-0}" -ge 2 ] && [ "${K_LS3:-0}" -eq 1 ]; then
            pass "kernel qemu: 殻 目 (一覧。書の前は 2 件、後は 筆記 が加わる)"
        else
            fail "kernel qemu: 殻 目 (史記=${K_LS1:-0} 詩経=${K_LS2:-0} 筆記=${K_LS3:-0})"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -60
        fi
        K_WR="$(grep -oE '殻書 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}')"
        if [ "$K_WR" = "0x000000000000000c" ] && grep -q '殻讀:天地玄黄' "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 殻 書→讀 (筆記 を作って 12 バイト書き、読み戻す)"
        else
            fail "kernel qemu: 殻 書→讀 (書='${K_WR:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -60
        fi
        if grep -q '殻誤 0xffffffffffffffdc' "$KLOG" 2>/dev/null && grep -q '殻用法' "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 殻 書 の誤り経路 (32 バイトを超える名前→-ENAMETOOLONG、引数不足→用法)"
        else
            fail "kernel qemu: 殻 書 の誤り経路"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -60
        fi
        # --- M4/F0: 典籍の削除 (削) ---
        K_DEL="$(grep -c '殻削:筆記' "$KLOG" 2>/dev/null)"
        K_NO="$(grep -c '^殻無\|殻> 殻無' "$KLOG" 2>/dev/null)"
        K_REUSE="$(grep -c '殻目:新稿' "$KLOG" 2>/dev/null)"
        K_LIST3="$(grep -c '殻目:筆記' "$KLOG" 2>/dev/null)"
        if [ "${K_DEL:-0}" -eq 1 ] && [ "${K_NO:-0}" -ge 2 ] && [ "${K_LIST3:-0}" -eq 1 ]; then
            pass "kernel qemu: 殻 削 (削った典籍は 讀 で 殻無、目 の一覧からも消える)"
        else
            fail "kernel qemu: 殻 削 (削=${K_DEL:-0} 殻無=${K_NO:-0} 削除後の一覧に筆記=${K_LIST3:-0})"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -80
        fi
        if grep -q '殻誤 0xfffffffffffffffe' "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 殻 削 の誤り経路 (無い名前→-ENOENT)"
        else
            fail "kernel qemu: 殻 削 の誤り経路"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -80
        fi
        if [ "${K_REUSE:-0}" -eq 1 ]; then
            pass "kernel qemu: 殻 削 のあと作成 (削った枠を再利用して 新稿 が一覧に出る)"
        else
            fail "kernel qemu: 殻 削 のあと作成 (新稿=${K_REUSE:-0})"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -80
        fi
        # --- 篇藏 F2: 殻の章操作 (章・移・在・改) ---
        K_DIR="$(sed -n '/^殻章:天地\/家\/殻章/,/^殻在:天地\/典/p' "$KLOG" 2>/dev/null | tr -d '\r' | grep -a '^殻' | grep -av '^殻> ' | paste -sd'|' -)"
        K_DIR_WANT='殻章:天地/家/殻章|殻移:天地/家/殻章|殻在:天地/家/殻章|殻書 0x0000000000000006|殻改:甲→乙|殻讀:一二|殻用法 改 旧 新|殻移:..|殻在:天地/家|殻誤 0xffffffffffffffec|殻移:天地/典|殻在:天地/典'
        if [ "$K_DIR" = "$K_DIR_WANT" ]; then
            pass "kernel qemu: 殻 章・移・在・改 (章を作って移り、書いた篇を名替して読み、.. で上がり、章でない先は -ENOTDIR、天地/典 へ戻る)"
        else
            fail "kernel qemu: 殻 章・移・在・改 (got='${K_DIR:-none}')"
            grep -a '殻' "$KLOG" 2>/dev/null | sed 's/^/      /' | tail -40
        fi
        K_HELP="$(grep -c '殻命令一覧' "$KLOG" 2>/dev/null)"
        if [ "${K_HELP:-0}" -eq 1 ] && grep -q '書 名 文  … 典籍を作って文を書く' "$KLOG" 2>/dev/null \
           && grep -q '改 旧 新   … 篇の名を替える' "$KLOG" 2>/dev/null \
           && grep -q '終        … 殻を終える' "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 殻 助 (命令一覧を表示)"
        else
            fail "kernel qemu: 殻 助 (一覧見出し=${K_HELP:-0})"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -60
        fi
        if grep -q "殻不明" "$KLOG" 2>/dev/null && grep -q "殻終" "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 殻 未知の命令と 終"
        else
            fail "kernel qemu: 殻 未知の命令と 終"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -40
        fi
        # --- M5/P1: 行程の生成・待機・終了 (生行程/待行程/終行程) ---------------------
        sp_val() { grep -a "^$1 " "$KLOG" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}'; }
        SP_BAD=""
        for kv in '生=3' '待識=3' '待碼=7' '生無=0xfffffffffffffffe' '待無=0xfffffffffffffff6' '生繰返 成功=20' '生繰返 頁残差=0'; do
            k="${kv%%=*}"; v="${kv#*=}"
            case "$v" in 0x*) want="$v" ;; *) want="$(printf '0x%016x' "$v")" ;; esac
            got="$(sp_val "$k")"
            [ "$got" = "$want" ] || SP_BAD="$SP_BAD [$k want=$want got=${got:-none}]"
        done
        if [ -z "$SP_BAD" ]; then
            pass "kernel qemu: 生行程・待行程 (子の識=3、終了コード 7 を回収、無い名前 -ENOENT、子が無ければ -ECHILD)"
        else
            fail "kernel qemu: 生行程・待行程 (不一致:$SP_BAD)"
            grep -a '^生\|^待\|子行程' "$KLOG" 2>/dev/null | sed 's/^/      /' | head -30
        fi
        if grep -aq '子行程起動 天下' "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 子行程が漢像から起動し、引数 (天下) を受け取って出力 (EL0、別の窓)"
        else
            fail "kernel qemu: 子行程が漢像から起動し、引数を受け取る"
            grep -a '子行程\|異常' "$KLOG" 2>/dev/null | sed 's/^/      /' | head
        fi
        K_CH="$(grep -ac '子行程起動' "$KLOG" 2>/dev/null)"
        # 枠の枯渇: 待たずに起動し続けて行程表が満杯 (-EAGAIN)、全員を回収でき、回収後にまた起動できる
        EX_N="$(sp_val '枯渇 起動数')"; EX_FULL="$(sp_val '枯渇 満杯')"; EX_REAP="$(sp_val '枯渇 回収')"; EX_RE="$(sp_val '枯渇 再起動')"
        EX_NUM=$((EX_N))
        if [ "$EX_FULL" = "0xfffffffffffffff5" ] && [ "$EX_NUM" -ge 1 ] && [ "$EX_NUM" -le 7 ] \
                && [ "$EX_REAP" = "$EX_N" ] && [ "$EX_RE" = "0x0000000000000001" ]; then
            pass "kernel qemu: 行程表の枯渇 (空き枠 ${EX_NUM} 個を使い切ると -EAGAIN、全員を回収し、回収後にまた起動できる)"
        else
            fail "kernel qemu: 行程表の枯渇 (起動数=${EX_N:-none} 満杯=${EX_FULL:-none} 回収=${EX_REAP:-none} 再起動=${EX_RE:-none})"
            grep -a '^枯渇' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # 頁が足りないとき (空き 0〜3 頁) の 生行程 は -ENOMEM で失敗し、頁が漏れず、全部放して空き数が戻る
        if [ "$(sp_val '資不足')" = "0x00000000000000ff" ]; then
            pass "kernel qemu: 頁不足の 生行程 (空き 0〜3 頁で -ENOMEM、失敗後も頁が漏れず、全部放して空き数が戻る)"
        else
            fail "kernel qemu: 頁不足の 生行程 (資不足=$(sp_val '資不足') 期待 0xff)"
        fi
        # 異常終了: 保護違反 (EC 36) と BRK (EC 60) は子だけを終え (128 + EC)、正常な子は 5 で終わり、親は走り続け、頁は漏れない
        if [ "$(sp_val '異常終了 保護違反')" = "0x00000000000000a4" ] && [ "$(sp_val '異常終了 BRK')" = "0x00000000000000bc" ] \
                && [ "$(sp_val '異常終了 正常')" = "0x0000000000000005" ] && [ "$(sp_val '異常終了 回収')" = "0x0000000000000003" ] \
                && [ "$(sp_val '異常終了 頁残差')" = "0x0000000000000000" ] \
                && [ "$(sp_val '異常終了 コード書込')" = "0x00000000000000a4" ] && [ "$(sp_val '異常終了 データ実行')" = "0x00000000000000a0" ]; then
            pass "kernel qemu: 異常終了とメモリ保護 (核専用域への書込 → 164、自分のコードへの書込 → 164、データ域への飛び込み → 160、BRK → 188、正常 → 5。核は子だけを終え、親は走り続けて 3 つとも回収し、頁が漏れない)"
        else
            fail "kernel qemu: 異常終了 (保護違反=$(sp_val '異常終了 保護違反') BRK=$(sp_val '異常終了 BRK') 正常=$(sp_val '異常終了 正常') 回収=$(sp_val '異常終了 回収') 頁残差=$(sp_val '異常終了 頁残差'))"
            grep -a '^異常終了\|民異常' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # 長時間: 200 回の起動・回収がすべて成功し、頁が漏れず、識が単調に増えている
        LT_OK="$(sp_val '長時間 成功')"; LT_PG="$(sp_val '長時間 頁残差')"; LT_ID="$(sp_val '長時間 識増')"
        if [ "$LT_OK" = "$(printf '0x%016x' 200)" ] && [ "$LT_PG" = "0x0000000000000000" ] \
                && [ -n "$LT_ID" ] && [ "$((LT_ID))" -gt 200 ]; then
            pass "kernel qemu: 長時間 (起動・回収 200 回が全て成功、頁が漏れない、識は $((LT_ID)) まで増えた)"
        else
            fail "kernel qemu: 長時間 (成功=${LT_OK:-none} 頁残差=${LT_PG:-none} 識=${LT_ID:-none})"
        fi
        # 子の出力 = 検証 21 + 殻の 問安 1 + 篇試 が術のパスで起動する 問安 1 + 貯試 が起動する 3 役
        if [ "${K_CH:-0}" -eq $((226 + EX_NUM + 1)) ]; then
            pass "kernel qemu: 起動・回収を 20 回繰り返しても頁が漏れず、毎回子が走る (子の出力 $((226 + EX_NUM + 1)) 回 = 検証 21 + 長時間 200 + 殻 1 + 篇試 1 + 貯試 3 + 枯渇の試験 $((EX_NUM + 1)))"
        else
            fail "kernel qemu: 起動・回収の繰り返し (子の出力=${K_CH:-0} 回、期待 $((226 + EX_NUM + 1)))"
        fi
        # --- M5/P2: 殻が外部命令を起動する (引数 argc/argv と柄の継承) ----------------
        if grep -aq '^子行程起動 日月' "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 殻から外部命令 問安 を起動し、引数 (日月) が子に渡る"
        else
            fail "kernel qemu: 殻から外部命令 問安 を起動し、引数が子に渡る"
            grep -a '殻\|子行程' "$KLOG" 2>/dev/null | sed 's/^/      /' | tail -20
        fi
        K_ARGC="$(grep -a '^數 個数 ' "$KLOG" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}')"
        K_ARGL="$(grep -a '^數 長合 ' "$KLOG" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}')"
        K_RC="$(grep -a '^殻碼 ' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}' | paste -sd' ' -)"
        if [ "$K_ARGC" = "0x0000000000000004" ] && [ "$K_ARGL" = "0x0000000000000009" ] \
           && [ "$K_RC" = "0x0000000000000007 0x0000000000000004" ]; then
            pass "kernel qemu: argv の受け渡し (數 一 二 三 → argc=4、長さの合計=9)、終了コードを 殻碼 で表示 (7, 4)"
        else
            fail "kernel qemu: argv の受け渡し (argc=${K_ARGC:-none} 長合=${K_ARGL:-none} 殻碼='${K_RC:-none}')"
            grep -a '殻\|數\|子行程' "$KLOG" 2>/dev/null | sed 's/^/      /' | tail -20
        fi
        # --- #42 G0: BTRON3 互換層 (user/btron/) の get_tid と ER_* ----------------
        btron_val() { grep -a "^識試 $1 " "$KLOG" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}'; }
        BTRON_BAD=""
        for k in 'get_tid=識別' 'get_tid>0' 'ER_負' '錯換' 'H=符号付16' 'H=32767' 'H=-32768' 'H隣欄保持' 'Bool=False0True1' 'SIZE配置' 'PNT配置' 'RECT4辺' 'RECT共用体' 'ErrCode共用体LE' 'ER_全名eclass=-1' 'ER_全名detail通し番号' '制御0000-0020/007F' 'TC_A=2121-7E7E' 'TC_B=8021-FD7E' 'TC_C=2180-7EFD' 'TC_D=8080-FDFD' '言語指定FE21-FEFE' '特殊FF21-FF7E/ESC FF80-FFFE/EOF' '空白3種' 'TC至UC記号' 'TC至UC仮名漢字' 'TC至UC割当なし' 'UC至TC' 'A全往復6877' 'TAD書き可変' 'TAD読み戻し' 'TAD異常' 'TADラージ' 'TAD管理情報' 'TAD管理情報読み' 'TAD文章始終' 'TAD図形始終' 'TAD始異常' 'TAD仮身書き' 'TAD仮身読み' 'TAD仮身データ' 'TAD仮身異常' 'TAD画像書き' 'TAD画像読み' 'TAD画像色' 'TAD画像異常' 'TAD機能付箋書き' 'TAD機能付箋読み' 'TAD指定付箋' 'TAD付箋異常'; do
            got="$(btron_val "$k")"
            [ "$got" = "0x0000000000000001" ] || BTRON_BAD="$BTRON_BAD $k(got=${got:-none})"
        done
        if [ -z "$BTRON_BAD" ]; then
            pass "kernel qemu: BTRON3 互換層 get_tid が 漢令 識別 と一致し正、ER_* が負、錯換の対応が正しい、共有データ編 §1 の H・Bool・SIZE・PNT・RECT・ErrCode が配置どおり、§2 の TRON コードの符号領域の分類が境界値どおり、A ゾーンと Unicode の変換、§3 の TAD セグメントの枠の読み書き"
        else
            fail "kernel qemu: BTRON3 互換層 (不一致:$BTRON_BAD)"
            grep -a '識試' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # --- #42 M6: メモリ管理 (1.5) get_mbk / rel_mbk / mbk_sts ----------------------
        MB_N="$(grep -ac '^貯試 ' "$KLOG" 2>/dev/null)"
        MB_BAD="$(grep -a '^貯試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${MB_N:-0}" -eq 45 ] && [ "${MB_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 メモリ管理 (get_mbk・rel_mbk・mbk_sts・malloc 族・共有・システム・DELEXIT 権限・枯渇の ${MB_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 メモリ管理 (項目=${MB_N:-0}/45、失敗=${MB_BAD:-?})"
            grep -a '^貯試 ' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # --- M7a: イベント管理 (1.7) 漢令 192〜211 -----------------------------------
        EV_N="$(grep -ac '^件試 ' "$KLOG" 2>/dev/null)"
        EV_BAD="$(grep -a '^件試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${EV_N:-0}" -eq 73 ] && [ "${EV_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 イベント管理 (get_evt・put_evt・clr_evt・get_pdp・set_pdp・get_etm・get_kmp・chg_emk・set_krp・get_krp・set_krm・get_krm・get_kid・get_ktb・set_ktb・chg_pda・sig_buz・ctl_buz・req_evt・las_evt の ${EV_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 イベント管理 (項目=${EV_N:-0}/73、失敗=${EV_BAD:-?})"
            grep -a '^件試 ' "$KLOG" 2>/dev/null | grep -av '0x0000000000000001$' | sed 's/^/      /' | head -40
        fi
        # --- M7b: デバイス管理 (1.8) 漢令 212〜220 -----------------------------------
        DV_N="$(grep -ac '^設試 ' "$KLOG" 2>/dev/null)"
        DV_BAD="$(grep -a '^設試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${DV_N:-0}" -eq 97 ] && [ "${DV_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 デバイス管理 (opn_dev・cls_dev・rea_dev・wri_dev・chg_dmd・dev_sts・get_dev・lst_dev・sus_dev の ${DV_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 デバイス管理 (項目=${DV_N:-0}/97、失敗=${DV_BAD:-?})"
            grep -a '^設試 ' "$KLOG" 2>/dev/null | grep -av '0x0000000000000001$' | sed 's/^/      /' | head -40
        fi
        # --- vda (virtio-blk): QEMU が終わったあとのディスクイメージに、書いた区画が届いている ----
        if [ -f "$OUT/disk.img" ]; then
            IMG_S3="$(od -An -v -tx1 -j 1536 -N 4 "$OUT/disk.img" | tr -s ' ' | sed 's/^ //; s/ $//')"
            IMG_S10="$(od -An -v -tx1 -j 5120 -N 4 "$OUT/disk.img" | tr -s ' ' | sed 's/^ //; s/ $//')"
            IMG_S4="$(od -An -v -tx1 -j 2048 -N 4 "$OUT/disk.img" | tr -s ' ' | sed 's/^ //; s/ $//')"
            if [ "$IMG_S3" = "05 06 07 08" ] && [ "$IMG_S10" = "28 29 2a 2b" ] && [ "$IMG_S4" = "00 00 00 00" ]; then
                pass "kernel qemu: vda (virtio-blk) に書いた区画 3・10 がディスクイメージに届き、書いていない区画 4 は 0 のまま"
            else
                fail "kernel qemu: vda のディスクイメージ (区画 3='$IMG_S3' 区画 10='$IMG_S10' 区画 4='$IMG_S4')"
            fi
        else
            fail "kernel qemu: vda のディスクイメージが無い"
        fi
        # --- M7c: システム管理 (1.10) 漢令 179〜180 ----------------------------------
        # --- 3.8 実身／仮身マネージャ (docs/design-object-model.md) V1a: 登録簿 -----------------
        OM_N="$(grep -ac '^実試 ' "$KLOG" 2>/dev/null)"
        OM_BAD="$(grep -a '^実試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${OM_N:-0}" -eq 60 ] && [ "${OM_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 実身／仮身マネージャの登録簿・実身の操作・続柄・起動 (oreg_vob ほか V1a・V1b・V2・V3・V4a・V4b-1・V4b-2 の ${OM_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 実身／仮身マネージャの登録簿と実身の操作 (項目=${OM_N:-0}/60、失敗=${OM_BAD:-?})"
            grep -a '^実試 ' "$KLOG" 2>/dev/null | grep -av '0x0000000000000001$' | sed 's/^/      /' | head -40
        fi
        SV_N="$(grep -ac '^系試 ' "$KLOG" 2>/dev/null)"
        SV_BAD="$(grep -a '^系試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${SV_N:-0}" -eq 38 ] && [ "${SV_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 システム管理 (get_ver・get_cnf の ${SV_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 システム管理 (項目=${SV_N:-0}/38、失敗=${SV_BAD:-?})"
            grep -a '^系試 ' "$KLOG" 2>/dev/null | grep -av '0x0000000000000001$' | sed 's/^/      /' | head -40
        fi
        EX_N="$(grep -ac '^例試 ' "$KLOG" 2>/dev/null)"
        EX_BAD="$(grep -a '^例試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${EX_N:-0}" -eq 16 ] && [ "${EX_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 例外ハンドラ (def_exc・ret_exc・EL0 上り呼びの ${EX_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 例外ハンドラ (項目=${EX_N:-0}/16、失敗=${EX_BAD:-?})"
            grep -a '^例試 ' "$KLOG" 2>/dev/null | grep -av '0x0000000000000001$' | sed 's/^/      /' | head -40
        fi
        MH_N="$(grep -ac '^信手試 ' "$KLOG" 2>/dev/null)"
        MH_BAD="$(grep -a '^信手試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${MH_N:-0}" -eq 25 ] && [ "${MH_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 メッセージハンドラ (def_msg・ret_msg・入れ子抑制・MH_NONE/BREAK/TERM の ${MH_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 メッセージハンドラ (項目=${MH_N:-0}/25、失敗=${MH_BAD:-?})"
            grep -a '^信手試 ' "$KLOG" 2>/dev/null | grep -av '0x0000000000000001$' | sed 's/^/      /' | head -40
        fi
        # --- 1.1 副タスク (cre_tsk・ext_tsk・ter_tsk・slp/wup/can_wup・chg_pri・配分比) ------
        SB_N="$(grep -ac '^副試 ' "$KLOG" 2>/dev/null)"
        SB_BAD="$(grep -a '^副試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${SB_N:-0}" -eq 21 ] && [ "${SB_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 副タスク (cre_tsk・ext_tsk・ter_tsk・slp_tsk/wup_tsk/can_wup・chg_pri・get_inf の ${SB_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 副タスク (項目=${SB_N:-0}/21、失敗=${SB_BAD:-?})"
            grep -a '^副試 ' "$KLOG" 2>/dev/null | sed 's/^/      /' | head -40
        fi
        # --- 篇藏 F1〜F3 (#6): 篇ID・屬、章とパス、名替、權・志・器・術・法 ---------------
        PF_N="$(grep -ac '^篇試 ' "$KLOG" 2>/dev/null)"
        PF_BAD="$(grep -a '^篇試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${PF_N:-0}" -eq 41 ] && [ "${PF_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: 篇藏 F1〜F4 (標・索を含む ${PF_N} 項目)"
        else
            fail "kernel qemu: 篇藏 F1〜F3 (項目=${PF_N:-0}/41、失敗=${PF_BAD:-?})"
            grep -a '^篇試 ' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        if grep -aq '^篇試器盤出力' "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 篇藏 器/盤 への書込が UART に出る"
        else
            fail "kernel qemu: 篇藏 器/盤 への書込が UART に出ない"
        fi
        # --- #42 1.6 B1: ファイル管理の接続とパス解決 ----------------------------------
        FL_N="$(grep -ac '^録試 ' "$KLOG" 2>/dev/null)"
        FL_BAD="$(grep -a '^録試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${FL_N:-0}" -eq 122 ] && [ "${FL_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 ファイル管理 B1・B2 (接続・get_lnk・chg_wrk・作成・削除・開閉・状態の ${FL_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 ファイル管理 B1 (項目=${FL_N:-0}/122、失敗=${FL_BAD:-?})"
            grep -a '^録試 ' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # --- #42 G6b: メッセージバッファとランデブポート (1.3) ------------------------
        CM_N="$(grep -ac '^緩試 ' "$KLOG" 2>/dev/null)"
        CM_BAD="$(grep -a '^緩試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${CM_N:-0}" -eq 35 ] && [ "${CM_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 メッセージバッファ・ランデブ (環の折り返し・待ち・中断・転送・削除の ${CM_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 メッセージバッファ・ランデブ (項目=${CM_N:-0}/35、失敗=${CM_BAD:-?})"
            grep -a '^緩試 ' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # --- #42 G6a: セマフォとイベントフラグ (1.3) -------------------------------------
        SY_N="$(grep -ac '^同試 ' "$KLOG" 2>/dev/null)"
        SY_BAD="$(grep -a '^同試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${SY_N:-0}" -eq 29 ] && [ "${SY_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 セマフォ・イベントフラグ (FIFO・時間切れ・中断・削除・DELEXIT・自動返却・上限・OR 待ちの ${SY_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 セマフォ・イベントフラグ (項目=${SY_N:-0}/29、失敗=${SY_BAD:-?})"
            grep -a '^同試 ' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # --- #42 G5: ter_prc (MS_TERM・TERM_ALL・ER_LEVEL・ER_SELF) と prc_sts ------------
        TM_N="$(grep -ac '^強試 ' "$KLOG" 2>/dev/null)"
        TM_BAD="$(grep -a '^強試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${TM_N:-0}" -eq 23 ] && [ "${TM_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 強制終了・行程状態 (${TM_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 強制終了・行程状態 (項目=${TM_N:-0}/23、失敗=${TM_BAD:-?})"
            grep -a '^強試 ' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # --- #42 G4: 利用者情報 (get_usr / chg_usr) と set_tim / set_tod の権限 --------
        US_N="$(grep -ac '^利試 ' "$KLOG" 2>/dev/null)"
        US_BAD="$(grep -a '^利試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${US_N:-0}" -eq 19 ] && [ "${US_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 利用者情報・時刻設定の権限 (${US_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 利用者情報・時刻設定の権限 (項目=${US_N:-0}/19、失敗=${US_BAD:-?})"
            grep -a '^利試 ' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # 暦差の検証: 時試が出す現在の日付が、ホストの UTC の日付 (前後 1 日まで許す) に一致する
        CK_DATE="$(grep -a '^時試日付 ' "$KLOG" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}')"
        CK_GOT="$(printf '%d' "$CK_DATE" 2>/dev/null)"
        CK_OK=0
        for d in "$(date -u +%Y%m%d)" "$(date -u -v-1d +%Y%m%d 2>/dev/null)" "$(date -u -v+1d +%Y%m%d 2>/dev/null)"; do
            [ -n "$d" ] && [ "$d" = "$CK_GOT" ] && CK_OK=1
        done
        if [ "$CK_OK" -eq 1 ]; then
            pass "kernel qemu: get_tim/get_tod の日付がホストの UTC の日付と一致 (${CK_GOT})"
        else
            fail "kernel qemu: get_tim/get_tod の日付がホストの UTC と一致しない (ゲスト=${CK_GOT:-none} ホスト=$(date -u +%Y%m%d))"
        fi
        # --- #42 G3a: メッセージ (snd_msg / rcv_msg / clr_msg) ---------------------
        MS_N="$(grep -ac '^信試 ' "$KLOG" 2>/dev/null)"
        MS_BAD="$(grep -a '^信試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${MS_N:-0}" -eq 45 ] && [ "${MS_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 メッセージ (FIFO・型選択・NOCLR・clr_msg・ER_*・行程間の待ち合わせ・子の終了通知 MS_EXIT の ${MS_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 メッセージ (項目=${MS_N:-0}/45、失敗=${MS_BAD:-?})"
            grep -a '^信試 ' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # --- #42 G2: 時計の取得系 (get_tim / get_tod) と構造体の複写出 ---------------
        CK_N="$(grep -ac '^時試 ' "$KLOG" 2>/dev/null)"
        CK_BAD="$(grep -a '^時試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${CK_N:-0}" -eq 11 ] && [ "${CK_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 時計 (get_tim・get_tod・暦・閏年・ER_ADR の ${CK_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 時計 (項目=${CK_N:-0}/11、失敗=${CK_BAD:-?})"
            grep -a '^時試 ' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # --- #47 T1: 黄帝紀元の純粋な変換・書式化・解析 ---------------------------
        TN_N="$(grep -ac '^時元試 ' "$KLOG" 2>/dev/null)"
        TN_BAD="$(grep -a '^時元試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${TN_N:-0}" -eq 82 ] && [ "${TN_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: 黄帝紀元の変換・書式化・解析と壁時計 (下限・負の秒・閏年・往復・ER_*・漢令 221〜223・篇時 34 の ${TN_N} 項目)"
        else
            fail "kernel qemu: 黄帝紀元の変換・書式化・解析と壁時計 (項目=${TN_N:-0}/82、失敗=${TN_BAD:-?})"
            grep -a '^時元試 ' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # --- #47 T3: 漢殻命令 時 (現在日時・篇の作時/改時) ------------------------
        if grep -Eq '^時 黄紀 [0-9]+年[0-9][0-9]月[0-9][0-9]日 [0-9][0-9]:[0-9][0-9]:[0-9][0-9] UTC\?? Unix -?[0-9]+ 単調 [0-9]+ ms$' "$KLOG" 2>/dev/null \
           && grep -Eq '^時 史記 作 黄紀 [0-9]+年[0-9][0-9]月[0-9][0-9]日 [0-9][0-9]:[0-9][0-9]:[0-9][0-9] UTC 改 黄紀 ' "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 漢殻命令 時 (現在の黄紀・Unix 秒・単調時計、篇 史記 の作時・改時)"
        else
            fail "kernel qemu: 漢殻命令 時 (現在日時・篇時刻)"
            grep -a '^時 ' "$KLOG" 2>/dev/null | sed 's/^/      /' | head -20
        fi
        # --- #42 G1: グローバル名 (cre_nam / del_nam / get_nam) -------------------
        GN_N="$(grep -ac '^名試 ' "$KLOG" 2>/dev/null)"
        GN_BAD="$(grep -a '^名試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${GN_N:-0}" -eq 21 ] && [ "${GN_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 グローバル名 (作成・取得・変更・強制・削除・ER_*・8文字・16件・DELEXIT の ${GN_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 グローバル名 (項目=${GN_N:-0}/21、失敗=${GN_BAD:-?})"
            grep -a '^名試 ' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        K_UNK="$(grep -ac '殻不明' "$KLOG" 2>/dev/null)"
        K_SERR="$(grep -ac '^殻誤' "$KLOG" 2>/dev/null)"  # 空行・空白だけの行が 殻誤 を出さないこと (他の試験の 3 件だけ)
        if [ "${K_UNK:-0}" -eq 4 ] && [ "${K_SERR:-0}" -eq 3 ]; then
            pass "kernel qemu: 像の無い命令は 殻不明 (怪・存在せず 子・17 バイトの長い名前・終了 の 4 件。空行と空白だけの行は何も出さず、終了 は 終 と取り違えて殻を終えない)"
        else
            fail "kernel qemu: 像の無い命令は 殻不明 (件数=${K_UNK:-0}、期待 4。殻誤=${K_SERR:-0}、期待 3)"
        fi
        # --- 実身・仮身の漢殻の命令 (docs/design-object-model.md V5): 実作・仮置・実削・実目・実名 -------
        OB_LAST="$(LC_ALL=C awk '/^実目 ID=0 /{buf=""} /^実目 /{buf=buf $0 "\n"} END{printf "%s", buf}' "$KLOG" 2>/dev/null)"
        OB_OK=1
        [ "$(grep -ac '^実作 完 ID=[0-9]* 参照=1$' "$KLOG" 2>/dev/null)" -eq 3 ] || OB_OK=0
        [ "$(grep -ac '^実誤 実作 ' "$KLOG" 2>/dev/null)" -eq 3 ] || OB_OK=0
        grep -aq '^仮置 完 参照=2$' "$KLOG" 2>/dev/null || OB_OK=0
        grep -aq '^実目 ID=[0-9]* 参照=2 名=oa$' "$KLOG" 2>/dev/null || OB_OK=0
        grep -aq '^実削 完 外=1 消=0$' "$KLOG" 2>/dev/null || OB_OK=0
        grep -aq '^実名 完=1$' "$KLOG" 2>/dev/null || OB_OK=0
        grep -aq '^実削 完 外=1 消=2$' "$KLOG" 2>/dev/null || OB_OK=0
        printf '%s' "$OB_LAST" | grep -aq '名=abcdefghijklmnopqrst$' || OB_OK=0
        [ "$(printf '%s' "$OB_LAST" | grep -ac '名=ob$\|名=oc$')" -eq 0 ] || OB_OK=0
        [ "$(printf '%s' "$OB_LAST" | grep -ac '名=oa$')" -eq 1 ] || OB_OK=0
        if [ "$OB_OK" -eq 1 ]; then
            pass "kernel qemu: 実身・仮身の漢殻の命令 (実作 3 件と不正な名前 3 件の拒否、仮置で参照数 2、実削は他の仮身が参照していれば実身を残し (消=0)、実名、実削で入れ子の 2 つを消す、実目)"
        else
            fail "kernel qemu: 実身・仮身の漢殻の命令"
            grep -a '^実[作削目名]\|^仮置\|^実誤' "$KLOG" 2>/dev/null | grep -av '^実試' | sed 's/^/      /' | head -30
        fi
        # --- M5/P0: 行程表の統合・行程数 8・頁池の拡大 ---------------------------
        tbl_val() { grep -a "$1 " "$KLOG" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}'; }
        TBL_BAD=""
        for kv in '行程表 項数=8' '行程表 独立=1' '行程表 頁表=1' '行程表 識甲=1' '行程表 識乙=2' '行程表 状空=0'; do
            k="${kv%%=*}"; want="$(printf '0x%016x' "${kv##*=}")"
            got="$(tbl_val "$k")"
            [ "$got" = "$want" ] || TBL_BAD="$TBL_BAD [$k want=$want got=${got:-none}]"
        done
        if [ -z "$TBL_BAD" ]; then
            pass "kernel qemu: 行程表 (8 項が独立・識と状・8 行程分の頁表と動的頁域のブロック写像)"
        else
            fail "kernel qemu: 行程表 (不一致:$TBL_BAD)"
            grep -a '行程表' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # 注: 総数は、この実行で必ず virtio-blk を付けている (vda の環 2 ページが先に使われる) ことを前提にした 30718 (RAM 128 MiB: 動的頁域 120 MiB = 30720 ページ)。
        K_TOTAL="$(tbl_val '頁池 総')"
        if [ "$K_TOTAL" = "$(printf '0x%016x' 30718)" ]; then
            pass "kernel qemu: 頁池 120 MiB (RAM 128 MiB の動的頁域は RAM の終わりまでの 30720 ページ = 空き + 行程の棧 2 ページ × 8 + vda の環 2 ページ。総数は vda の 2 ページを除く)"
        else
            fail "kernel qemu: 頁池 120 MiB (総=${K_TOTAL:-none}、期待 0x77fe)"
            grep -a '頁池' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # --- M5/P0: 柄表・開表 (行程ごとの柄、開くたびに独立した位置) ---------------
        K_IND="$(grep -a '籍独立 ' "$KLOG" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}')"
        K_SEP="$(grep -a '籍別柄 ' "$KLOG" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}')"
        if [ "$K_IND" = "0x0000000000000001" ] && [ "$K_SEP" = "0x0000000000000001" ]; then
            pass "kernel qemu: 柄表・開表 (同じ典籍を 2 回開くと別の柄で、位置が独立)"
        else
            fail "kernel qemu: 柄表・開表 (独立=${K_IND:-none} 別柄=${K_SEP:-none})"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -40
        fi
        K_BUSY="$(grep -a '籍削忙 ' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}' | paste -sd' ' -)"
        if [ "$K_BUSY" = "0xfffffffffffffff0 0xfffffffffffffff0" ]; then
            pass "kernel qemu: 開かれている間は 削 が -EBUSY (開数。2 本のうち 1 本を閉じてもまだ -EBUSY)"
        else
            fail "kernel qemu: 開かれている間は 削 が -EBUSY (got '${K_BUSY:-none}')"
            grep -a '籍削忙' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        K_FULL="$(grep -a '籍満 ' "$KLOG" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}')"
        K_REOPEN="$(grep -a '籍再開 ' "$KLOG" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}')"
        K_DEVCLOSE="$(grep -a '籍盤閉 ' "$KLOG" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}')"
        if [ "$K_FULL" = "0xffffffffffffffe8" ] && [ "$K_REOPEN" = "0x0000000000000003" ] \
           && [ "$K_DEVCLOSE" = "0xfffffffffffffff7" ]; then
            pass "kernel qemu: 柄表の満杯 (-EMFILE)、閉じて再び開ける、盤の柄は閉じられない (-EBADF)"
        else
            fail "kernel qemu: 柄表の満杯 (満杯=${K_FULL:-none} 再開=${K_REOPEN:-none} 盤閉=${K_DEVCLOSE:-none})"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -40
        fi
        KSEQ="$(grep -oE '甲書|乙書|甲讀|乙讀' "$KLOG" 2>/dev/null | paste -sd' ' -)"
        if [ "$KSEQ" = "甲書 乙書 甲讀 乙讀" ]; then
            pass "kernel qemu: 譲渡によるラウンドロビン切替"
        else
            fail "kernel qemu: 譲渡によるラウンドロビン切替 (got '${KSEQ:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        # --- M3 software: タイマーによるプリエンプション (非協調切替) ----------
        K_PRE="$(grep -oE '甲忙始|乙起|甲忙終|甲醒|乙忙終' "$KLOG" 2>/dev/null | paste -sd' ' -)"
        if [ "$K_PRE" = "甲忙始 乙起 甲忙終 甲醒 乙忙終" ]; then
            pass "kernel qemu: タイマー横取り (甲が回転中に 乙 が割込実行、甲が復歸)"
        else
            fail "kernel qemu: タイマー横取り (got '${K_PRE:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        # --- M3 software: 待機・起床 (sleep/wake) ------------------------------
        K_SL1="$(grep -oE '甲忙終0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_SL2="$(grep -oE '甲醒 0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        K_SL3="$(grep -oE '乙忙終0x[0-9a-f]{16}' "$KLOG" 2>/dev/null | grep -oE '0x[0-9a-f]{16}')"
        if [ -n "$K_SL1" ] && [ -n "$K_SL2" ] && [ -n "$K_SL3" ] && \
           [ $((K_SL1)) -lt $((K_SL2)) ] && [ $((K_SL2)) -lt $((K_SL3)) ]; then
            pass "kernel qemu: 待機と起床 (甲が眠り乙が回転中に甲が起床: 甲忙終='${K_SL1}' < 甲醒='${K_SL2}' < 乙忙終='${K_SL3}')"
        else
            fail "kernel qemu: 待機と起床 (甲忙終='${K_SL1:-none}' 甲醒='${K_SL2:-none}' 乙忙終='${K_SL3:-none}')"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        K_BOOT="$(grep -ac "殻起動" "$KLOG" 2>/dev/null)"
        if grep -q "民務終了 行程=0x0000000000000000" "$KLOG" 2>/dev/null && \
           ! grep -q "民務終了 行程=0x0000000000000001" "$KLOG" 2>/dev/null && \
           [ "${K_BOOT:-0}" -ge 2 ] && grep -q "殻響:再起" "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 甲は 終行程 で終了し、殻行程 (乙) は 終 のあと殻を再起動 (殻起動 ${K_BOOT} 回)"
        else
            fail "kernel qemu: 甲は 終行程 で終了し、殻行程 (乙) は 終 のあと殻を再起動 (殻起動 ${K_BOOT:-0} 回)"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        # --- 篇藏の永続化 (docs/design-persistence.md): 書いて 篇同 → 再起動 → 読める。壊れたスロットは使わない -------
        # 同じディスクイメージ (16754 区画以上。20000 区画) で 5 回起動し、そのたびに殻へ命令を流して 殻終 を待つ。
        PERSIST_IMG="$OUT/persist.img"
        PERSIST_PIPE="$OUT/persist_serial"
        dd if=/dev/zero of="$PERSIST_IMG" bs=512 count=20000 2>/dev/null
        pian_boot() {  # $1 = ログ、$2 = 殻に流す命令 (改行区切り)、$3 = (省略可) 命令の代わりに流すファイル (生のバイトを含む入力用)
            local plog="$1" pcmds="$2" pfile="${3:-}" pq pc pf
            rm -f "$PERSIST_PIPE.in" "$PERSIST_PIPE.out" "$plog"
            mkfifo "$PERSIST_PIPE.in" "$PERSIST_PIPE.out"
            cat "$PERSIST_PIPE.out" > "$plog" &
            pc=$!
            qemu-system-aarch64 -M virt,gic-version=2 -cpu cortex-a57 -nographic \
                -global virtio-mmio.force-legacy=false \
                -drive file="$PERSIST_IMG",if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 \
                -serial "pipe:$PERSIST_PIPE" -kernel "$OUT/kernel.elf" \
                >"$OUT/persist_qemu.console.log" 2>&1 &
            pq=$!
            ( printf 'KANBUN\n' > "$PERSIST_PIPE.in"
              for _ in $(seq 1 60); do grep -q "甲得" "$plog" 2>/dev/null && break; sleep 0.25; done
              if [ -n "$pfile" ]; then cat "$pfile" > "$PERSIST_PIPE.in"; else printf '%s' "$pcmds" > "$PERSIST_PIPE.in"; fi ) &
            pf=$!
            for _ in $(seq 1 "${PIAN_TRIES:-80}"); do
                grep -q "殻終\|核恐慌" "$plog" 2>/dev/null && break
                sleep 0.5
            done
            kill "$pq" 2>/dev/null
            wait "$pq" 2>/dev/null
            wait "$pc" 2>/dev/null
            kill "$pf" 2>/dev/null
            wait "$pf" 2>/dev/null
        }
        persist_ok() {  # $1 = ログ、$2 = 「永試 」の後の目印。その行が成功 (…01) か
            grep -a "^永試 $2" "$1" 2>/dev/null | grep -q '0x0000000000000001$'
        }
        pian_boot "$OUT/persist1.log" $'永試 F\n永試 W\n終\n'
        P1_HDR="$(od -An -v -tx1 -j 32768 -N 4 "$PERSIST_IMG" | tr -s ' ' | sed 's/^ //; s/ $//')"
        P1_VER="$(od -An -v -tu4 -j 32772 -N 4 "$PERSIST_IMG" | tr -s ' ' | sed 's/^ //; s/ $//')"
        P1_TM_W="$(grep -a '^永試 時作 ' "$OUT/persist1.log" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}')"
        if persist_ok "$OUT/persist1.log" 'F:' && persist_ok "$OUT/persist1.log" 'F録:' && persist_ok "$OUT/persist1.log" 'W標:' && persist_ok "$OUT/persist1.log" 'W大:' && persist_ok "$OUT/persist1.log" 'W:' && [ "$P1_HDR" = "50 49 41 4e" ] && [ "$P1_VER" = "6" ]; then
            pass "kernel qemu: 録層に 13 バイトと 6000 バイト (2 頁) のファイルを作り、篇同 で篇藏と録層の状態がスロット A のヘッダ (PIAN・版 6) としてディスクに届く"
        else
            fail "kernel qemu: 篇同 の書込み (ヘッダ='$P1_HDR' 版='$P1_VER')"
            grep -a '永試' "$OUT/persist1.log" 2>/dev/null | sed 's/^/      /' | head -8
        fi
        pian_boot "$OUT/persist2.log" $'永試 R\n永試 S\n永試 T\n永試 V\n永試 G\n永試 O\n終\n'
        P2_HDR="$(od -An -v -tx1 -j 4305408 -N 4 "$PERSIST_IMG" | tr -s ' ' | sed 's/^ //; s/ $//')"
        P2_TM_W="$(grep -a '^永試 時作 ' "$OUT/persist2.log" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}')"
        P2_TM_C="$(grep -a '^永試 時改 ' "$OUT/persist2.log" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}')"
        if persist_ok "$OUT/persist2.log" 'R:' && persist_ok "$OUT/persist2.log" 'S:' && persist_ok "$OUT/persist2.log" 'T:' && persist_ok "$OUT/persist2.log" 'V:' && grep -aq '篇戻 世代=0x0000000000000001' "$OUT/persist2.log" && persist_ok "$OUT/persist2.log" 'G:' && persist_ok "$OUT/persist2.log" 'O:' && [ "$P2_HDR" = "50 49 41 4e" ] && [ -n "$P1_TM_W" ] && [ "$P1_TM_W" = "$P2_TM_W" ] && [ -n "$P2_TM_C" ]; then
            pass "kernel qemu: 再起動のあとスロット A (世代 1) から戻り、篇藏の内容・録層の 2 つのファイル・篇「永」の作時を読める。戻したあとに作った録層のファイルは新しい ID になる。開いたままの 篇同 はスロット B (世代 2) へ"
        else
            fail "kernel qemu: 再起動後の読み戻しとスロット B への書込み (ヘッダ='$P2_HDR' 作時='$P1_TM_W'/'$P2_TM_W')"
            grep -a '永試\|篇戻' "$OUT/persist2.log" 2>/dev/null | sed 's/^/      /' | head -10
        fi
        pian_boot "$OUT/persist3.log" $'永試 R\n永試 H\n永試 D\n同\n問安 日月\n終\n'
        P3_TM_W="$(grep -a '^永試 時作 ' "$OUT/persist3.log" 2>/dev/null | head -1 | grep -oE '0x[0-9a-f]{16}')"
        if persist_ok "$OUT/persist3.log" 'R:' && persist_ok "$OUT/persist3.log" 'H:' && grep -aq '^子行程起動 日月' "$OUT/persist3.log" && grep -aq '篇戻 世代=0x0000000000000002' "$OUT/persist3.log" && persist_ok "$OUT/persist3.log" 'D:' && grep -aq '殻同 保存した' "$OUT/persist3.log" && [ -n "$P3_TM_W" ] && [ "$P1_TM_W" = "$P3_TM_W" ]; then
            pass "kernel qemu: 世代 2 (スロット B) から戻り、開いたまま保存した篇も削れる (開数は保存した値が残らない)。篇「永」の作時も保たれる。戻したあとに作った録層のファイルも戻る。殻の 同 で世代 3 をスロット A へ保存でき、戻したあとも漢像 (問安) を起動できる"
        else
            fail "kernel qemu: 世代 2 の読み戻しと開数 (作時='$P1_TM_W'/'$P3_TM_W')"
            grep -a '永試\|篇戻' "$OUT/persist3.log" 2>/dev/null | sed 's/^/      /' | head -10
        fi
        # 最新 (世代 3) のスロット A のヘッダは無傷のまま、篇の本文の区画 1 つ (最初に頁を持つ篇の最初の区画。録層のファイルの本体も篇の本文) を壊す
        # → データのチェックサムが合わず、世代 2 のスロット B から戻る (録層の区画の破損も検出する)
        printf '\377\377\377\377' | dd of="$PERSIST_IMG" bs=1 seek=$((129 * 512)) conv=notrunc 2>/dev/null
        pian_boot "$OUT/persist4.log" $'永試 R\n永試 H\n終\n'
        if persist_ok "$OUT/persist4.log" 'R:' && persist_ok "$OUT/persist4.log" 'H:' && grep -aq '篇戻 世代=0x0000000000000002' "$OUT/persist4.log"; then
            pass "kernel qemu: ヘッダが無傷でも本文の区画が壊れた最新のスロット A は使わず、世代 2 のスロット B から戻る (データのチェックサム)"
        else
            fail "kernel qemu: 壊れた録層の区画を持つスロットを避けて戻れない"
            grep -a '永試\|篇戻' "$OUT/persist4.log" 2>/dev/null | sed 's/^/      /' | head -6
        fi
        # スロット A のヘッダと、スロット B の篇の表の区画 (スロット先頭の 2 区画目) も壊す → どちらも使えず、初期化した状態で起動する
        dd if=/dev/zero of="$PERSIST_IMG" bs=512 seek=64 count=1 conv=notrunc 2>/dev/null
        printf '\377\377\377\377' | dd of="$PERSIST_IMG" bs=1 seek=$((8410 * 512)) conv=notrunc 2>/dev/null
        # --- 競合のストレス: 5 つの子が同時に篇藏 (作成・書込・標・索・読戻・削除) を 40 回ずつ使う。タイマーの横取りの中でも食い違いと頁の漏れが無い ----
        pian_boot "$OUT/stress.log" $'競試\n終\n'
        if grep -aq '^競試 失敗数 0x0000000000000000' "$OUT/stress.log" && grep -aq '^競試 頁差 0x0000000000000000' "$OUT/stress.log" \
           && grep -aq '^競試 合格 0x0000000000000001' "$OUT/stress.log"; then
            pass "kernel qemu: 競合のストレス (5 行程 × 40 回 × 2 巡の作成・書込・標・索・読戻・削除が全て一致し、2 巡目の前後で頁が漏れない)"
        else
            fail "kernel qemu: 競合のストレス"
            grep -a '^競試\|^殻' "$OUT/stress.log" 2>/dev/null | cut -c1-80 | sed 's/^/      /' | tail -12
        fi
        # --- セルフホスト: OS の上で動く機械漢文の字句解析器 (字句) が、C++ 版 -tokens と同じトークン列を出す ----
        SH_SRC='常「引五」之有符六四 為 負 5 註 x'
        printf '%s' "$SH_SRC" >"$OUT/selfhost_os_src.mkn"
        "$BIN" "$OUT/selfhost_os_src.mkn" -tokens >"$OUT/selfhost_os_ref.txt" 2>/dev/null
        pian_boot "$OUT/selfhost_os.log" $'書 源 '"$SH_SRC"$'\n字句 源\n終\n'
        sed -n '/^殻> 字句 源/,/^殻> 終/p' "$OUT/selfhost_os.log" | grep -aE '^[0-9]+:[0-9]+ ' >"$OUT/selfhost_os_got.txt"
        if [ -s "$OUT/selfhost_os_ref.txt" ] && cmp -s "$OUT/selfhost_os_ref.txt" "$OUT/selfhost_os_got.txt"; then
            pass "selfhost: OS の上で動く機械漢文の字句解析器 (字句) が C++ 版 -tokens と同じトークン列を出す ($(wc -l <"$OUT/selfhost_os_ref.txt" | tr -d ' ') 行)"
        else
            fail "selfhost: OS 上の字句解析器の出力が C++ 版と違う"
            diff "$OUT/selfhost_os_ref.txt" "$OUT/selfhost_os_got.txt" 2>&1 | head -8 | sed 's/^/      /'
            grep -a '字句' "$OUT/selfhost_os.log" | head -3 | sed 's/^/      /'
        fi
        # --- セルフホスト: OS の上で動く機械漢文の構文解析器 (構文) が、C++ 版 -ast と同じ AST を出す ----
        SA_SRC='術曰「試」 受「値」之無符六四 返 無符六四 設「和」之無符六四 為 (値 加 1) 乘 2 若 和 大於 3 則 歸 和 終若 歸 0 終術'
        printf '%s' "$SA_SRC" >"$OUT/selfhost_os_ast_src.mkn"
        "$BIN" "$OUT/selfhost_os_ast_src.mkn" -ast >"$OUT/selfhost_os_ast_ref.txt" 2>/dev/null
        pian_boot "$OUT/selfhost_os_ast.log" $'書 源 '"$SA_SRC"$'\n構文 源\n終\n'
        sed -n '/^殻> 構文 源/,/^殻> 終/p' "$OUT/selfhost_os_ast.log" | sed '1d;$d' | grep -av '^頁供' | grep -av '^殻碼' >"$OUT/selfhost_os_ast_got.txt"
        if [ -s "$OUT/selfhost_os_ast_ref.txt" ] && cmp -s "$OUT/selfhost_os_ast_ref.txt" "$OUT/selfhost_os_ast_got.txt"; then
            pass "selfhost: OS の上で動く機械漢文の構文解析器 (構文) が C++ 版 -ast と同じ AST を出す ($(wc -l <"$OUT/selfhost_os_ast_ref.txt" | tr -d ' ') 行)"
        else
            fail "selfhost: OS 上の構文解析器の出力が C++ 版と違う"
            diff "$OUT/selfhost_os_ast_ref.txt" "$OUT/selfhost_os_ast_got.txt" 2>&1 | head -8 | sed 's/^/      /'
            grep -a '構文' "$OUT/selfhost_os_ast.log" | head -3 | sed 's/^/      /'
        fi
        # --- セルフホスト: OS の上で動く機械漢文の型検査器 (型検) が、C++ 版 -check と同じ診断を出す ----
        ST_SRC='術曰「試」 受「値」之無符六四 返 無符六四 設「和」之真偽 為 値 加 1 歸 和 終術'
        printf '%s' "$ST_SRC" >"$OUT/selfhost_os_tc_src.mkn"
        "$BIN" "$OUT/selfhost_os_tc_src.mkn" -check 2>"$OUT/selfhost_os_tc_ref.txt" >/dev/null
        pian_boot "$OUT/selfhost_os_tc.log" $'書 源 '"$ST_SRC"$'\n型検 源\n終\n'
        sed -n '/^殻> 型検 源/,/^殻> 終/p' "$OUT/selfhost_os_tc.log" | grep -a '^錯 ' >"$OUT/selfhost_os_tc_got.txt"
        if [ -s "$OUT/selfhost_os_tc_ref.txt" ] && cmp -s "$OUT/selfhost_os_tc_ref.txt" "$OUT/selfhost_os_tc_got.txt"; then
            pass "selfhost: OS の上で動く機械漢文の型検査器 (型検) が C++ 版 -check と同じ診断を出す ($(wc -l <"$OUT/selfhost_os_tc_ref.txt" | tr -d ' ') 件)"
        else
            fail "selfhost: OS 上の型検査器の出力が C++ 版と違う"
            diff "$OUT/selfhost_os_tc_ref.txt" "$OUT/selfhost_os_tc_got.txt" 2>&1 | head -8 | sed 's/^/      /'
            grep -a '型検' "$OUT/selfhost_os_tc.log" | head -3 | sed 's/^/      /'
        fi
        # --- セルフホスト: OS の上で動く機械漢文のコンパイラ (機譯) が、C++ 版 -ir と同じ IR を出す ----
        SC_SRC='術曰「試」 受「値」之無符六四 返 無符六四 設「和」之無符六四 為 (値 加 1) 乘 2 若 和 大於 3 則 歸 和 終若 歸 0 終術'
        printf '%s' "$SC_SRC" >"$OUT/selfhost_os_cc_src.mkn"
        "$BIN" "$OUT/selfhost_os_cc_src.mkn" -ir -o "$OUT/selfhost_os_cc_ref.ll" 2>/dev/null
        pian_boot "$OUT/selfhost_os_cc.log" $'書 源 '"$SC_SRC"$'\n機譯 源\n終\n'
        sed -n '/^殻> 機譯 源/,/^殻> 終/p' "$OUT/selfhost_os_cc.log" | sed '1d;$d' | grep -av '^頁供' | grep -av '^殻碼' >"$OUT/selfhost_os_cc_got.ll"
        if [ -s "$OUT/selfhost_os_cc_ref.ll" ] && cmp -s "$OUT/selfhost_os_cc_ref.ll" "$OUT/selfhost_os_cc_got.ll"; then
            pass "selfhost: OS の上で動く機械漢文のコンパイラ (機譯) が C++ 版 -ir と同じ IR を出す ($(wc -l <"$OUT/selfhost_os_cc_ref.ll" | tr -d ' ') 行)"
        else
            fail "selfhost: OS 上のコンパイラの IR が C++ 版と違う"
            diff "$OUT/selfhost_os_cc_ref.ll" "$OUT/selfhost_os_cc_got.ll" 2>&1 | head -8 | sed 's/^/      /'
            grep -a '機譯' "$OUT/selfhost_os_cc.log" | head -3 | sed 's/^/      /'
        fi
        # --- 広域 (漢令 123): 民の窓 (2 MiB) に収まらない作業域が要る大きなソースを OS の上で IR にする ----
        #     関数 1200 個・約 220 KB を 4 つの篇 (部0〜部3。1 つの篇は 64 KiB まで) に作り、根の篇の「註 @取込」で束ねる。作業域は約 5 MiB。
        python3 -I - "$OUT/selfhost_os_big.mkn" 4 300 <<'PYEOF'
import sys
out, parts, per = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(out, 'w', encoding='utf-8') as f:
    for i in range(parts * per):
        f.write("術曰「f%d」 受「値」之無符六四 返 無符六四\n    設「和」之無符六四 為 (値 加 %d) 乘 2\n    若 和 大於 3 則\n        歸 和\n    終若\n    歸 0\n終術\n" % (i, i))
PYEOF
        "$BIN" "$OUT/selfhost_os_big.mkn" -ir -o "$OUT/selfhost_os_big.ll" 2>/dev/null
        BIG_EXPECT="$(python3 -I - "$OUT/selfhost_os_big.ll" "$OUT/selfhost_os_big.mkn" <<'PYEOF'
import sys
d = open(sys.argv[1], 'rb').read()
h = 0xcbf29ce484222325
for b in d:
    h = ((h ^ b) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
print("%d 0x%016x %d" % (len(d), h, len(open(sys.argv[2], 'rb').read())))
PYEOF
)"
        BIG_LEN="${BIG_EXPECT%% *}"; BIG_REST="${BIG_EXPECT#* }"; BIG_HASH="${BIG_REST%% *}"; BIG_SRC="${BIG_REST#* }"
        PIAN_TRIES=2400 pian_boot "$OUT/selfhost_os_big.log" $'源増 部0 300 0\n源増 部1 300 300\n源増 部2 300 600\n源増 部3 300 900\n源増 b 天地/典/大根 4\n機譯 -s 天地/典/大根\n書 小 術曰「甲」 返 無 終術\n機譯 -s 小\n機譯 -s 小\n機譯 -s 小\n終\n'
        if grep -aq "^機譯 長 0x0*$(printf '%x' "$BIG_LEN")\$" "$OUT/selfhost_os_big.log" \
           && grep -aq "^ 雑 0x0*${BIG_HASH#0x}\$" "$OUT/selfhost_os_big.log" \
           && [ "$(grep -ac '^機譯 長 0x0*[0-9a-f]*$' "$OUT/selfhost_os_big.log")" -ge 4 ]; then
            pass "selfhost: 広域 (漢令 123) で民の窓に収まらない作業域を取り、OS の上のコンパイラ (機譯) が 4 つの篇に分けた ${BIG_SRC} バイトのソースを取込で束ねて ${BIG_LEN} バイトの IR にし、C++ 版と同じ雑値になる。行程の終了で広域は頁池へ戻り、続けて 3 回取り直せる"
        else
            fail "selfhost: OS 上で大きなソースの IR が C++ 版と違う、または作れない (期待: 源 ${BIG_SRC} 長 ${BIG_LEN} 雑 ${BIG_HASH})"
            grep -a '源増\|機譯\|殻誤\|核恐慌' "$OUT/selfhost_os_big.log" | head -8 | sed 's/^/      /'
        fi
        # --- 核そのものを OS の上で IR にする (セルフホストの総仕上げ): 核の展開後のソース 796 KB をコンソール経由で 13 個ほどの篇へ受け、取込で束ねて 機譯 にかける ----
        #     時間がかかる (QEMU の TCG 上で数分) ので、KERNEL_SELFBUILD=0 で省ける。
        if [ "${KERNEL_SELFBUILD:-1}" = "1" ]; then
            sh tools/kernel-expand.sh kernel/kernel.mkn "$OUT/selfhost_kernel_all.mkn" >/dev/null 2>&1
            "$BIN" "$OUT/selfhost_kernel_all.mkn" -ir -o "$OUT/selfhost_kernel_ref.ll" 2>/dev/null
            python3 -I - "$OUT/selfhost_kernel_all.mkn" "$OUT/selfhost_kernel_ref.ll" "$OUT/selfhost_kernel_stream.bin" <<'PYEOF' >"$OUT/selfhost_kernel_expect.txt"
import sys
src = open(sys.argv[1], 'rb').read()
ir = open(sys.argv[2], 'rb').read()
h = 0xcbf29ce484222325
for b in ir:
    h = ((h ^ b) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
# 行の境界で 60000 バイト以下に分ける (篇の本文は 64 KiB まで)
parts, cur = [], b''
for line in src.splitlines(keepends=True):
    if len(cur) + len(line) > 60000:
        parts.append(cur); cur = b''
    cur += line
parts.append(cur)
out = b''
for i, p in enumerate(parts):
    out += ('源受 部%d %d\n' % (i, len(p))).encode('utf-8') + p
out += ('源増 b 天地/典/核根 %d\n機譯 -s 天地/典/核根\n終\n' % len(parts)).encode('utf-8')
open(sys.argv[3], 'wb').write(out)
print(len(ir), '0x%016x' % h, len(src), len(parts))
PYEOF
            read -r KS_LEN KS_HASH KS_SRC KS_PARTS <"$OUT/selfhost_kernel_expect.txt"
            PIAN_TRIES="${KERNEL_SELFBUILD_TRIES:-3600}" pian_boot "$OUT/selfhost_kernel.log" "" "$OUT/selfhost_kernel_stream.bin"
            if grep -aq "^機譯 長 0x0*$(printf '%x' "$KS_LEN")\$" "$OUT/selfhost_kernel.log" \
               && grep -aq "^ 雑 0x0*${KS_HASH#0x}\$" "$OUT/selfhost_kernel.log"; then
                pass "selfhost: 核そのもの (展開後 ${KS_SRC} バイト) を OS の上で IR にする: コンソールから ${KS_PARTS} 個の篇へ受け、取込で束ねた 機譯 が ${KS_LEN} バイトの IR を C++ 版と同じ雑値で作る"
            else
                fail "selfhost: OS 上で核を IR にできない、または C++ 版と違う (期待: 長 ${KS_LEN} 雑 ${KS_HASH})"
                grep -a '源受\|源増\|機譯\|殻誤\|核恐慌' "$OUT/selfhost_kernel.log" | head -8 | sed 's/^/      /'
            fi
        fi
        pian_boot "$OUT/panic1.log" $'異常試 k\n問安\n終\n'
        if grep -aq '^核恐慌 init終了' "$OUT/panic1.log" && ! grep -aq '殻終' "$OUT/panic1.log" \
           && [ "$(grep -ac '問安' "$OUT/panic1.log")" -le 1 ]; then
            pass "kernel qemu: init (殻行程) の終了で 核恐慌 init終了 を出して止まる (以後の命令は実行されない)"
        else
            fail "kernel qemu: init 終了の panic"
            tail -5 "$OUT/panic1.log" 2>/dev/null | sed 's/^/      /'
        fi
        # --- 漢殻の受入試験: 起動 → 診断 (助・在・目) → 異常な子 (保護違反・BRK) → 未知の命令・異常に長い行 → 殻が生きていて 終 で閉じる ----
        pian_boot "$OUT/accept1.log" $'響 開始\n助\n在\n目\n標 天地/典/史記 色 青\n標 天地/典/史記 色\n索 天地/典 色\n索 天地/典 色 赤\n標 天地/典/史記 色 -\n標 天地/典/史記 色\n索 天地/典 色\n異常試 w\n響 保護違反の後\n異常試 b\n響 BRKの後\n未知命令\n'"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"$'\n響 長い行の後\n異常試\n響 正常の後\n終\n'
        sed -n '/^殻響:開始/,$p' "$OUT/accept1.log" >"$OUT/accept1.session.log"  # 核の自己試験の出力を除き、この試験の入力以降だけを見る
        ACC="$OUT/accept1.session.log"
        acc_line() { grep -an "$1" "$ACC" 2>/dev/null | head -1 | cut -d: -f1; }
        if [ -n "$(grep -ac '^殻起動' "$OUT/accept1.log")" ] && [ -n "$(acc_line '殻響:開始')" ] && [ -n "$(acc_line '^殻命令一覧')" ] \
           && [ -n "$(acc_line '標 完')" ] && [ -n "$(acc_line '標 値:青')" ] && [ -n "$(acc_line '索:天地/典/史記')" ] \
           && [ "$(grep -ac '^索:' "$ACC")" -eq 1 ] && [ "$(grep -ac '^索件 0x0000000000000000' "$ACC")" -eq 2 ] \
           && [ "$(grep -ac '^標誤 0xfffffffffffffffe' "$ACC")" -eq 1 ] && [ "$(grep -ac '^標誤 ' "$ACC")" -eq 1 ] \
           && [ -n "$(acc_line '殻在:天地/典')" ] && [ -n "$(acc_line '^殻目:')" ] \
           && [ "$(grep -ac '^異常試 開始' "$ACC")" -eq 3 ] \
           && grep -aq '殻碼 0x00000000000000a4' "$ACC" && grep -aq '殻碼 0x00000000000000bc' "$ACC" \
           && [ "$(grep -ac '^殻碼 ' "$ACC")" -eq 4 ] \
           && [ "$(acc_line '殻響:保護違反の後')" -gt "$(acc_line '殻碼 0x00000000000000a4')" ] \
           && [ "$(acc_line '殻響:BRKの後')" -gt "$(acc_line '殻碼 0x00000000000000bc')" ] \
           && [ -n "$(acc_line '殻響:長い行の後')" ] && [ -n "$(acc_line '殻響:正常の後')" ] \
           && [ "$(grep -ac '^殻不明' "$ACC")" -ge 2 ] \
           && [ -n "$(acc_line '^殻終')" ] && ! grep -aq '核恐慌\|異常 ESR=.*殻' "$ACC"; then
            pass "kernel qemu: 漢殻の受入 (起動・助/在/目の診断・保護違反と BRK の子を殻が回収して続行・未知の命令と 400 字の行に耐え・終で閉じる)"
        else
            fail "kernel qemu: 漢殻の受入試験"
            grep -a '^殻\|^異常' "$ACC" 2>/dev/null | cut -c1-80 | sed 's/^/      /' | head -30
        fi
        pian_boot "$OUT/persist5.log" $'永試 N\n永試 M\n終\n'
        if persist_ok "$OUT/persist5.log" 'N:' && persist_ok "$OUT/persist5.log" 'M:' && ! grep -aq '篇戻' "$OUT/persist5.log"; then
            pass "kernel qemu: どのスロットも使えないときは初期化した状態で起動する (篇「永」も録層の pmem も無い)"
        else
            fail "kernel qemu: 両スロットが使えないときの起動"
            grep -a '永試\|篇戻' "$OUT/persist5.log" 2>/dev/null | sed 's/^/      /' | head -6
        fi
        # --- Devicetree: x0 の DTB を解析して機器表を作る。RAM を 64 MiB に減らすと量が追従し、16 MiB では核が診断して止まる ----
        fdt_boot() {  # $1 = ログ、$2 = QEMU の追加引数 (-m など)
            rm -f "$1"
            qemu-system-aarch64 -M virt,gic-version=2 -cpu cortex-a57 -nographic $2 \
                -global virtio-mmio.force-legacy=false \
                -serial "file:$1" -kernel "$OUT/kernel.elf" >"$OUT/fdt_qemu.console.log" 2>&1 &
            local fq=$!
            for _ in $(seq 1 40); do
                grep -aq '頁割当\|核恐慌' "$1" 2>/dev/null && break
                sleep 0.25
            done
            kill "$fq" 2>/dev/null
            wait "$fq" 2>/dev/null
        }
        fdt_boot "$OUT/fdt128.log" "-m 128M"
        fdt_boot "$OUT/fdt64.log" "-m 64M"
        fdt_boot "$OUT/fdt16.log" "-m 16M"
        fdt_boot "$OUT/fdt32.log" "-m 32M"
        fdt_boot "$OUT/fdt24.log" "-m 24M"
        fdt_boot "$OUT/fdtel2.log" "-machine virtualization=on"
        if grep -aq '^樹 有効 0x0000000000000001' "$OUT/fdt128.log" \
           && grep -aq '^樹 記憶基 0x0000000040000000' "$OUT/fdt128.log" \
           && grep -aq '^樹 記憶量 0x0000000008000000' "$OUT/fdt128.log" \
           && grep -aq '^樹 串口 0x0000000009000000' "$OUT/fdt128.log" \
           && grep -aq '^樹 割配 0x0000000008000000' "$OUT/fdt128.log" \
           && grep -aq '^樹 時計 0x0000000009010000' "$OUT/fdt128.log" \
           && grep -aq '^樹 盤 0x000000000a000000' "$OUT/fdt128.log" \
           && grep -aq '^樹 記憶量 0x0000000004000000' "$OUT/fdt64.log" && grep -aq '日誌' "$OUT/fdt64.log" \
           && grep -aq '^樹 割込 0x000000000000001e' "$OUT/fdt128.log" && grep -aq '^樹 盤数 0x0000000000000020' "$OUT/fdt128.log" && grep -aq '^樹 盤幅 0x0000000000000200' "$OUT/fdt128.log" \
           && grep -aq '^樹 頁数 0x0000000000007800' "$OUT/fdt128.log" && grep -aq '^樹 頁末 0x0000000048000000' "$OUT/fdt128.log" \
           && grep -aq '^樹 頁数 0x0000000000003800' "$OUT/fdt64.log" \
           && grep -aq '^樹 頁数 0x0000000000001800' "$OUT/fdt32.log" && grep -aq '頁割当' "$OUT/fdt32.log" \
           && grep -aq '^樹 頁数 0x0000000000001000' "$OUT/fdt24.log" && grep -aq '頁割当' "$OUT/fdt24.log" \
           && grep -aq '^樹 EL 0x0000000000000001' "$OUT/fdt128.log" \
           && grep -aq '^樹 EL 0x0000000000000001' "$OUT/fdtel2.log" && grep -aq '記憶管理有効' "$OUT/fdtel2.log" && grep -aq '^樹 有効 0x0000000000000001' "$OUT/fdtel2.log" \
           && grep -aq '^核恐慌 記憶不足' "$OUT/fdt16.log" && ! grep -aq '記憶管理有効' "$OUT/fdt16.log"; then
            pass "kernel qemu: Devicetree を解析して RAM・UART・GIC・RTC・virtio の基底番地を得る (RAM 128・64・32・24 MiB で動的頁域が 30720・14336・6144・4096 ページに追従して起動し、16 MiB では 核恐慌 記憶不足。EL2 で始まる起動 (virtualization=on) も EL1 へ降りて同じに起動する)"
        else
            fail "kernel qemu: Devicetree の解析"
            grep -a '^樹\|^核恐慌' "$OUT/fdt128.log" "$OUT/fdt64.log" "$OUT/fdt16.log" 2>/dev/null | sed 's/^/      /' | head -20
        fi
        # --- 差分書き込み: 塊 (4 KiB) ごとのハッシュで、変わった塊だけを書く。書いたスロットから再起動で戻れる ----
        pian_boot "$OUT/diff1.log" $'永試 Y\n終\n'
        pian_boot "$OUT/diff2.log" $'永試 Z\n終\n'
        if persist_ok "$OUT/diff1.log" 'Y:' && persist_ok "$OUT/diff2.log" 'Z:' && grep -aq '篇戻 世代=' "$OUT/diff2.log"; then
            pass "kernel qemu: 差分書き込み (初回は全塊、同じ状態の 3 回目は 0 塊、篇を 1 つ足した 4 回目は 8 塊以下。書いたスロットから再起動で戻る)"
        else
            fail "kernel qemu: 差分書き込み"
            grep -a '永試\|篇戻' "$OUT/diff1.log" "$OUT/diff2.log" 2>/dev/null | cut -c1-120 | sed 's/^/      /' | head -10
        fi
        # --- 独立ブートローダー: 導 が virtio-blk の核イメージ (KBL1) を読んで、DTB を避難させ、核へ移譲する ----------
        loader_boot() {  # $1 = ログ、$2 = 追加の QEMU 引数 (機械 -machine など)、$3 = ディスクイメージ ("" なら装置なし)
            rm -f "$1"
            if [ -n "$3" ]; then
                qemu-system-aarch64 -M virt,gic-version=2 -cpu cortex-a57 -nographic $2 \
                    -global virtio-mmio.force-legacy=false \
                    -drive file="$3",if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 \
                    -serial "file:$1" -kernel "$OUT/loader.elf" >"$OUT/loader_qemu.console.log" 2>&1 &
            else
                qemu-system-aarch64 -M virt,gic-version=2 -cpu cortex-a57 -nographic $2 \
                    -global virtio-mmio.force-legacy=false \
                    -serial "file:$1" -kernel "$OUT/loader.elf" >"$OUT/loader_qemu.console.log" 2>&1 &
            fi
            local lq=$!
            for _ in $(seq 1 60); do
                grep -aq '記憶管理有効\|導誤' "$1" 2>/dev/null && break
                sleep 0.25
            done
            kill "$lq" 2>/dev/null
            wait "$lq" 2>/dev/null
        }
        loader_boot "$OUT/loader1.log" "" "$OUT/kernel.img"
        loader_boot "$OUT/loader2.log" "-machine virtualization=on" "$OUT/kernel.img"
        dd if=/dev/zero of="$OUT/loader_zero.img" bs=512 count=8 2>/dev/null
        loader_boot "$OUT/loader3.log" "" "$OUT/loader_zero.img"
        loader_boot "$OUT/loader4.log" "" ""
        LD_OK=1
        for lg in loader1 loader2; do
            grep -aq '^導 開始' "$OUT/$lg.log" && grep -aq '^導 DTB 0x0000000040000000' "$OUT/$lg.log" \
                && [ "$(grep -ac '^導 段 ' "$OUT/$lg.log")" -ge 1 ] && grep -aq '^導 移譲 0x0000000040000000' "$OUT/$lg.log" \
                && grep -aq '^超漢文起動' "$OUT/$lg.log" && grep -aq '^樹 有効 0x0000000000000001' "$OUT/$lg.log" \
                && grep -aq '^樹 EL 0x0000000000000001' "$OUT/$lg.log" && grep -aq '記憶管理有効' "$OUT/$lg.log" || LD_OK=0
        done
        if [ "$LD_OK" -eq 1 ] && grep -aq '^導誤 魔が KBL1 でない' "$OUT/loader3.log" && ! grep -aq '超漢文起動' "$OUT/loader3.log" \
           && grep -aq '^導誤 ブロック装置が無い' "$OUT/loader4.log" && ! grep -aq '超漢文起動' "$OUT/loader4.log"; then
            pass "boot: 独立ブートローダー 導 (DTB を避難して virtio-blk の KBL1 を読み、核へ移譲して核が DTB を読んで起動する。EL2 開始でも同じ。魔が違うイメージと装置なしは理由を出して止まる)"
        else
            fail "boot: 独立ブートローダー 導"
            grep -a '^導\|^樹 有効\|^樹 EL' "$OUT/loader1.log" "$OUT/loader2.log" "$OUT/loader3.log" "$OUT/loader4.log" 2>/dev/null | cut -c1-100 | sed 's/^/      /' | head -20
        fi
        # --- #47 T4: RTC を 1970-01-01 に固定した起動。PL031 が 0 を返し、時計は無効になる ----
        RTC_IMG="$OUT/rtc_off_serial"
        rm -f "$RTC_IMG.in" "$RTC_IMG.out" "$OUT/rtc_off.log"
        mkfifo "$RTC_IMG.in" "$RTC_IMG.out"
        cat "$RTC_IMG.out" > "$OUT/rtc_off.log" &
        RTC_CAT=$!
        qemu-system-aarch64 -M virt,gic-version=2 -cpu cortex-a57 -nographic \
            -rtc base=1970-01-01T00:00:00 \
            -global virtio-mmio.force-legacy=false \
            -serial "pipe:$RTC_IMG" -kernel "$OUT/kernel.elf" \
            >"$OUT/rtc_off.console.log" 2>&1 &
        RTC_QEMU=$!
        ( printf 'KANBUN\n' > "$RTC_IMG.in"
          for _ in $(seq 1 60); do grep -q "甲得" "$OUT/rtc_off.log" 2>/dev/null && break; sleep 0.25; done
          printf '時元試 無効\n時\n終\n' > "$RTC_IMG.in" ) &
        RTC_FEED=$!
        for _ in $(seq 1 50); do
            grep -q '^時元試 T4: 削 時元 ' "$OUT/rtc_off.log" 2>/dev/null && break
            sleep 0.5
        done
        kill "$RTC_QEMU" 2>/dev/null
        wait "$RTC_QEMU" 2>/dev/null
        wait "$RTC_CAT" 2>/dev/null
        kill "$RTC_FEED" 2>/dev/null
        wait "$RTC_FEED" 2>/dev/null
        RTC_N="$(grep -ac '^時元試 T4: ' "$OUT/rtc_off.log" 2>/dev/null)"
        RTC_BAD="$(grep -a '^時元試 T4: ' "$OUT/rtc_off.log" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${RTC_N:-0}" -eq 10 ] && [ "${RTC_BAD:-1}" -eq 0 ] \
           && grep -Eq '^日誌 黄紀 [0-9]+年[0-9][0-9]月[0-9][0-9]日 [0-9][0-9]:[0-9][0-9]:[0-9][0-9] UTC\?$' "$OUT/rtc_off.log" 2>/dev/null \
           && grep -Eq '^時 黄紀 [0-9]+年[0-9][0-9]月[0-9][0-9]日 [0-9][0-9]:[0-9][0-9]:[0-9][0-9] UTC\? Unix [0-9]+ 単調 [0-9]+ ms$' "$OUT/rtc_off.log" 2>/dev/null; then
            pass "kernel qemu: RTC 無効の起動 (壁時の旗 0、get_tim=ER_NODEV、篇の作時・改時 0、日誌と 時 の表示に ?)"
        else
            fail "kernel qemu: RTC 無効の起動 (T4 項目=${RTC_N:-0}/10、失敗=${RTC_BAD:-?})"
            grep -a '^時元試\|^日誌\|^時 ' "$OUT/rtc_off.log" 2>/dev/null | sed 's/^/      /' | head -30
        fi
    else
        echo "SKIP: kernel qemu (qemu-system-aarch64 not found)"
    fi
else
    echo "SKIP: kernel qemu (kernel.elf not built)"
fi

# --- 言語適合テスト (言語仕様 §10 M0 受入条件 1・2) ---------------------------
# 機械漢文のソースの拡張子は .mkn (README「開発上の約束」)。.txt のソースが残っていないこと。
STRAY="$(find kernel user tests src -name '*.txt' -not -path 'tests/output/*' 2>/dev/null)"
if [ -z "$STRAY" ]; then
    pass "規則: 機械漢文のソースの拡張子は .mkn (.txt のソースが無い)"
else
    fail "規則: .txt のソースが残っている ($(echo "$STRAY" | head -3 | tr '\n' ' '))"
fi

# tests/lang/ok/*.mkn  : 構文解析の golden (-ast を *.ast と比較) と 型検査+IR 生成の成功
# tests/lang/err/*.mkn : 1 行目の「註 期待: E00xx ...」の診断コードが全て出て、クラッシュせず失敗すること
# golden を更新するには UPDATE_GOLDEN=1 make test
echo "=== Language conformance tests ==="
LANG_OK=0; LANG_ERR=0
for f in tests/lang/ok/*.mkn; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .mkn)"
    LANG_OK=$((LANG_OK + 1))
    "$BIN" "$f" -ast >"$OUT/lang_$name.ast" 2>"$OUT/lang_$name.ast.log"
    if [ "${UPDATE_GOLDEN:-0}" = "1" ]; then
        cp "$OUT/lang_$name.ast" "tests/lang/ok/$name.ast"
    fi
    if diff -u "tests/lang/ok/$name.ast" "$OUT/lang_$name.ast" >"$OUT/lang_$name.ast.diff" 2>&1; then
        pass "lang ok: $name (parser golden)"
    else
        fail "lang ok: $name (parser golden)"
        sed 's/^/      /' "$OUT/lang_$name.ast.diff" | head -20
    fi
    "$BIN" "$f" -ir -o "$OUT/lang_$name.ll" >"$OUT/lang_$name.ir.log" 2>&1 \
        && pass "lang ok: $name (typecheck + IR)" || {
            fail "lang ok: $name (typecheck + IR)"
            sed 's/^/      /' "$OUT/lang_$name.ir.log" | head -5
        }
done
for f in tests/lang/err/*.mkn; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .mkn)"
    LANG_ERR=$((LANG_ERR + 1))
    expect="$(head -1 "$f" | grep -oE 'E00[0-9][0-9]' | tr '\n' ' ')"
    "$BIN" "$f" -ir -o /dev/null >"$OUT/lang_err_$name.log" 2>&1
    rc=$?
    good=1
    [ "$rc" -ge 1 ] && [ "$rc" -lt 128 ] || good=0
    for code in $expect; do
        grep -q "錯 $code:" "$OUT/lang_err_$name.log" || good=0
    done
    [ -n "$expect" ] || good=0
    if [ "$good" = "1" ]; then
        pass "lang err: $name ($expect)"
    else
        fail "lang err: $name (expected '$expect', rc=$rc)"
        sed 's/^/      /' "$OUT/lang_err_$name.log" | head -5
    fi
done
# 定数式の畳み込みと単項 負 が、LLVM の正しい IR (neg ではない) になること。
if "$LLC" -march=aarch64 -filetype=obj "$OUT/lang_consts.ll" -o "$OUT/lang_consts.o" \
        >"$OUT/lang_consts.llc.log" 2>&1 \
    && grep -q 'sub i64 0, 7' "$OUT/lang_consts.ll" \
    && grep -q -- '-147244780800' "$OUT/lang_consts.ll" \
    && grep -q 'add i64 7, -5' "$OUT/lang_consts.ll" \
    && ! grep -qE '(^|[[:space:]])neg[[:space:]]' "$OUT/lang_consts.ll"; then
    pass "lang ok: consts (定数式の畳み込み・単項 負 -> AArch64 object)"
else
    fail "lang ok: consts (定数式の畳み込み・単項 負 -> AArch64 object)"
    sed 's/^/      /' "$OUT/lang_consts.llc.log" | head -10
    grep -nE 'neg|147244780800|add i64 7' "$OUT/lang_consts.ll" | sed 's/^/      /' | head -10
fi
# 型付き機械命令が AArch64 の命令 (mrs/msr/dsb/isb/tlbi/dc/ic/wfi/svc/brk) になること。
if "$LLC" -march=aarch64 -filetype=obj "$OUT/lang_machine.ll" -o "$OUT/lang_machine.o" \
        >"$OUT/lang_machine.llc.log" 2>&1 \
    && "$OBJDUMP" -d "$OUT/lang_machine.o" >"$OUT/lang_machine.dis" 2>&1 \
    && grep -qE 'mrs[[:space:]]+x[0-9]+, CNTFRQ_EL0' "$OUT/lang_machine.dis" \
    && grep -qE 'msr[[:space:]]+TPIDR_EL1' "$OUT/lang_machine.dis" \
    && grep -qE 'msr[[:space:]]+DAIFClr, #0x2' "$OUT/lang_machine.dis" \
    && grep -qE 'dsb[[:space:]]+sy' "$OUT/lang_machine.dis" \
    && grep -qE 'tlbi[[:space:]]+vmalle1' "$OUT/lang_machine.dis" \
    && grep -qE 'dc[[:space:]]+cvau' "$OUT/lang_machine.dis" \
    && grep -qE 'ic[[:space:]]+iallu' "$OUT/lang_machine.dis" \
    && grep -qE 'wfi' "$OUT/lang_machine.dis" \
    && grep -qE 'svc[[:space:]]+#0' "$OUT/lang_machine.dis" \
    && grep -qE 'brk[[:space:]]+#0' "$OUT/lang_machine.dis" \
    && grep -qE 'sub[[:space:]]+sp, sp, #0x120' "$OUT/lang_machine.dis" \
    && grep -qE 'sub[[:space:]]+sp, sp, #0x100' "$OUT/lang_machine.dis" \
    && grep -qE 'stp[[:space:]]+x28, x29, \[sp, #0xe0\]' "$OUT/lang_machine.dis" \
    && grep -qE 'str[[:space:]]+x2, \[sp, #0x110\]' "$OUT/lang_machine.dis" \
    && grep -qE 'msr[[:space:]]+SP_EL0, x2' "$OUT/lang_machine.dis" \
    && grep -qE 'eret' "$OUT/lang_machine.dis" \
    && grep -qE 'bl[[:space:]]+0x[0-9a-f]+ <entry_probe' "$OUT/lang_machine.dis" \
    && grep -qE 'cbz[[:space:]]+x0,' "$OUT/lang_machine.dis" \
    && grep -qE 'mov[[:space:]]+x8, #0xb6' "$OUT/lang_machine.dis" \
    && grep -qE 'mov[[:space:]]+x4, #0x3c0' "$OUT/lang_machine.dis" \
    && grep -qE 'msr[[:space:]]+ELR_EL1, x0' "$OUT/lang_machine.dis" \
    && grep -qE 'msr[[:space:]]+HCR_EL2, x16' "$OUT/lang_machine.dis" \
    && grep -qE 'msr[[:space:]]+SPSR_EL2, x16' "$OUT/lang_machine.dis" \
    && grep -qE 'mrs[[:space:]]+x16, CurrentEL' "$OUT/lang_machine.dis" \
    && grep -qE 'br[[:space:]]+x1' "$OUT/lang_machine.dis" \
    && "$OBJDUMP" -dr "$OUT/lang_machine.o" >"$OUT/lang_machine.rel" 2>&1 \
    && [ "$(grep -cE 'R_AARCH64_JUMP26[[:space:]]+vh_' "$OUT/lang_machine.rel")" -eq 16 ] \
    && grep -qE '^[[:space:]]*0*280:[[:space:]]+R_AARCH64_JUMP26[[:space:]]+vh_irq$' "$OUT/lang_machine.rel" \
    && grep -qE '^[[:space:]]*0*400:[[:space:]]+R_AARCH64_JUMP26[[:space:]]+vh_sync0$' "$OUT/lang_machine.rel" \
    && grep -qE '^[[:space:]]*0*480:[[:space:]]+R_AARCH64_JUMP26[[:space:]]+vh_irq0$' "$OUT/lang_machine.rel"; then
    pass "lang ok: machine (型付き機械命令 -> AArch64 命令)"
else
    fail "lang ok: machine (型付き機械命令 -> AArch64 命令)"
    sed 's/^/      /' "$OUT/lang_machine.llc.log" | head -10
    grep -E 'mrs|msr|dsb|tlbi|dc |ic |wfi|svc|brk' "$OUT/lang_machine.dis" 2>/dev/null | sed 's/^/      /' | head -20
fi
# 全キーワードが golden テストのどこかで実際に使われていること (言語仕様 §10 条件 1)
: >"$OUT/lang_tokens.txt"
for f in tests/lang/ok/*.mkn; do "$BIN" "$f" -tokens 2>/dev/null | awk '{print $2}' >>"$OUT/lang_tokens.txt"; done
sort -u "$OUT/lang_tokens.txt" >"$OUT/lang_tokens.sorted"
KW_MISSING=""
for kw in $(grep -oE '\{"[^"]+", TokKind::[A-Za-z0-9]+\}' src/lexer.cpp | sed -E 's/\{"([^"]+)".*/\1/'); do
    grep -qxF "$kw" "$OUT/lang_tokens.sorted" || KW_MISSING="$KW_MISSING $kw"
done
if [ -z "$KW_MISSING" ]; then
    pass "lang ok: 全キーワードが golden テストで使われている"
else
    fail "lang ok: golden テストで未使用のキーワード:$KW_MISSING"
fi
echo "language cases: ok=$LANG_OK err=$LANG_ERR"

echo "=== Tests complete (rc=$RC) ==="
exit "$RC"
