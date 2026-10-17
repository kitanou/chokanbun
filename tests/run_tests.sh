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
"$BIN" tests/hello.txt -ir -o "$OUT/hello.ll" 2>"$OUT/hello.gen.log" \
    && pass "hello: IR generation" || fail "hello: IR generation"
"$LLC" -march=aarch64 -filetype=obj "$OUT/hello.ll" -o "$OUT/hello.o" \
    >"$OUT/hello.llc.log" 2>&1 \
    && pass "hello: AArch64 object" || fail "hello: AArch64 object"
"$OBJDUMP" -d "$OUT/hello.o" >"$OUT/hello.dis" 2>&1 \
    && pass "hello: disassembly" || fail "hello: disassembly"

# --- uart: 核外輸出 call + 取址/長度 builtins -> ELF ----------------------
"$BIN" tests/uart.txt -ir -o "$OUT/uart.ll" 2>"$OUT/uart.gen.log" \
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
"$BIN" tests/uart_mmio.txt -ir -o "$OUT/uart_mmio.ll" 2>"$OUT/uart_mmio.gen.log" \
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
# kernel/kernel.txt の「註 @取込」(kernel/vfs/*.txt) を展開してからコンパイルする。
sh tools/kernel-expand.sh kernel/kernel.txt "$OUT/kernel_all.txt" \
    && pass "kernel: 取込の展開 (kernel/vfs/)" || fail "kernel: 取込の展開 (kernel/vfs/)"
# 展開後の行番号を元のファイル:行へ戻せること (診断の位置合わせ)
KLINE="$(grep -n '術曰「籍削」' "$OUT/kernel_all.txt" | head -1 | cut -d: -f1)"
if [ -n "$KLINE" ] && [ "$(sh tools/kernel-line.sh "$OUT/kernel_all.txt.map" "$KLINE")" = \
     "kernel/vfs/ramfs.txt:$(grep -n '術曰「籍削」' kernel/vfs/ramfs.txt | head -1 | cut -d: -f1)" ]; then
    pass "kernel: 展開後の行番号を元のファイル:行へ戻せる (籍削 → kernel/vfs/ramfs.txt)"
else
    fail "kernel: 展開後の行番号を元のファイル:行へ戻せる"
fi
"$BIN" "$OUT/kernel_all.txt" -ir -o "$OUT/kernel.ll" 2>"$OUT/kernel.gen.log" \
    && pass "kernel: IR generation" || fail "kernel: IR generation"
if [ -s "$OUT/kernel.gen.log" ] && grep -q '錯' "$OUT/kernel.gen.log"; then
    echo "      (診断の行は展開後のもの。元の位置は: sh tools/kernel-line.sh $OUT/kernel_all.txt.map <行>)"
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
sh tools/mkimage.sh user/hello.txt "$OUT/hello.zo" "$OUT" 2>"$OUT/user_hello.build.log" \
    && pass "user: 外部命令 問安 を漢像にビルド" || {
        fail "user: 外部命令 問安 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_hello.build.log" | head -10
    }
sh tools/mkimage.sh user/count.txt "$OUT/count.zo" "$OUT" 2>"$OUT/user_count.build.log" \
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
sh tools/mkimage.sh user/btron_gtid.txt "$OUT/btron_gtid.zo" "$OUT" 2>"$OUT/user_btron_gtid.build.log" \
    && pass "user: BTRON3 互換層の試験 識試 (get_tid・ER_*) を漢像にビルド" || {
        fail "user: BTRON3 互換層の試験 識試 を漢像にビルド"
        sed 's/^/      /' "$OUT/user_btron_gtid.build.log" | head -10
    }
sh tools/gen-images.sh "$OUT/kernel_images.S" 問安="$OUT/hello.zo" 數="$OUT/count.zo" 識試="$OUT/btron_gtid.zo" \
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
"$BIN" tests/type_error.txt -ir -o /dev/null >"$OUT/type_error.log" 2>&1 \
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
        qemu-system-aarch64 -M virt,gic-version=2 -cpu cortex-a57 -nographic \
            -serial "pipe:$PIPE" -kernel "$OUT/kernel.elf" \
            >"$OUT/kernel_qemu.console.log" 2>&1 &
        QPID=$!
        # Feed one console line for the 読込 (番10) test.
        # Then feed 殻 (shell) commands once 甲 has read that line (M4).
        ( printf 'KANBUN\n' > "$PIPE.in"
          for _ in $(seq 1 60); do grep -q "甲得" "$KLOG" 2>/dev/null && break; sleep 0.25; done
          printf '響 天下太平\n讀 史記\n怪\n讀 無題\n目\n書 筆記 天地玄黄\n讀 筆記\n書 一二三四五六 x\n書 筆記\n目\n削 筆記\n讀 筆記\n目\n削 筆記\n書 新稿 草\n目\n問安 日月\n數 一 二 三\n識試\n存在せず 子\n助\n終\n' > "$PIPE.in" ) &
        FEEDPID=$!
        # Wait up to ~15s for the final marker, then stop QEMU.  The generic
        # timer fires five times (5 × CNTFRQ/40 ≈ 125 ms), so this is ample.
        for _ in $(seq 1 30); do
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
        if grep -q '殻誤 0xfffffffffffffff2' "$KLOG" 2>/dev/null && grep -q '殻用法' "$KLOG" 2>/dev/null; then
            pass "kernel qemu: 殻 書 の誤り経路 (長すぎる名前→-EFAULT、引数不足→用法)"
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
        K_HELP="$(grep -c '殻命令一覧' "$KLOG" 2>/dev/null)"
        if [ "${K_HELP:-0}" -eq 1 ] && grep -q '書 名 文  … 典籍を作って文を書く' "$KLOG" 2>/dev/null \
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
        if [ "${K_CH:-0}" -eq 22 ]; then
            pass "kernel qemu: 起動・回収を 20 回繰り返しても頁が漏れず、毎回子が走る (子の出力 22 回 = 検証 21 + 殻 1)"
        else
            fail "kernel qemu: 起動・回収の繰り返し (子の出力=${K_CH:-0} 回、期待 22)"
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
        for k in 'get_tid=識別' 'get_tid>0' 'ER_負' '錯換'; do
            got="$(btron_val "$k")"
            [ "$got" = "0x0000000000000001" ] || BTRON_BAD="$BTRON_BAD $k(got=${got:-none})"
        done
        if [ -z "$BTRON_BAD" ]; then
            pass "kernel qemu: BTRON3 互換層 get_tid が 漢令 識別 と一致し正、ER_* が負、錯換の対応が正しい"
        else
            fail "kernel qemu: BTRON3 互換層 (不一致:$BTRON_BAD)"
            grep -a '識試' "$KLOG" 2>/dev/null | sed 's/^/      /'
        fi
        K_UNK="$(grep -ac '殻不明' "$KLOG" 2>/dev/null)"
        if [ "${K_UNK:-0}" -ge 2 ]; then
            pass "kernel qemu: 像の無い命令は 殻不明 (組み込みでも外部命令でもない)"
        else
            fail "kernel qemu: 像の無い命令は 殻不明 (件数=${K_UNK:-0})"
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
        K_TOTAL="$(tbl_val '頁池 総')"
        if [ "$K_TOTAL" = "$(printf '0x%016x' 4096)" ]; then
            pass "kernel qemu: 頁池 16 MiB (4096 ページ = 空き + 行程の棧 2 ページ × 8)"
        else
            fail "kernel qemu: 頁池 16 MiB (総=${K_TOTAL:-none}、期待 0x1000)"
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
    else
        echo "SKIP: kernel qemu (qemu-system-aarch64 not found)"
    fi
else
    echo "SKIP: kernel qemu (kernel.elf not built)"
fi

# --- 言語適合テスト (言語仕様 §10 M0 受入条件 1・2) ---------------------------
# tests/lang/ok/*.txt  : 構文解析の golden (-ast を *.ast と比較) と 型検査+IR 生成の成功
# tests/lang/err/*.txt : 1 行目の「註 期待: E00xx ...」の診断コードが全て出て、クラッシュせず失敗すること
# golden を更新するには UPDATE_GOLDEN=1 make test
echo "=== Language conformance tests ==="
LANG_OK=0; LANG_ERR=0
for f in tests/lang/ok/*.txt; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .txt)"
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
for f in tests/lang/err/*.txt; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .txt)"
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
for f in tests/lang/ok/*.txt; do "$BIN" "$f" -tokens 2>/dev/null | awk '{print $2}' >>"$OUT/lang_tokens.txt"; done
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
