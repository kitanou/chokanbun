# AArch64 ABI・ブート設計（草案）

## ターゲット
- AArch64 little-endian / ARMv8-A
- QEMU `virt`、初期は単一CPU
- 初期ブートはEL1で動く構成を目指す（実際の起動例外レベルを検出して必要なら遷移）
- カーネルとユーザー空間の境界はEL1/EL0

## ブート
1. QEMU virtの起動契約とデバイスツリーを確認する。
2. スタックとBSSを初期化する。（実装: `kernel/boot.S`）
3. UARTを初期化し、最初のログを出す。（実装: `kernel/kernel.txt` の PL011 ドライバ）
4. 例外ベクタを設定する。（実装: `kernel/boot.S` が `VBAR_EL1` に `_vectors` を設定）
5. メモリ管理とタイマーを順次有効化する。（MMU: 実装済み。タイマー: 未実装）

## 例外
- `-kernel` 起動は EL1（SP_EL1）で始まる。`VBAR_EL1` に 2 KiB 整列した
  ベクタ表を設定し、同期例外は `kernel/vectors.S` の共通入口でレジスタを
  保存してから機械漢文ハンドラ `exception_dispatch`（`kernel/kernel.txt`）を
  呼ぶ。ハンドラは ESR_EL1 を復号して診断を出力し、復帰先 ELR_EL1 を返す。

## MMU
- 4 KiB グラニュール、`TTBR0_EL1`、`T0SZ=33`（2 GiB 領域）でレベル1 から
  探索する。1 GiB ブロックで恒等写像する:
  - `0x00000000`–`0x3FFFFFFF` を Device-nGnRnE（PL011 UART、GIC）
  - `0x40000000`–`0x7FFFFFFF` を Normal（RAM、漢極、棧）
- 変換表は機械漢文（`設頁表`）が構築し、システムレジスタ設定のみ
  `kernel/sysreg.S` の `enable_mmu` に委譲する。

## ABI方針
- 通常関数呼出しはAAPCS64に従う。
- 独自syscall ABIはSVCで定義し、番号レジスタ・引数・戻り値・エラー規約を別途固定する。
- 例外入口では保存対象レジスタとスタックアラインメントを厳密に規定する。
- デバイスアドレスを固定値で決め打ちせず、QEMU virtの仕様/DTBを参照する。

## 検証
QEMU + GDBでPC、SP、例外レベル、UART出力、割込動作を確認する。
