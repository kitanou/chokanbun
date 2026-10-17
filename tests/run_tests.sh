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
"$BIN" kernel/kernel.txt -ir -o "$OUT/kernel.ll" 2>"$OUT/kernel.gen.log" \
    && pass "kernel: IR generation" || fail "kernel: IR generation"
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

if [ -f "$OUT/kernel.o" ] && [ -f "$OUT/kernel_boot.o" ] && \
   [ -f "$OUT/kernel_vectors.o" ] && [ -f "$OUT/kernel_sysreg.o" ] && \
   [ -f "$OUT/kernel_el0.o" ]; then
    "$LD" -T kernel/kernel.lds "$OUT/kernel_boot.o" "$OUT/kernel_vectors.o" \
        "$OUT/kernel_sysreg.o" "$OUT/kernel_el0.o" "$OUT/kernel.o" -o "$OUT/kernel.elf" \
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
        rm -f "$KLOG"
        qemu-system-aarch64 -M virt,gic-version=2 -cpu cortex-a57 -nographic \
            -serial "file:$KLOG" -kernel "$OUT/kernel.elf" \
            >"$OUT/kernel_qemu.console.log" 2>&1 &
        QPID=$!
        # Wait up to ~15s for the final marker, then stop QEMU.  The generic
        # timer fires five times (5 × CNTFRQ/40 ≈ 125 ms), so this is ample.
        for _ in $(seq 1 30); do
            grep -q "民務終了" "$KLOG" 2>/dev/null && break
            sleep 0.5
        done
        kill "$QPID" 2>/dev/null
        wait "$QPID" 2>/dev/null
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
        KSEQ="$(grep -oE '甲書|乙書|甲讀|乙讀' "$KLOG" 2>/dev/null | paste -sd' ' -)"
        if [ "$KSEQ" = "甲書 乙書 甲讀 乙讀" ]; then
            pass "kernel qemu: 譲渡によるラウンドロビン切替"
        else
            fail "kernel qemu: 譲渡によるラウンドロビン切替 (got '${KSEQ:-none}')"
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

echo "=== Tests complete (rc=$RC) ==="
exit "$RC"
