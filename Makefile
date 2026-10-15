# 超漢文 OS - Compiler Build
#
# Usage:
#   make          - build the compiler (chokanbun)
#   make test     - run all tests
#   make clean    - remove build artifacts
#
# LLVM tools are expected in /opt/homebrew/opt/llvm/bin (Homebrew)
# or set LLVM_BIN to override.

LLVM_BIN ?= /opt/homebrew/opt/llvm/bin
LLD_BIN ?= /opt/homebrew/opt/lld/bin
CXX ?= $(LLVM_BIN)/clang++
CLANG ?= $(LLVM_BIN)/clang
LLC ?= $(LLVM_BIN)/llc
LD ?= $(LLD_BIN)/ld.lld
CXXFLAGS ?= -std=c++17 -Wall -Wextra -g -O2

SRC_DIR := src
OBJ_DIR := build
BIN := chokanbun

SRCS := $(SRC_DIR)/lexer.cpp $(SRC_DIR)/ast.cpp $(SRC_DIR)/parser.cpp $(SRC_DIR)/typecheck.cpp $(SRC_DIR)/llvmir.cpp $(SRC_DIR)/main.cpp
OBJS := $(SRCS:$(SRC_DIR)/%.cpp=$(OBJ_DIR)/%.o)

.PHONY: all test clean run

all: $(BIN)

$(BIN): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $(OBJS)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.cpp | $(OBJ_DIR)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

test: $(BIN)
	@echo "=== Running tests ==="
	@mkdir -p tests/output
	@echo "--- Test: hello (basic function) ---"
	./$(BIN) tests/hello.txt -ir -o tests/output/hello.ll && \
	$(CLANG) --target=aarch64-none-elf -c tests/output/hello.ll -o tests/output/hello.o && \
	$(LLC) -march=aarch64 -filetype=obj tests/output/hello.o -o tests/output/hello.elf && \
	echo "PASS: hello" || echo "FAIL: hello"
	@echo "--- Test: uart (world peace) ---"
	./$(BIN) tests/uart.txt -ir -o tests/output/uart.ll && \
	$(CLANG) --target=aarch64-none-elf -ffreestanding -c tests/output/uart.ll -o tests/output/uart.o && \
	$(LD) -T boot/boot.lds -entry main tests/output/uart.o -o tests/output/uart.elf && \
	echo "PASS: uart" || echo "FAIL: uart"
	@echo "--- Test: type errors ---"
	./$(BIN) tests/type_error.txt -ir -o /dev/null 2>&1 | grep -q "E00" && \
	echo "PASS: type_error" || echo "FAIL: type_error"
	@echo "=== Tests complete ==="

run: test
	@echo "=== Running QEMU ==="
	qemu-system-aarch64 -M virt -cpu cortex-a57 -nographic -serial stdio \
		-kernel tests/output/uart.elf 2>&1 | head -5

clean:
	rm -rf $(OBJ_DIR) $(BIN) tests/output

# Convenience: build and run the UART example
world-peace: test
	@echo "Output should contain: 世界安寧"
