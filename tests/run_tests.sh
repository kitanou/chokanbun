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
"$CLANG" --target=aarch64-none-elf -c boot/boot.S -o "$OUT/boot.o" \
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
"$LLC" -march=aarch64 -filetype=obj "$OUT/kernel.ll" -o "$OUT/kernel.o" \
    >"$OUT/kernel.llc.log" 2>&1 \
    && pass "kernel: AArch64 object" || fail "kernel: AArch64 object"
"$CLANG" --target=aarch64-none-elf -c kernel/boot.S -o "$OUT/kernel_boot.o" \
    >"$OUT/kernel_boot.log" 2>&1 \
    && pass "kernel: boot stub object" || fail "kernel: boot stub object"
"$CLANG" --target=aarch64-none-elf -c kernel/vectors.S -o "$OUT/kernel_vectors.o" \
    >"$OUT/kernel_vectors.log" 2>&1 \
    && pass "kernel: exception vectors object" || fail "kernel: exception vectors object"
"$CLANG" --target=aarch64-none-elf -c kernel/sysreg.S -o "$OUT/kernel_sysreg.o" \
    >"$OUT/kernel_sysreg.log" 2>&1 \
    && pass "kernel: sysreg helpers object" || fail "kernel: sysreg helpers object"
"$CLANG" --target=aarch64-none-elf -c kernel/el0.S -o "$OUT/kernel_el0.o" \
    >"$OUT/kernel_el0.log" 2>&1 \
    && pass "kernel: EL0/SVC boundary object" || fail "kernel: EL0/SVC boundary object"

# 外部命令 (漢像 KBN1) をビルドし、カーネルイメージへ埋め込む (行程の設計 P1)。
export BIN LLVM_BIN LLD_BIN
sh tools/mkimage.sh user/hello.mkn "$OUT/hello.zo" "$OUT" 2>"$OUT/user_hello.build.log" \
    && pass "user: 外部命令 問安 を漢像にビルド" || {
        fail "user: 外部命令 問安 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_hello.build.log" | head -10
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
    && pass "user: BTRON3 互換層の試験 実試 (3.8 実身／仮身マネージャの登録簿) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 実試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_omgr.build.log" | head -10
    }
sh tools/mkimage.sh user/btron_sys.mkn "$OUT/btron_sys.zo" "$OUT" 2>"$OUT/user_btron_sys.build.log" \
    && pass "user: BTRON3 互換層の試験 系試 (1.10 システム管理) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 系試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_sys.build.log" | head -10
    }
sh tools/gen-images.sh "$OUT/kernel_images.S" 問安="$OUT/hello.zo" 數="$OUT/count.zo" 識試="$OUT/btron_gtid.zo" 名試="$OUT/btron_gname.zo" 時試="$OUT/btron_clk.zo" 信試="$OUT/btron_msg.zo" 利試="$OUT/btron_usr.zo" 強試="$OUT/btron_term.zo" 同試="$OUT/btron_sync.zo" 緩試="$OUT/btron_comm.zo" 録試="$OUT/btron_file.zo" 篇試="$OUT/pian_test.zo" 永試="$OUT/pian_persist.zo" 貯試="$OUT/btron_mem.zo" 件試="$OUT/btron_evt.zo" 設試="$OUT/btron_dev.zo" 系試="$OUT/btron_sys.zo" 実試="$OUT/btron_omgr.zo" \
    && "$CLANG" --target=aarch64-none-elf -c "$OUT/kernel_images.S" -o "$OUT/kernel_images.o" \
        >"$OUT/kernel_images.log" 2>&1 \
    && pass "kernel: 漢像の埋め込み (像表)" || fail "kernel: 漢像の埋め込み (像表)"

if [ -f "$OUT/kernel.o" ] && [ -f "$OUT/kernel_boot.o" ] && \
   [ -f "$OUT/kernel_vectors.o" ] && [ -f "$OUT/kernel_sysreg.o" ] && \
   [ -f "$OUT/kernel_el0.o" ] && [ -f "$OUT/kernel_images.o" ]; then
    "$LD" -T kernel/kernel.lds "$OUT/kernel_boot.o" "$OUT/kernel_vectors.o" \
        "$OUT/kernel_sysreg.o" "$OUT/kernel_el0.o" "$OUT/kernel_images.o" "$OUT/kernel.o" -o "$OUT/kernel.elf" \
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
          printf '響 天下太平\n讀 史記\n怪\n讀 無題\n目\n書 筆記 天地玄黄\n讀 筆記\n書 一二三四五六七八九十壱 x\n書 筆記\n目\n削 筆記\n讀 筆記\n目\n削 筆記\n書 新稿 草\n目\n問安 日月\n數 一 二 三\n識試\n名試\n時試\n信試\n利試\n強試\n同試\n緩試\n録試\n篇試\n貯試\n件試\n設試\n系試\n実試\n章 天地/家/殻章\n移 天地/家/殻章\n在\n書 甲 一二\n改 甲 乙\n讀 乙\n改 甲\n移 ..\n在\n移 天地/典/史記\n移 天地/典\n在\n存在せず 子\n\n終了\n   \n助\n終\n' > "$PIPE.in" ) &
        FEEDPID=$!
        # Wait up to ~40s for the final marker, then stop QEMU.  The generic
        # timer fires five times (5 × CNTFRQ/40 ≈ 125 ms); the long parts are the
        # BTRON3 file-management test (録試) and the memory test (貯試), which
        # grows with every stage (3 つの子を起動して回収する).
        for _ in $(seq 1 80); do
            grep -q "殻終" "$KLOG" 2>/dev/null && grep -q "民務終了 行程=0x0000000000000000" "$KLOG" 2>/dev/null && break
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
        for kv in 異頁=1 残減=1 解放=1 二重=0 範囲外=0 境界外=0 再利用=1 零埋=0 復元=1; do
            k="${kv%%=*}"; want="$(printf '0x%016x' "${kv##*=}")"
            got="$(pool_val "$k")"
            [ "$got" = "$want" ] || POOL_BAD="$POOL_BAD $k(want=$want got=${got:-none})"
        done
        if [ -z "$POOL_BAD" ]; then
            pass "kernel qemu: 頁池 割当・解放・二重解放・範囲外・再利用・ゼロ埋め・空き数の復元"
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
        # 子の出力 = 検証 21 + 殻の 問安 1 + 篇試 が術のパスで起動する 問安 1 + 貯試 が起動する 3 役
        if [ "${K_CH:-0}" -eq 26 ]; then
            pass "kernel qemu: 起動・回収を 20 回繰り返しても頁が漏れず、毎回子が走る (子の出力 26 回 = 検証 21 + 殻 1 + 篇試 1 + 貯試 3)"
        else
            fail "kernel qemu: 起動・回収の繰り返し (子の出力=${K_CH:-0} 回、期待 26)"
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
        for k in 'get_tid=識別' 'get_tid>0' 'ER_負' '錯換' 'H=符号付16' 'H=32767' 'H=-32768' 'H隣欄保持' 'Bool=False0True1' 'SIZE配置' 'PNT配置' 'RECT4辺' 'RECT共用体'; do
            got="$(btron_val "$k")"
            [ "$got" = "0x0000000000000001" ] || BTRON_BAD="$BTRON_BAD $k(got=${got:-none})"
        done
        if [ -z "$BTRON_BAD" ]; then
            pass "kernel qemu: BTRON3 互換層 get_tid が 漢令 識別 と一致し正、ER_* が負、錯換の対応が正しい、共有データ編 §1 の H・Bool・SIZE・PNT・RECT が配置どおり"
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
        if [ "${OM_N:-0}" -eq 34 ] && [ "${OM_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 実身／仮身マネージャの登録簿・実身の操作・続柄 (oreg_vob ほか V1a・V1b・ochg_rel・ocnv_vob の ${OM_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 実身／仮身マネージャの登録簿と実身の操作 (項目=${OM_N:-0}/34、失敗=${OM_BAD:-?})"
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
        # --- 篇藏 F1〜F3 (#6): 篇ID・屬、章とパス、名替、權・志・器・術・法 ---------------
        PF_N="$(grep -ac '^篇試 ' "$KLOG" 2>/dev/null)"
        PF_BAD="$(grep -a '^篇試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${PF_N:-0}" -eq 28 ] && [ "${PF_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: 篇藏 F1〜F3 (${PF_N} 項目)"
        else
            fail "kernel qemu: 篇藏 F1〜F3 (項目=${PF_N:-0}/28、失敗=${PF_BAD:-?})"
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
        if [ "${FL_N:-0}" -eq 117 ] && [ "${FL_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 ファイル管理 B1・B2 (接続・get_lnk・chg_wrk・作成・削除・開閉・状態の ${FL_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 ファイル管理 B1 (項目=${FL_N:-0}/117、失敗=${FL_BAD:-?})"
            grep -a '^録試 ' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # --- #42 G6b: メッセージバッファとランデブポート (1.3) ------------------------
        CM_N="$(grep -ac '^緩試 ' "$KLOG" 2>/dev/null)"
        CM_BAD="$(grep -a '^緩試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${CM_N:-0}" -eq 27 ] && [ "${CM_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 メッセージバッファ・ランデブ (環の折り返し・待ち・転送・削除の ${CM_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 メッセージバッファ・ランデブ (項目=${CM_N:-0}/27、失敗=${CM_BAD:-?})"
            grep -a '^緩試 ' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        # --- #42 G6a: セマフォとイベントフラグ (1.3) -------------------------------------
        SY_N="$(grep -ac '^同試 ' "$KLOG" 2>/dev/null)"
        SY_BAD="$(grep -a '^同試 ' "$KLOG" 2>/dev/null | grep -vc '0x0000000000000001$')"
        if [ "${SY_N:-0}" -eq 21 ] && [ "${SY_BAD:-1}" -eq 0 ]; then
            pass "kernel qemu: BTRON3 互換層 セマフォ・イベントフラグ (待ちの FIFO・時間切れ・削除・DELEXIT・自動返却の ${SY_N} 項目)"
        else
            fail "kernel qemu: BTRON3 互換層 セマフォ・イベントフラグ (項目=${SY_N:-0}/21、失敗=${SY_BAD:-?})"
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
        if [ "${K_UNK:-0}" -eq 3 ] && [ "${K_SERR:-0}" -eq 3 ]; then
            pass "kernel qemu: 像の無い命令は 殻不明 (怪・存在せず 子・終了 の 3 件。空行と空白だけの行は何も出さず、終了 は 終 と取り違えて殻を終えない)"
        else
            fail "kernel qemu: 像の無い命令は 殻不明 (件数=${K_UNK:-0}、期待 3。殻誤=${K_SERR:-0}、期待 3)"
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
        # 注: 総数は、この実行で必ず virtio-blk を付けている (vda の環 2 ページが先に使われる) ことを前提にした 4094。
        K_TOTAL="$(tbl_val '頁池 総')"
        if [ "$K_TOTAL" = "$(printf '0x%016x' 4094)" ]; then
            pass "kernel qemu: 頁池 16 MiB (4096 ページ = 空き + 行程の棧 2 ページ × 8 + vda の環 2 ページ。総数は vda の 2 ページを除く)"
        else
            fail "kernel qemu: 頁池 16 MiB (総=${K_TOTAL:-none}、期待 0xffe)"
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
        if grep -q "民務終了 行程=0x0000000000000000" "$KLOG" 2>/dev/null && \
           grep -q "民務終了 行程=0x0000000000000001" "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 両行程が 終行程 で終了し EL1 へ復歸"
        else
            fail "kernel qemu: 両行程が 終行程 で終了し EL1 へ復歸"
            sed 's/^/      /' "$KLOG" 2>/dev/null | head -20
        fi
        # --- 篇藏の永続化 (docs/design-persistence.md): 書いて 篇同 → 再起動 → 読める。壊れたスロットは使わない -------
        # 同じディスクイメージ (10370 区画以上。12288 区画) で 5 回起動し、そのたびに殻へ命令を流して 殻終 を待つ。
        PERSIST_IMG="$OUT/persist.img"
        PERSIST_PIPE="$OUT/persist_serial"
        dd if=/dev/zero of="$PERSIST_IMG" bs=512 count=12288 2>/dev/null
        pian_boot() {  # $1 = ログ、$2 = 殻に流す命令 (改行区切り)
            local plog="$1" pcmds="$2" pq pc pf
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
              printf '%s' "$pcmds" > "$PERSIST_PIPE.in" ) &
            pf=$!
            for _ in $(seq 1 80); do
                grep -q "殻終" "$plog" 2>/dev/null && break
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
        if persist_ok "$OUT/persist1.log" 'F:' && persist_ok "$OUT/persist1.log" 'W:' && [ "$P1_HDR" = "50 49 41 4e" ]; then
            pass "kernel qemu: 録層に 13 バイトと 6000 バイト (2 頁) のファイルを作り、篇同 で篇藏と録層の状態がスロット A のヘッダ (PIAN) としてディスクに届く"
        else
            fail "kernel qemu: 篇同 の書込み (ヘッダ='$P1_HDR')"
            grep -a '永試' "$OUT/persist1.log" 2>/dev/null | sed 's/^/      /' | head -5
        fi
        pian_boot "$OUT/persist2.log" $'永試 R\n永試 G\n永試 O\n終\n'
        P2_HDR="$(od -An -v -tx1 -j 2671104 -N 4 "$PERSIST_IMG" | tr -s ' ' | sed 's/^ //; s/ $//')"
        if persist_ok "$OUT/persist2.log" 'R:' && grep -aq '篇戻 世代=0x0000000000000001' "$OUT/persist2.log" && persist_ok "$OUT/persist2.log" 'G:' && persist_ok "$OUT/persist2.log" 'O:' && [ "$P2_HDR" = "50 49 41 4e" ]; then
            pass "kernel qemu: 再起動のあとスロット A (世代 1) から戻り、篇藏の内容と録層の 2 つのファイル (6000 バイト = 2 頁を含む) を読める。戻したあとに作った録層のファイルは新しい ID になる。開いたままの 篇同 はスロット B (世代 2) へ"
        else
            fail "kernel qemu: 再起動後の読み戻しとスロット B への書込み (ヘッダ='$P2_HDR')"
            grep -a '永試\|篇戻' "$OUT/persist2.log" 2>/dev/null | sed 's/^/      /' | head -6
        fi
        pian_boot "$OUT/persist3.log" $'永試 R\n永試 H\n永試 D\n同\n問安 日月\n終\n'
        if persist_ok "$OUT/persist3.log" 'R:' && persist_ok "$OUT/persist3.log" 'H:' && grep -aq '^子行程起動 日月' "$OUT/persist3.log" && grep -aq '篇戻 世代=0x0000000000000002' "$OUT/persist3.log" && persist_ok "$OUT/persist3.log" 'D:' && grep -aq '殻同 保存した' "$OUT/persist3.log"; then
            pass "kernel qemu: 世代 2 (スロット B) から戻り、開いたまま保存した篇も削れる (開数は保存した値が残らない)。戻したあとに作った録層のファイルも戻る。殻の 同 で世代 3 をスロット A へ保存でき、戻したあとも漢像 (問安) を起動できる"
        else
            fail "kernel qemu: 世代 2 の読み戻しと開数"
            grep -a '永試\|篇戻' "$OUT/persist3.log" 2>/dev/null | sed 's/^/      /' | head -6
        fi
        # 最新 (世代 3) のスロット A のヘッダは無傷のまま、録層の本体の区画 1 つ (最初のファイルの最初の区画) を壊す
        # → データのチェックサムが合わず、世代 2 のスロット B から戻る (録層の区画の破損も検出する)
        printf '\377\377\377\377' | dd of="$PERSIST_IMG" bs=1 seek=$((1121 * 512)) conv=notrunc 2>/dev/null
        pian_boot "$OUT/persist4.log" $'永試 R\n永試 H\n終\n'
        if persist_ok "$OUT/persist4.log" 'R:' && persist_ok "$OUT/persist4.log" 'H:' && grep -aq '篇戻 世代=0x0000000000000002' "$OUT/persist4.log"; then
            pass "kernel qemu: ヘッダが無傷でも録層の区画が壊れた最新のスロット A は使わず、世代 2 のスロット B から戻る (データのチェックサム)"
        else
            fail "kernel qemu: 壊れた録層の区画を持つスロットを避けて戻れない"
            grep -a '永試\|篇戻' "$OUT/persist4.log" 2>/dev/null | sed 's/^/      /' | head -6
        fi
        # スロット A のヘッダと、スロット B の篇の表の区画 (スロット先頭の 2 区画目) も壊す → どちらも使えず、初期化した状態で起動する
        dd if=/dev/zero of="$PERSIST_IMG" bs=512 seek=64 count=1 conv=notrunc 2>/dev/null
        printf '\377\377\377\377' | dd of="$PERSIST_IMG" bs=1 seek=$((5218 * 512)) conv=notrunc 2>/dev/null
        pian_boot "$OUT/persist5.log" $'永試 N\n永試 M\n終\n'
        if persist_ok "$OUT/persist5.log" 'N:' && persist_ok "$OUT/persist5.log" 'M:' && ! grep -aq '篇戻' "$OUT/persist5.log"; then
            pass "kernel qemu: どのスロットも使えないときは初期化した状態で起動する (篇「永」も録層の pmem も無い)"
        else
            fail "kernel qemu: 両スロットが使えないときの起動"
            grep -a '永試\|篇戻' "$OUT/persist5.log" 2>/dev/null | sed 's/^/      /' | head -6
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
