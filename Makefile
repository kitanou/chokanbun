# 超漢文 OS - Compiler Build
#
# Usage:
#   make          - build the compiler (chokanbun)
#   make test     - run all tests (see tests/run_tests.sh)
#   make run      - run tests, then boot the kernel interactively under QEMU
#   make clean    - remove build artifacts
#
# LLVM tools are expected in /opt/homebrew/opt/llvm/bin (Homebrew)
# or set LLVM_BIN to override.

LLVM_BIN ?= /opt/homebrew/opt/llvm/bin
LLD_BIN ?= /opt/homebrew/opt/lld/bin

# CXX and LD are predefined by make, so ?= would not take effect here.
ifeq ($(origin CXX),default)
CXX := $(LLVM_BIN)/clang++
endif
ifeq ($(origin LD),default)
LD := $(LLD_BIN)/ld.lld
endif

CXXFLAGS ?= -std=c++17 -Wall -Wextra -g -O2 -MMD -MP

SRC_DIR := src
OBJ_DIR := build
BIN := chokanbun

SRCS := $(SRC_DIR)/lexer.cpp $(SRC_DIR)/ast.cpp $(SRC_DIR)/parser.cpp $(SRC_DIR)/typecheck.cpp $(SRC_DIR)/llvmir.cpp $(SRC_DIR)/astdump.cpp $(SRC_DIR)/main.cpp
OBJS := $(SRCS:$(SRC_DIR)/%.cpp=$(OBJ_DIR)/%.o)

.PHONY: all test run clean

all: $(BIN)

$(BIN): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $(OBJS)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.cpp | $(OBJ_DIR)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

# ヘッダの変更でも再コンパイルする (オブジェクト間のクラス配置の食い違いを防ぐ)
-include $(OBJS:.o=.d)

test: $(BIN)
	BIN=./$(BIN) LLVM_BIN="$(LLVM_BIN)" LLD_BIN="$(LLD_BIN)" \
		bash tests/run_tests.sh

run: test
	@echo "=== Running QEMU (漢極 kernel) ==="
	@test -f tests/output/disk.img || dd if=/dev/zero of=tests/output/disk.img bs=512 count=64 2>/dev/null
	qemu-system-aarch64 -M virt,gic-version=2 -cpu cortex-a57 -nographic -serial mon:stdio \
		-global virtio-mmio.force-legacy=false \
		-drive file=tests/output/disk.img,if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 \
		-kernel tests/output/kernel.elf

clean:
	rm -rf $(OBJ_DIR) $(BIN) tests/output
