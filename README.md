# 超漢文 OS — ChoKanbun OS

**機械漢文でカーネル内部まで記述する ARM64 ネイティブ OS。**

> 世界安寧

## 目的
- AArch64 (ARMv8-A) を対象とする独立した研究用OSを開発する。
- カーネル、システムコール、メモリ管理、プロセス管理、ドライバ、ユーザーランドを機械漢文で記述する。
- 機械漢文を独立したシステムプログラミング言語として定義し、LLVM IR経由でARM64機械語へコンパイルする。
- POSIX互換性は段階的に実装する。

## 開発方針
- 最初の実行環境: QEMU `virt` / AArch64。
- 最初の到達点: 機械漢文で記述したベアメタルプログラムがUARTへ「世界安寧」を出力する。
- ブート初期化などは当面最小限のAArch64アセンブリを許容し、後に低水準機械漢文構文へ移行する。
- コンパイラのブートストラップ実装には既存言語を許容する。カーネル本体は機械漢文を原則とする。
- `machine-kanbun` とは独立して仕様・実装・Issueを管理する。

## 設計文書
- [全体構成](docs/architecture.md)
- [機械漢文言語仕様草案](docs/language-spec.md)
- [AArch64 ABI・ブート方針](docs/abi-aarch64.md)
- [POSIX互換方針](docs/posix-compat.md)
- [ロードマップ](docs/roadmap.md)

## ビルドとテスト

```sh
make          # コンパイラ (chokanbun) をビルド
make test     # 全テストを実行 (IR生成 → AArch64オブジェクト → ELFリンク → QEMU)
make run      # 漢極カーネル (kernel/) をQEMU上で実行
make clean
```

LLVM ツールは既定で `/opt/homebrew/opt/llvm/bin` と `/opt/homebrew/opt/lld/bin`
を参照する。`LLVM_BIN` / `LLD_BIN` で上書きできる。

`make test` は `tests/run_tests.sh` を呼び出し、以下を検証する:

1. `hello` — 機械漢文 → LLVM IR → AArch64オブジェクト（逆アセンブル確認）
2. `uart` — `取址`/`長度` と `外術曰` 呼び出し → ELF リンク（C 版 UART スタブと結合）
3. `uart_mmio` — **機械漢文のみで記述した PL011 ドライバ**（`險`/`項`/`讀揮發`/`寫揮發`）→ ELF リンク
4. `kernel` — `kernel/` の漢極（例外ベクタ・例外ハンドラ・MMU・物理ページ割当）→ ELF リンク（`_vectors` の 2KiB 整列も検証）
5. `type_error` — 型不一致の診断（`E00xx`）が出ること
6. `qemu` — QEMU `virt` 上で機械漢文ドライバが PL011 に **世界安寧** を出力すること
7. `kernel qemu` — QEMU `virt` 上で漢極が **超漢文起動**・**異常捕獲（BRK 診断）**・**記憶管理有効（MMU）**・**物理ページ割当** を出力すること

## 開発状況
Phase 0 完了。機械漢文コンパイラがビルド・テスト可能で、
QEMU `virt` / AArch64 上で機械漢文ソース由来のコードが UART に「世界安寧」を
出力する。さらに M2 の一部として、PL011 UART ドライバを機械漢文の
volatile MMIO・生ポインタ添字で記述できる（`tests/uart_mmio.txt`）。

M2 のカーネル基盤として `kernel/` を新設した。漢極本体（`kernel/kernel.txt`）は
機械漢文で記述し、PL011 出力、例外ハンドラ（`brk #0` を捕捉して ESR を復号し
`eret` で継続）、物理ページ割当、レベル1 変換表の構築による恒等写像 MMU 有効化を
行う。暫定 AArch64 アセンブリはスタック設定（`kernel/boot.S`）、例外ベクタ表と
レジスタ保存（`kernel/vectors.S`）、システムレジスタ操作（`kernel/sysreg.S`）に
限定する。`boot/uart.c` の C 版ドライバは `外術曰` 連携の後方互換・参照用として
残している。旧起動スタブ `boot/boot.S` は Phase 0 の参照用。

