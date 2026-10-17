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
5. メモリ管理とタイマーを順次有効化する。（MMU: 実装済み。タイマー+GIC割込: 実装済み）

## 例外
- `-kernel` 起動は EL1（SP_EL1）で始まる。`VBAR_EL1` に 2 KiB 整列した
  ベクタ表を設定し、同期例外は `kernel/vectors.S` の共通入口でレジスタを
  保存してから機械漢文ハンドラ `exception_dispatch`（`kernel/kernel.txt`）を
  呼ぶ。ハンドラは ESR_EL1 を復号して診断を出力し、復帰先 ELR_EL1 を返す。

## 割込（GICv2 + 汎用タイマー）
- QEMU `virt,gic-version=2`を前提とする。GIC ディストリビュータ `0x08000000`、
  CPU インタフェース `0x08010000`。
- EL1 物理タイマー（PPI 30）を `CNTP_TVAL_EL0`/`CNTP_CTL_EL0` で起動し、
  `CNTFRQ_EL0`（QEMU virt では 62.5 MHz）から周期を求める。
- IRQ はベクタ表の Current EL with SPx（+0x280）から `irq_handler`
  （`kernel/vectors.S`）に届く。`irq_handler` は x0–x30 と NZCV を保存して
  機械漢文ハンドラ `irq_dispatch`（`kernel/kernel.txt`）を呼び、復帰時に
  すべて復元して `eret` する。
- 例外入口は `PSTATE.DAIF` の I ビットを立てるため、ハンドラ実行中は割込が
  入れ子にならない。`開割込`（`local_irq_enable`）で明示的に I を落とし、
  `待割込`（`wait_irq`）で `wfi` する。
- CPU インタフェースはセキュア状態からのアクセスとなるため、
  `GICC_CTLR.AckCtl`（bit 2）を設定して `GICC_IAR` で Group 1 の要因番号を
  取得する。要因番号は `GICC_EOIR` に書き戻して完了する。

### 機械漢文から見える割込境界（暫定アセンブリ）
| 機械漢文の宣言 | ELF 記号 | 役割 |
|---|---|---|
| `外術曰「始計時」 受「幅」之無符六四` | `timer_start` | `CNTP_TVAL_EL0` 設定 + `CNTP_CTL_EL0` 有効化 |
| `外術曰「再裝計時」 受「幅」之無符六四` | `timer_rearm` | 残量カウンタの再装填 |
| `外術曰「停計時」` | `timer_stop` | タイマー停止 |
| `外術曰「讀周波数」 返 無符六四` | `read_cntfrq` | `CNTFRQ_EL0` の読み出し |
| `外術曰「開割込」` | `local_irq_enable` | `PSTATE.I` の解除 |
| `外術曰「待割込」` | `wait_irq` | `wfi` |

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
