# 超漢文OS アーキテクチャ v0.1（草案）

## 原則
1. カーネル内部・ドライバ・ユーザーランドを機械漢文で記述する。
2. コンパイラは独立実装し、機械漢文AST → 型付きIR → LLVM IR → AArch64 と変換する。
3. 実行時の構造体やページテーブルはバイナリ表現とし、漢文テキストとして保持しない。
4. 初期ブートと例外入口に必要な最小限のアセンブリは暫定許容する。
5. QEMU virtで検証後、実機移植を検討する。

## 層
- userland: 漢文シェル、基本コマンド
- runtime: syscallラッパー、標準入出力、メモリAPI
- kernel: 起動、物理/仮想メモリ、例外、行程、スケジューラ、VFS、ドライバ
- arch/aarch64: EL1/EL0、MMU、例外ベクタ、GIC、汎用タイマー、PL011 UART
- hardware: QEMU virt (AArch64)

## 境界
- EL1: カーネル、EL0: ユーザー空間
- システムコール: SVCを介する。番号・引数・エラー規約はABI文書で固定
- デバイス: MMIOを型付きvolatile操作として表現
- 互換性: POSIXは独立レイヤーで段階的に実装

## 実装状況（M2）
- `kernel/`: 漢極本体。`kernel.txt`（機械漢文）が PL011 出力・例外診断・
  物理ページ割当・変換表構築・GIC 設定・割込処理を担い、
  `boot.S`/`vectors.S`/`sysreg.S`（暫定アセンブリ）がスタック・ベクタ表・
  システムレジスタ操作を担う。
- 例外: 同期例外を捕捉し ESR_EL1 を復号、`eret` で継続する。
- MMU: レベル1 変換表による 1GiB ブロック恒等写像（RAM/UART/GIC）。
- 割込: GICv2（QEMU `virt`, `gic-version=2`）のディストリビュータ
  0x08000000 と CPU インタフェース 0x08010000 を機械漢文の volatile MMIO で
  設定する。EL1 物理タイマー（PPI 30）を `CNTP_TVAL_EL0`/`CNTP_CTL_EL0` で
  起動し、IRQ はベクタ表（Current EL with SPx, +0x280）から `irq_handler`
  （暫定アセンブリでレジスタと NZCV を保存）を経て機械漢文の
  `公開 記號「irq_dispatch」 術曰「割込處理」` に届く。ハンドラは `GICC_IAR`
  で要因番号を取得し、タイマーを再装填して `GICC_EOIR` で完了、`eret` で
  中断した計算へ戻る。
- 未実装: EL0 行程、スケジューラ、VFS。

## 非目標（初期）
- Linuxバイナリ互換
- GUI・ネットワーク・SMP
- 実機Apple Siliconでの直接ブート
