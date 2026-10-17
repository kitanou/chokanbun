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

# --- type_error: 錯 E00xx must be reported --------------------------------
"$BIN" tests/type_error.txt -ir -o /dev/null >"$OUT/type_error.log" 2>&1 \
    && fail "type_error: unexpected success" || pass "type_error: rejected"
if grep -q "E00" "$OUT/type_error.log"; then
    pass "type_error: diagnostic E00xx"
else
    fail "type_error: diagnostic E00xx"
fi

# --- QEMU: 世界安寧 on the PL011 UART --------------------------------------
if [ -f "$OUT/uart.elf" ]; then
    if command -v qemu-system-aarch64 >/dev/null 2>&1; then
        QLOG="$OUT/qemu.log"
        rm -f "$QLOG"
        qemu-system-aarch64 -M virt -cpu cortex-a57 -nographic \
            -serial "file:$QLOG" -kernel "$OUT/uart.elf" \
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
            pass "qemu: 世界安寧 output"
        else
            fail "qemu: 世界安寧 output"
            sed 's/^/      /' "$QLOG" 2>/dev/null | head -20
        fi
    else
        echo "SKIP: qemu (qemu-system-aarch64 not found)"
    fi
else
    echo "SKIP: qemu (uart.elf not built)"
fi

echo "=== Tests complete (rc=$RC) ==="
exit "$RC"
